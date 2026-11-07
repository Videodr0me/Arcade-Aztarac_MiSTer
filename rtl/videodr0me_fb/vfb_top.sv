// ============================================================================
// Tile-based sparse vector framebuffer and CRT effect pipeline.
// Written 2026 by Videodr0me
// ============================================================================

`default_nettype none

module vfb_top (
	input         wire clk_sys,
	input         wire clk_source,
	input         wire source_tick,
	input         wire reset,
	input         wire video_timing_reset, // Resync output wire without resetting the framebuffer.

	input  wire                           clk_io,
	input  wire                           upload_reset,
	input  wire                           artwork_enable,
	input  wire                           artwork_labels_only,
	input  wire [2:0]                     artwork_blend,
	input  wire [2:0]                     artwork_brightness,
	input  wire [1:0]                     artwork_orientation,
	input  wire [11:0]                    layout_width, layout_height,
	input  wire [1:0]                     layout_orientation,
	output wire                           layout_valid,
	output vfb_layout_pkg::vfb_viewport_t layout_viewport,
	output wire                           artwork_available,
	input  wire                           ioctl_download, ioctl_wr,
	input  wire [15:0]                    ioctl_index,
	input  wire [26:0]                    ioctl_addr,
	input  wire [7:0]                     ioctl_data,
	output wire                           ioctl_wait,

	// Vector input
	input  wire [10:0] X_VECTOR,
	input  wire [10:0] Y_VECTOR,
	input  wire [5:0]  COLOR,   // RRGGBB, 2 bits per gun
	input  wire [7:0]  INTENSITY,
	output        wire SOURCE_READY,
	input         wire IS_DOT,
	input         wire BEAM_ON,

	// Framebuffer DDRAM
	output        wire DDRAM_CLK,
	input         wire DDRAM_BUSY,
	output  wire [7:0] DDRAM_BURSTCNT,
	output wire [28:0] DDRAM_ADDR,
	input  wire [63:0] DDRAM_DOUT,
	input         wire DDRAM_DOUT_READY,
	output        wire DDRAM_RD,
	output wire [63:0] DDRAM_DIN,
	output  wire [7:0] DDRAM_BE,
	output        wire DDRAM_WE,

	// Compressed primary delay
	input  wire [15:0] SDRAM_DQ_IN,
	output wire [15:0] SDRAM_DQ_OUT,
	output        wire SDRAM_DQ_OE,
	output        wire SDRAM_CKE,
	output        wire SDRAM_nCS,
	output        wire SDRAM_nRAS,
	output        wire SDRAM_nCAS,
	output        wire SDRAM_nWE,
	output  wire [1:0] SDRAM_DQM,
	output wire [12:0] SDRAM_A,
	output  wire [1:0] SDRAM_BA,

	// Raster dimensions
	input wire [11:0]  RENDER_WIDTH,
	input wire [11:0]  RENDER_HEIGHT,

	// Video timing and output
	output logic [7:0]  VGA_R,
	output logic [7:0]  VGA_G,
	output logic [7:0]  VGA_B,
	output logic        VGA_HS,
	output logic        VGA_VS,
	output logic        VGA_HBLANK,
	output logic        VGA_VBLANK,

	input  wire [10:0] h_cnt,
	input  wire [10:0] v_cnt,
	input         wire ce_pix,
	input         wire hsync,
	input         wire vsync,
	input         wire hblank,
	input         wire vblank,

	// Frame, buffer, and CRT controls
	input         wire OSD_120HZ,
	input         wire FRAME_DONE,
	input         wire FRAME_START,
	input wire [15:0]  FRAME_TICK_CLKS,
	input   wire [1:0] BUFFER_MODE,
	input   wire [2:0] DOT_MODE,
	output        wire FIFO_FULL_LED,

	input  wire [2:0] osd_bloom_width,
	input  wire [2:0] osd_bloom_curve,
	input  wire [1:0] osd_tone_mapping,
	input  wire [2:0] osd_halo_filter,
	input  wire [2:0] osd_halo_curve,
	input  wire [2:0] osd_halo_knee,
	input  wire [1:0] osd_halo_shape,
	input  wire       halo_grid_8,        // Committed in the renderer clock domain while frozen.
	input  wire [1:0] osd_phosphor_mode,  // 0=Off, 1=LUT A, 2=LUT B, 3=LUT C
	input  wire [1:0] osd_inter_frame_phosphor_mode,
	input  wire [1:0] osd_halo_spread,
	input  wire       osd_color_space,
	input  wire [2:0] osd_presentation_color,
	input  wire       osd_slot_mask,
	input  wire       osd_slot_mask_rows,
	input  wire       full_bypass_active,
	output wire       raw_path_vblank,
	output wire       processed_path_vblank
);

	import vfb_layout_pkg::*;

	localparam TILE_SIZE      = VFB_TILE_SIZE;
	localparam CACHE_COUNT    = 4; // Four cache slots in this integration.
	localparam BUFFER_COUNT   = VFB_BUFFER_COUNT;
	localparam BUF_IDX_W      =  3;
	localparam TILEMAP_ADDR_W = 15;

	// Rasterizer and tile cache
	logic        pixel_valid;
	logic        pixel_ready;
	logic [15:0] pixel_tile_id;
	logic [5:0]  pixel_offset;
	logic [15:0] pixel_data;
	wire         rasterizer_fifo_full_led;


	// Readout and DDRAM arbiter
	wire        readout_ready;
	wire        readout_grant;
	wire [15:0] readout_tile_id;
	wire [63:0] readout_data;
	wire        readout_data_valid;
	wire        flush_done_arbiter;

	// End-of-frame timing
	wire        eof_token;
	wire        eof_token_popped;
	wire [15:0] eof_frame_tick_clks_popped;
	wire [15:0] eof_elapsed_frame_tick_clks_popped;
	wire [15:0] eof_completed_frame_tick_clks;

	// VBLANK display request
	wire vbl_swap_req;

	wire [BUF_IDX_W-1:0] buf_display;
	wire [BUF_IDX_W-1:0] buf_draw;
	wire                 arbiter_idle;
	wire                 arbiter_reset_busy;

	// Reset framebuffer and DDRAM clients.
	assign DDRAM_CLK = clk_sys;

	logic        osd_120hz_vid              = 1'b0;
	logic [1:0]  buffer_mode_vid            = 2'd0;
	logic [2:0]  dot_mode_vid               = 3'd0;
	logic [1:0]  inter_frame_mode_vid       = 2'd0;
	logic [2:0]  osd_halo_knee_vid          = vfb_control_pkg::KNEE_16;
	logic [1:0]  osd_halo_shape_vid         = 2'd0;
	logic [2:0]  osd_bloom_width_vid        = 3'd0;
	logic [1:0]  osd_phosphor_mode_vid      = 2'd0;
	logic [1:0]  osd_halo_spread_vid        = 2'd0;
	logic        osd_color_space_vid        = 1'b0;
	logic [2:0]  osd_presentation_color_vid = 3'd0;
	logic        osd_slot_mask_vid          = 1'b0;
	logic        osd_slot_mask_rows_vid     = 1'b0;
	logic [1:0]  osd_tone_mapping_vid       = vfb_control_pkg::TONE_OFF;
	logic        full_bypass_active_q       = 1'b0;
	logic        halo_grid_8_q              = 1'b0;
	logic [23:0] render_size_q              = {12'd720, 12'd480};

	always_ff @(posedge clk_sys) begin
		full_bypass_active_q <= full_bypass_active;
		halo_grid_8_q        <= halo_grid_8;
		render_size_q        <= {RENDER_WIDTH, RENDER_HEIGHT};
	end

	wire [11:0] render_width_q  = render_size_q[23:12];
	wire [11:0] render_height_q = render_size_q[11:0];

	wire fb_reset_request = reset;
	// Stop new DDR work immediately, but retain the active requester until its
	// Avalon transaction is idle. Reset all clients together at the safe edge.
	wire        fb_client_reset   = arbiter_reset_busy && arbiter_idle;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [1:0] source_reset_sync = 2'b11;
	always_ff @(posedge clk_source)
		source_reset_sync <= {source_reset_sync[0], fb_reset_request};
	wire source_reset = source_reset_sync[1];

	logic filter_reset_q  = 1'b1;
	logic readout_reset_q = 1'b1;
	always_ff @(posedge clk_sys) begin
		// History clears feed black pixels through the live filter timing path.
		filter_reset_q  <= video_timing_reset;
		readout_reset_q <= fb_client_reset | video_timing_reset;
	end

	// Measure frame timing in source clocks and store each frame's draw duration.
	wire [2:0]           draw_idx;
	wire [15:0]          active_frame_tick_clks;
	wire [15:0]          completed_frame_tick_clks;
	wire [2:0]           readout_draw_idx;
	wire [31:0]          readout_age_map;
	wire                 compose_req;
	wire                 compose_done;
	wire [BUF_IDX_W-1:0] compose_source_buf;
	wire [BUF_IDX_W-1:0] compose_target_buf;
	wire                 compose_has_source;
	wire                 compose_source_is_composed;
	wire                 raw_frame_dropped;
	wire [BUF_IDX_W-1:0] raw_frame_dropped_buf;
	wire [2:0]           compose_draw_idx;
	wire [31:0]          compose_age_map;
	wire [3:0]           compose_frame_age;
	wire                 compose_metadata_ready;

	vfb_phosphor_timing #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) phosphor_timing_inst (
		.clk_source(clk_source),
		.source_tick(source_tick),
		.clk_sys(clk_sys),
		.reset_source(source_reset),
		.reset_sys(fb_client_reset),
		.frame_done(FRAME_DONE),
		.frame_start(FRAME_START),
		.frame_tick_clks_in(FRAME_TICK_CLKS),

		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.eof_elapsed_frame_tick_clks_popped(eof_elapsed_frame_tick_clks_popped),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.vbl_swap_req(vbl_swap_req),
		.presentation_120hz(osd_120hz_vid),
		.BUFFER_MODE(buffer_mode_vid),
		.compose_req(compose_req),
		.compose_buf(compose_target_buf),
		.raw_frame_dropped(raw_frame_dropped),
		.raw_frame_dropped_buf(raw_frame_dropped_buf),
		.compose_draw_idx(compose_draw_idx),
		.compose_age_map(compose_age_map),
		.compose_frame_age(compose_frame_age),
		.compose_metadata_ready(compose_metadata_ready),

		.draw_idx(draw_idx),
		.active_frame_tick_clks(active_frame_tick_clks),
		.completed_frame_tick_clks(completed_frame_tick_clks),
		.readout_draw_idx(readout_draw_idx),
		.readout_age_map(readout_age_map)
	);

	vfb_rasterizer #(
		.TILE_SIZE(TILE_SIZE)
	) rasterizer_inst (
		.clk_sys(clk_sys),
		.clk_source(clk_source),
		.reset(fb_client_reset),

		// Vector input
		.X_VECTOR(X_VECTOR),
		.Y_VECTOR(Y_VECTOR),
		.COLOR(COLOR),
		.INTENSITY(INTENSITY),
		.SOURCE_READY(SOURCE_READY),
		.IS_DOT(IS_DOT),
		.BEAM_ON(BEAM_ON),
		.FRAME_DONE(FRAME_DONE),
		.DOT_MODE(dot_mode_vid),
		.FB_WIDTH(render_width_q),
		.FB_HEIGHT(render_height_q),

		// Tile cache output
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),
		.draw_idx(draw_idx),
		.frame_tick_clks(active_frame_tick_clks),
		.completed_frame_tick_clks(completed_frame_tick_clks),


		.eof_token(eof_token),
		.eof_completed_frame_tick_clks(eof_completed_frame_tick_clks),
		.fifo_full_led(rasterizer_fifo_full_led),
		.fifo_empty()
	);

	// Internal connections
	wire        fill_ready, fill_grant;
	wire [28:0] fill_addr;
	wire [7:0]  fill_burstcnt;
	wire [63:0] fill_data;
	wire        fill_data_valid;

	wire        flush_ready, flush_grant, flush_done, flush_advance;
	wire [28:0] flush_addr;
	wire [7:0]  flush_burstcnt;
	wire [63:0] flush_din;
	wire [7:0]  flush_be;

	wire [14:0] display_tile_addr;
	wire        display_tile_dirty;

	wire                      flush_req;
	wire                      clear_req;
	wire [BUF_IDX_W-1:0]      clear_buf_idx;
	wire                      clear_done;
	wire                      has_draw_buf;
	wire [BUFFER_COUNT-1:0]   buf_draw_hot;
	wire                      display_valid;
	wire                      display_is_composed;
	wire [TILEMAP_ADDR_W-1:0] compose_tilemap_addr;
	wire [BUFFER_COUNT-1:0]   compose_tilemap_write_hot;
	wire                      compose_tilemap_write_din;
	wire [BUFFER_COUNT-1:0]   compose_tilemap_dout;

	wire [28:0] display_buf_base = vfb_buffer_base(buf_display);

	vfb_buffer_controller #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) buffer_controller_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),

		.BUFFER_MODE(buffer_mode_vid),
		.inter_frame_mode(inter_frame_mode_vid),

		.eof_token_popped(eof_token_popped),
		.vbl_swap_req(vbl_swap_req),

		.flush_req(flush_req),
		.flush_done(flush_done),

		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),
		.compose_req(compose_req),
		.compose_source_buf(compose_source_buf),
		.compose_target_buf(compose_target_buf),
		.compose_has_source(compose_has_source),
		.compose_source_is_composed(compose_source_is_composed),
		.compose_done(compose_done),

		.buf_draw(buf_draw),
		.buf_display_out(buf_display),
		.display_valid(display_valid),
		.display_is_composed(display_is_composed),

		.has_draw_buf(has_draw_buf),
		.buf_draw_hot(buf_draw_hot),
		.raw_frame_dropped(raw_frame_dropped),
		.raw_frame_dropped_buf(raw_frame_dropped_buf)
	);

	assign FIFO_FULL_LED = rasterizer_fifo_full_led;

	vfb_tile_cache_manager #(
		.TILE_SIZE(TILE_SIZE),
		.CACHE_COUNT(CACHE_COUNT),
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) cache_manager_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),

		.FB_HEIGHT(render_height_q),

		// Rasterizer
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),

		.eof_token(eof_token),
		.eof_completed_frame_tick_clks(eof_completed_frame_tick_clks),

		// Buffer controller
		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.eof_elapsed_frame_tick_clks_popped(eof_elapsed_frame_tick_clks_popped),
		.flush_req(flush_req),
		.flush_done(flush_done),
		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.display_valid(display_valid),
		.has_draw_buf(has_draw_buf),
		.buf_draw_hot(buf_draw_hot),

		// DDRAM arbiter
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done_in(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),

		.display_tile_addr(display_tile_addr),
		.display_tile_dirty(display_tile_dirty),
		.compose_tilemap_addr(compose_tilemap_addr),
		.compose_tilemap_write_hot(compose_tilemap_write_hot),
		.compose_tilemap_write_din(compose_tilemap_write_din),
		.compose_tilemap_dout(compose_tilemap_dout)
	);

	wire [28:0] readout_addr = display_buf_base + ({13'd0, readout_tile_id} << 4);
	wire [8:0]  readout_burstcnt;

	wire        compose_read_ready;
	wire        compose_read_grant;
	wire [28:0] compose_read_addr;
	wire [7:0]  compose_read_burstcnt;
	wire [63:0] compose_read_data;
	wire        compose_read_data_valid;
	wire        compose_write_ready;
	wire        compose_write_grant;
	wire        compose_write_done;
	wire [28:0] compose_write_addr;
	wire [7:0]  compose_write_burstcnt;
	wire [63:0] compose_write_data;
	wire [7:0]  compose_write_be;
	wire        compose_write_advance;

	vfb_phosphor_compositor #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W),
		.TILEMAP_ADDR_W(TILEMAP_ADDR_W)
	) phosphor_compositor_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),
		.render_width(render_width_q),
		.render_height(render_height_q),
		.intra_frame_mode(osd_phosphor_mode_vid),
		.inter_frame_mode(inter_frame_mode_vid),
		.compose_req(compose_req),
		.compose_source_buf(compose_source_buf),
		.compose_target_buf(compose_target_buf),
		.compose_has_source(compose_has_source),
		.compose_source_is_composed(compose_source_is_composed),
		.compose_done(compose_done),
		.raw_reference_draw_idx(compose_draw_idx),
		.raw_age_map(compose_age_map),
		.raw_frame_age(compose_frame_age),
		.raw_metadata_ready(compose_metadata_ready),
		.tilemap_addr(compose_tilemap_addr),
		.tilemap_write_hot(compose_tilemap_write_hot),
		.tilemap_write_din(compose_tilemap_write_din),
		.tilemap_dout(compose_tilemap_dout),
		.read_ready(compose_read_ready),
		.read_grant(compose_read_grant),
		.read_addr(compose_read_addr),
		.read_burstcnt(compose_read_burstcnt),
		.read_data(compose_read_data),
		.read_data_valid(compose_read_data_valid),
		.write_ready(compose_write_ready),
		.write_grant(compose_write_grant),
		.write_done(compose_write_done),
		.write_addr(compose_write_addr),
		.write_burstcnt(compose_write_burstcnt),
		.write_data(compose_write_data),
		.write_be(compose_write_be),
		.write_advance(compose_write_advance)
	);


	wire        upload_write_ready, upload_write_done, upload_write_advance;
	wire [28:0] upload_write_addr;
	wire [7:0]  upload_write_burstcnt, upload_write_be;
	wire [63:0] upload_write_data;
	wire        artwork_read_ready, artwork_read_grant, artwork_read_data_valid;
	wire [28:0] artwork_read_addr;
	wire [7:0]  artwork_read_burstcnt;
	wire [63:0] artwork_read_data;
	vfb_ddr_arbiter ddr_arbiter_inst (
		.clk_sys(clk_sys),
		.rst_sys(fb_reset_request),

		// DDRAM Avalon-MM
		.DDRAM_BUSY(DDRAM_BUSY),
		.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
		.DDRAM_ADDR(DDRAM_ADDR),
		.DDRAM_RD(DDRAM_RD),
		.DDRAM_WE(DDRAM_WE),
		.DDRAM_DIN(DDRAM_DIN),
		.DDRAM_BE(DDRAM_BE),
		.DDRAM_DOUT(DDRAM_DOUT),
		.DDRAM_DOUT_READY(DDRAM_DOUT_READY),

		// Readout
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_addr(readout_addr),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		// Fill
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		// Flush
		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),
		.compose_read_ready(compose_read_ready),
		.compose_read_grant(compose_read_grant),
		.compose_read_addr(compose_read_addr),
		.compose_read_burstcnt(compose_read_burstcnt),
		.compose_read_data(compose_read_data),
		.compose_read_data_valid(compose_read_data_valid),
		.compose_write_ready(compose_write_ready),
		.compose_write_grant(compose_write_grant),
		.compose_write_done(compose_write_done),
		.compose_write_addr(compose_write_addr),
		.compose_write_burstcnt(compose_write_burstcnt),
		.compose_write_data(compose_write_data),
		.compose_write_be(compose_write_be),
		.compose_write_advance(compose_write_advance),


		.upload_write_ready(upload_write_ready), .upload_write_done(upload_write_done),
		.upload_write_addr(upload_write_addr), .upload_write_burstcnt(upload_write_burstcnt),
		.upload_write_data(upload_write_data), .upload_write_be(upload_write_be),
		.upload_write_advance(upload_write_advance),
		.artwork_read_ready(artwork_read_ready), .artwork_read_grant(artwork_read_grant),
		.artwork_read_addr(artwork_read_addr), .artwork_read_burstcnt(artwork_read_burstcnt),
		.artwork_read_data(artwork_read_data), .artwork_read_data_valid(artwork_read_data_valid),
		.arbiter_idle(arbiter_idle),
		.reset_busy(arbiter_reset_busy)
	);

	wire [7:0]  raw_vga_r;
	wire [7:0]  raw_vga_g;
	wire [7:0]  raw_vga_b;
	wire [13:0] raw_canonical_pixel;
	wire        raw_vga_hs;
	wire        raw_vga_vs;
	wire        raw_vga_hblank;
	wire        raw_vga_vblank;

	// Synchronize menu options.
	wire [36:0] osd_control_in = {
		osd_halo_shape,                 // [36:35]
		OSD_120HZ,                      // [34]
		BUFFER_MODE,                    // [33:32]
		DOT_MODE,                       // [31:29]
		osd_inter_frame_phosphor_mode,  // [28:27]
		osd_halo_knee,                  // [26:24]
		osd_halo_curve,
		osd_tone_mapping,
		osd_slot_mask_rows,
		osd_slot_mask,
		osd_presentation_color,
		osd_color_space,
		osd_halo_spread,
		osd_phosphor_mode,
		osd_halo_filter,
		osd_bloom_curve,
		osd_bloom_width
	};

	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [36:0] osd_control_meta   =     '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [36:0] osd_control_sync   =     '0;
	logic [36:0] osd_control_sync_d =     '0;
	logic [36:0] osd_control_stable =     '0;
	logic [9:0]  bloom_curve_gain   = 10'd64;
	logic [9:0]  halo_curve_gain    = 10'd64;
	logic [7:0]  halo_filter        =   8'd0;

	function automatic [9:0] decode_curve_gain(
		input logic [2:0] sel
	);
		begin
			decode_curve_gain =
				(sel == 3'd0) ? 10'd64  :  // Minimal
				(sel == 3'd1) ? 10'd96  :  // Min+
				(sel == 3'd2) ? 10'd128 :  // Mild
				(sel == 3'd3) ? 10'd192 :  // Mild+
				(sel == 3'd4) ? 10'd256 :  // Moderate
				(sel == 3'd5) ? 10'd320 :  // Mod+
				(sel == 3'd6) ? 10'd384 :  // Strong-
				                  10'd512 ; // Strong
		end
	endfunction

	function automatic [7:0] decode_halo_filter(
		input logic [2:0] sel
	);
		begin
			decode_halo_filter =
				(sel == 3'd0) ? 8'd0  :  // Off
				(sel == 3'd1) ? 8'd8  :  // 0.25x
				(sel == 3'd2) ? 8'd11 :  // 0.33x
				(sel == 3'd3) ? 8'd16 :  // 0.5x
				(sel == 3'd4) ? 8'd24 :  // 0.75x
				(sel == 3'd5) ? 8'd32 :  // 1.0x
				(sel == 3'd6) ? 8'd40 :  // 1.25x
				                  8'd48 ; // 1.5x
		end
	endfunction

	always_ff @(posedge clk_sys) begin
		osd_control_meta   <= osd_control_in;
		osd_control_sync   <= osd_control_meta;
		osd_control_sync_d <= osd_control_sync;
		if (osd_control_sync == osd_control_sync_d) osd_control_stable <= osd_control_sync;

		osd_bloom_width_vid        <= osd_control_stable[2:0];
		bloom_curve_gain           <= decode_curve_gain(osd_control_stable[5:3]);
		halo_filter                <= decode_halo_filter(osd_control_stable[8:6]);
		osd_phosphor_mode_vid      <= osd_control_stable[10:9];
		osd_halo_spread_vid        <= osd_control_stable[12:11];
		osd_color_space_vid        <= osd_control_stable[13];
		osd_presentation_color_vid <= osd_control_stable[16:14];
		osd_slot_mask_vid          <= osd_control_stable[17];
		osd_slot_mask_rows_vid     <= osd_control_stable[18];
		halo_curve_gain            <= decode_curve_gain(osd_control_stable[23:21]);
		osd_halo_knee_vid          <= osd_control_stable[26:24];
		inter_frame_mode_vid       <= osd_control_stable[28:27];
		dot_mode_vid               <= osd_control_stable[31:29];
		buffer_mode_vid            <= osd_control_stable[33:32];
		osd_120hz_vid              <= osd_control_stable[34];
		osd_halo_shape_vid         <= osd_control_stable[36:35];
		if (ce_pix && vblank) osd_tone_mapping_vid <= osd_control_stable[20:19];
	end

	vfb_readout #(
		.TILE_SIZE(TILE_SIZE)
	) readout_inst (
		.clk_sys(clk_sys),
		.reset(readout_reset_q),
		.video_timing_reset(video_timing_reset),

		// DDRAM arbiter interface
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_tile_id(readout_tile_id),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		.vbl_swap_req(vbl_swap_req),

		// Readout output
		.VGA_R(raw_vga_r),
		.VGA_G(raw_vga_g),
		.VGA_B(raw_vga_b),
		.CANONICAL_PIXEL(raw_canonical_pixel),
		.VGA_HS(raw_vga_hs),
		.VGA_VS(raw_vga_vs),
		.VGA_HBLANK(raw_vga_hblank),
		.VGA_VBLANK(raw_vga_vblank),

		.display_tile_addr(display_tile_addr),
		.display_tile_dirty(display_tile_dirty),

		.h_cnt(h_cnt),
		.v_cnt(v_cnt),
		.ce_pix(ce_pix),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank),

		.RENDER_WIDTH(render_width_q),
		.RENDER_HEIGHT(render_height_q),
		.draw_idx(readout_draw_idx),
		.phosphor_age_map(readout_age_map),
		.osd_phosphor_mode(osd_phosphor_mode_vid),
		.tone_mapping(osd_tone_mapping_vid),
		.display_is_composed(display_is_composed)
	);

	wire   [7:0] filtered_vga_r;
	wire   [7:0] filtered_vga_g;
	wire   [7:0] filtered_vga_b;
	wire         filtered_vga_hs;
	wire         filtered_vga_vs;
	wire         filtered_vga_hblank;
	wire         filtered_vga_vblank;
	assign       raw_path_vblank       = VGA_VBLANK;
	assign       processed_path_vblank = VGA_VBLANK;

	vfb_halo_pipeline filter_inst (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.reset(filter_reset_q),

		.osd_bloom_width(osd_bloom_width_vid),
		.bloom_curve_gain(bloom_curve_gain),
		.halo_curve_gain(halo_curve_gain),
		.halo_filter(halo_filter),
		.halo_spread_mode(osd_halo_spread_vid),
		.halo_knee_mode(osd_halo_knee_vid),
		.halo_shape(osd_halo_shape_vid),
		.halo_grid_8(halo_grid_8_q),
		.active_height(render_height_q),
		.color_space_g08_709(osd_color_space_vid),
		.presentation_color(osd_presentation_color_vid),
		.slot_mask_enable(osd_slot_mask_vid),
		.slot_mask_rows(osd_slot_mask_rows_vid),
		.tone_mapping(osd_tone_mapping_vid),

		.CANONICAL_IN(raw_canonical_pixel),
		.VGA_R_IN(raw_vga_r),
		.VGA_G_IN(raw_vga_g),
		.VGA_B_IN(raw_vga_b),
		.VGA_HS_IN(raw_vga_hs),
		.VGA_VS_IN(raw_vga_vs),
		.VGA_HBLANK_IN(raw_vga_hblank),
		.VGA_VBLANK_IN(raw_vga_vblank),

		.VGA_R_OUT(filtered_vga_r),
		.VGA_G_OUT(filtered_vga_g),
		.VGA_B_OUT(filtered_vga_b),
		.VGA_HS_OUT(filtered_vga_hs),
		.VGA_VS_OUT(filtered_vga_vs),
		.VGA_HBLANK_OUT(filtered_vga_hblank),
		.VGA_VBLANK_OUT(filtered_vga_vblank),

		.sdram_data_in(SDRAM_DQ_IN),
		.sdram_data_out(SDRAM_DQ_OUT),
		.sdram_data_oe(SDRAM_DQ_OE),
		.sdram_cke(SDRAM_CKE),
		.sdram_cs(SDRAM_nCS),
		.sdram_ras(SDRAM_nRAS),
		.sdram_cas(SDRAM_nCAS),
		.sdram_we(SDRAM_nWE),
		.sdram_dqm(SDRAM_DQM),
		.sdram_addr(SDRAM_A),
		.sdram_ba(SDRAM_BA),
		// Debug-only fault outputs; intentionally unused in release RTL.
		.sdram_overflow(),
		.sdram_underflow(),
		.sdram_init_done()
	);

	logic [7:0] selected_r, selected_g, selected_b;
	logic       selected_hs, selected_vs, selected_hblank, selected_vblank;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [6:0] artwork_meta=0, artwork_sync=0;
	logic [6:0] artwork_prev=0, artwork_stable=0;
	always_ff @(posedge clk_sys) begin
		artwork_meta <= {artwork_brightness,artwork_enable,artwork_blend};
		artwork_sync <= artwork_meta;
		artwork_prev <= artwork_sync;
		if (artwork_sync == artwork_prev) artwork_stable <= artwork_sync;
	end
	vfb_overlay artwork_overlay (
		.clk_sys(clk_sys), .clk_io(clk_io), .reset(fb_client_reset),
		.upload_reset(upload_reset), .arbiter_ready(!arbiter_reset_busy || arbiter_idle),
		.video_timing_reset(video_timing_reset), .processed_path_active(1'b1),
		.artwork_enable(artwork_stable[3]), .artwork_blend(artwork_stable[2:0]),
		.artwork_labels_only(artwork_labels_only),
		.artwork_brightness(artwork_stable[6:4]), .artwork_orientation(artwork_orientation),
		.layout_width(layout_width), .layout_height(layout_height),
		.layout_orientation(layout_orientation), .layout_valid(layout_valid),
		.layout_viewport(layout_viewport),
		.render_width(render_width_q), .render_height(render_height_q),
		.artwork_available(artwork_available),
		.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data), .ioctl_wait(ioctl_wait),
		.ce_pix(ce_pix), .video_r_in(selected_r), .video_g_in(selected_g), .video_b_in(selected_b),
		.video_hs_in(selected_hs), .video_vs_in(selected_vs),
		.video_hblank_in(selected_hblank), .video_vblank_in(selected_vblank),
		.video_r_out(VGA_R), .video_g_out(VGA_G), .video_b_out(VGA_B),
		.video_hs_out(VGA_HS), .video_vs_out(VGA_VS),
		.video_hblank_out(VGA_HBLANK), .video_vblank_out(VGA_VBLANK),

		.upload_write_ready(upload_write_ready), .upload_write_done(upload_write_done),
		.upload_write_addr(upload_write_addr), .upload_write_burstcnt(upload_write_burstcnt),
		.upload_write_data(upload_write_data), .upload_write_be(upload_write_be),
		.upload_write_advance(upload_write_advance),
		.artwork_read_ready(artwork_read_ready), .artwork_read_grant(artwork_read_grant),
		.artwork_read_addr(artwork_read_addr), .artwork_read_burstcnt(artwork_read_burstcnt),
		.artwork_read_data(artwork_read_data), .artwork_read_data_valid(artwork_read_data_valid)
	);
	// Full bypass selects the unfiltered readout at a boundary chosen by the
	// video mode controller.
	always_ff @(posedge clk_sys) begin
		if (video_timing_reset) begin
			selected_r      <= 8'd0;
			selected_g      <= 8'd0;
			selected_b      <= 8'd0;
			selected_hs     <= 1'b1;
			selected_vs     <= 1'b1;
			selected_hblank <= 1'b1;
			selected_vblank <= 1'b1;
		end else begin
			if (ce_pix && full_bypass_active_q) begin
				selected_r      <= fb_client_reset ? 8'd0 : raw_vga_r;
				selected_g      <= fb_client_reset ? 8'd0 : raw_vga_g;
				selected_b      <= fb_client_reset ? 8'd0 : raw_vga_b;
				selected_hs     <= raw_vga_hs;
				selected_vs     <= raw_vga_vs;
				selected_hblank <= raw_vga_hblank;
				selected_vblank <= raw_vga_vblank;
			end else if (ce_pix) begin
				selected_r      <= fb_client_reset ? 8'd0 : filtered_vga_r;
				selected_g      <= fb_client_reset ? 8'd0 : filtered_vga_g;
				selected_b      <= fb_client_reset ? 8'd0 : filtered_vga_b;
				selected_hs     <= filtered_vga_hs;
				selected_vs     <= filtered_vga_vs;
				selected_hblank <= filtered_vga_hblank;
				selected_vblank <= filtered_vga_vblank;
			end
		end
	end

endmodule

`default_nettype wire

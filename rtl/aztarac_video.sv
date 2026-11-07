//============================================================================
//  Aztarac video timing, endpoint scaling, and framebuffer integration
//  Copyright (C) 2026 Videodr0me
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module aztarac_video
#(
	parameter logic [24:0] HEIGHT_STABLE_CYCLES = 25'd25_000_000
)
(
	input  wire        clk_sys,  // 50 MHz machine domain
	input  wire        clk_125,
	input  wire        reset,
	input  wire        upload_reset,
	input  wire        reset_source,

	input  wire        direct_video,
	input  wire        direct_video_31khz,
	input  wire        crt_15khz_480i,
	input  wire [2:0]  crt_vertical_position,
	input  wire [2:0]  crt_horizontal_position,
	input  wire [11:0] hdmi_width, hdmi_height,
	input  wire [1:0]  aspect_ratio,
	input  wire [1:0]  orientation,
	output wire [1:0]  active_orientation,

	input  wire signed [11:0] vector_x0, vector_y0, vector_x1, vector_y1,
	input  wire        [5:0]  vector_color,
	input  wire        [7:0]  vector_intensity,
	input  wire               vector_valid, frame_done,
	output wire               vector_ready, vector_overflow,

	input  wire        artwork_enable,
	input  wire        artwork_labels_only,
	input  wire [2:0]  artwork_blend,
	input  wire [2:0]  artwork_brightness,
	output wire        artwork_available,
	input  wire        ioctl_download, ioctl_wr,
	input  wire [15:0] ioctl_index,
	input  wire [26:0] ioctl_addr,
	input  wire [7:0]  ioctl_data,
	output wire        ioctl_wait,

	// OSD
	input wire                                    osd_120hz,
	input wire [1:0]                              osd_buffer_mode,
	input wire [1:0]                              osd_halo_shape,
	input wire                                    effects_bypass,
	input vfb_control_pkg::vfb_profile_settings_t resolved_settings,

	output logic [12:0] video_arx,
	output logic [12:0] video_ary,
	output wire         ce_pixel,
	output wire         hblank,
	output wire         vblank,
	output wire   [7:0] video_r,
	output wire   [7:0] video_g,
	output wire   [7:0] video_b,
	output wire         hsync,
	output wire         vsync,
	output wire         field,
	output wire         mode_supports_120hz,
	output wire         mode_is_15khz,
	output wire         mode_is_crt,
	output wire         video_mode_toggle,
	output wire         video_freeze,
	output wire [1:0]   profile_resolution,
	output wire         fifo_full,

	// DDRAM
	output wire         ddram_clk,
	input  wire         ddram_busy,
	output wire   [7:0] ddram_burst_count,
	output wire  [28:0] ddram_address,
	input  wire  [63:0] ddram_data_out,
	input  wire         ddram_data_ready,
	output wire         ddram_read,
	output wire  [63:0] ddram_data_in,
	output wire   [7:0] ddram_byte_enable,
	output wire         ddram_write,

	// SDRAM (halo alignment delay)
	input  wire  [15:0] sdram_data_in,
	output wire  [15:0] sdram_data_out,
	output wire         sdram_data_oe,
	output wire         sdram_cke,
	output wire         sdram_ncs,
	output wire         sdram_nras,
	output wire         sdram_ncas,
	output wire         sdram_nwe,
	output wire   [1:0] sdram_dqm,
	output wire  [12:0] sdram_address,
	output wire   [1:0] sdram_bank
);

	// Qualify one HDMI size per session. Direct Video uses its 15/31 kHz selection.
	typedef struct packed {
		logic [11:0] width, height;
	} display_size_t;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	display_size_t hdmi_size_meta_50 = '0, hdmi_size_sync_50 = '0;
	display_size_t size_candidate_50 = '0, size_stable_50 = '0;
	logic [24:0]   size_timer_50     = 25'd0;
	logic          size_direct_50    = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        direct_video_meta_50 = 1'b0, direct_video_sync_50 = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        direct_31khz_meta_50 = 1'b0, direct_31khz_sync_50 = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        upload_reset_50_meta = 1'b1, upload_reset_50 = 1'b1;
	display_size_t requested_size_50;
	assign requested_size_50 = direct_video_sync_50 ?
	                           {12'd0, (direct_31khz_sync_50 ? 12'd480 : 12'd240)} :
	                           hdmi_size_sync_50;

	always_ff @(posedge clk_sys) begin
		upload_reset_50_meta <= upload_reset;
		upload_reset_50      <= upload_reset_50_meta;
		direct_video_meta_50 <= direct_video;
		direct_video_sync_50 <= direct_video_meta_50;
		direct_31khz_meta_50 <= direct_video_31khz;
		direct_31khz_sync_50 <= direct_31khz_meta_50;
		hdmi_size_meta_50    <= {hdmi_width, hdmi_height};
		hdmi_size_sync_50    <= hdmi_size_meta_50;
		size_direct_50       <= direct_video_sync_50;
		if (upload_reset_50 || size_direct_50 != direct_video_sync_50) begin
			size_candidate_50 <= '0;
			size_stable_50    <= '0;
			size_timer_50     <= 25'd0;
		end else if (size_stable_50.height == 0 || direct_video_sync_50) begin
			if (requested_size_50.height <= 12'd200 || (!direct_video_sync_50 && requested_size_50.width == 0) ||
			    requested_size_50 != size_candidate_50) begin
				size_candidate_50 <= requested_size_50;
				size_timer_50     <= 25'd0;
			end else if (size_candidate_50 != size_stable_50) begin
				if (size_timer_50 < HEIGHT_STABLE_CYCLES - 1'd1)
					size_timer_50 <= size_timer_50 + 1'd1;
				else begin
					size_stable_50 <= size_candidate_50;
					size_timer_50  <= 25'd0;
				end
			end
		end
	end

	wire  [39:0] control_in = {crt_horizontal_position, crt_vertical_position,
	                           resolved_settings.halo_grid, size_stable_50.width, artwork_labels_only,
	                           orientation, artwork_enable, size_stable_50.height, osd_120hz,
	                           effects_bypass, size_direct_50, direct_31khz_sync_50, crt_15khz_480i};
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [39:0] control_meta = '0, control_sync = '0;
	logic [39:0] control_sync_d = '0;
	logic [39:0] control_stable = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        upload_reset_125_meta = 1'b1, upload_reset_125 = 1'b1;

	always_ff @(posedge clk_125) begin
		upload_reset_125_meta <= upload_reset;
		upload_reset_125      <= upload_reset_125_meta;
		control_meta          <= control_in;
		control_sync          <= control_meta;
		control_sync_d        <= control_sync;
		if (control_sync == control_sync_d) control_stable <= control_sync;
	end

	typedef struct packed {
		logic [11:0]                   height;
		logic                          mode_120hz;
		logic                          interlaced;
		logic [1:0]                    orient;
		logic                          framed;
		logic                          labels_only;
		logic                          sd_pixel_aspect;
		logic                          halo_grid;
		vfb_layout_pkg::vfb_viewport_t viewport;
	} mode_key_t;

	localparam logic [1:0] PIXEL_FULL       = 2'd0;
	localparam logic [1:0] PIXEL_HALF       = 2'd1;
	localparam logic [1:0] PIXEL_FRACTIONAL = 2'd2;
	// Fractional modes emit step / (step + wrap) pixel events per clock.

	typedef struct packed {
		logic [11:0] fb_width;
		logic [11:0] fb_height;
		logic [11:0] h_total;
		logic [11:0] v_total;
		logic [11:0] hs_start;
		logic [11:0] hs_end;
		logic [11:0] vs_start;
		logic [11:0] vs_end;
		logic  [1:0] pixel_mode;
		logic [17:0] pixel_step;
		logic [17:0] pixel_wrap;
		logic        is_1080p;
		logic        is_720p;
		logic        is_480p;
		logic        is_240p;
		logic        is_120hz;
		logic        is_interlaced;
		logic signed [4:0] crt_vertical_offset;
	} video_mode_t;

	function automatic video_mode_t decode_video_mode(
		input logic [11:0] height,
		input logic        requested_120hz,
		input logic        requested_interlace,
		input logic [2:0]  vertical_position, horizontal_position
	);
		video_mode_t mode;
		logic signed [4:0] offset, horizontal_offset;
		begin
			case (vertical_position)
				3'd1:    offset = height < 12'd480 ?  5'sd2 :  5'sd4;
				3'd2:    offset = height < 12'd480 ?  5'sd4 :  5'sd8;
				3'd3:    offset = height < 12'd480 ?  5'sd6 :  5'sd12;
				3'd4:    offset = height < 12'd480 ? -5'sd2 : -5'sd4;
				3'd5:    offset = height < 12'd480 ? -5'sd4 : -5'sd8;
				3'd6:    offset = height < 12'd480 ? -5'sd6 : -5'sd10;
				default: offset = 5'sd0;
			endcase
			case (horizontal_position)
				3'd1:    horizontal_offset =  5'sd4;
				3'd2:    horizontal_offset =  5'sd8;
				3'd3:    horizontal_offset =  5'sd12;
				3'd4:    horizontal_offset = -5'sd4;
				3'd5:    horizontal_offset = -5'sd8;
				3'd6:    horizontal_offset = -5'sd12;
				default: horizontal_offset =  5'sd0;
			endcase

			mode            =       '0;
			mode.fb_width   =  12'd960;
			mode.fb_height  =  12'd720;
			mode.h_total    = 12'd1388;
			mode.v_total    =  12'd748;
			mode.hs_start   = 12'd1108;
			mode.hs_end     = 12'd1196;
			mode.vs_start   =  12'd728;
			mode.vs_end     =  12'd733;
			mode.pixel_mode = requested_120hz ? PIXEL_FULL : PIXEL_HALF;
			mode.is_720p    = 1'b1;
			mode.is_120hz   = requested_120hz;

			if ((height >= 12'd1080) && (height < 12'd1400)) begin
				mode.fb_width   = 12'd1440;
				mode.fb_height  = 12'd1080;
				mode.h_total    = 12'd1851;
				mode.v_total    = 12'd1124;
				mode.hs_start   = 12'd1600;
				mode.hs_end     = 12'd1688;
				mode.vs_start   = 12'd1088;
				mode.vs_end     = 12'd1093;
				mode.pixel_mode = PIXEL_FULL;
				mode.is_1080p   = 1'b1;
				mode.is_720p    = 1'b0;
				mode.is_120hz   = 1'b0;
			end else if (height < 12'd480) begin
				mode.fb_width   = 12'd720;
				mode.fb_height  = 12'd240;
				mode.h_total    = 12'd883;
				mode.v_total    = 12'd263;
				mode.vs_start   = 12'(13'sd246 - offset);
				mode.vs_end     = 12'(13'sd249 - offset);
				mode.crt_vertical_offset = offset;
				mode.pixel_mode = PIXEL_FRACTIONAL;
				mode.pixel_step =  18'd884;
				mode.pixel_wrap = 18'd7015;
				mode.is_720p    =     1'b0;
				mode.is_240p    =     1'b1;
				mode.is_120hz   =     1'b0;
			end else if (height < 12'd720) begin
				mode.fb_width      = 12'd720;
				mode.fb_height     = 12'd480;
				mode.h_total       = 12'd883;
				mode.v_total       = 12'd528;
				mode.vs_start      = 12'(13'sd493 - offset);
				mode.vs_end        = 12'(13'sd499 - offset);
				mode.crt_vertical_offset = offset;
				mode.pixel_mode    = PIXEL_FRACTIONAL;
				mode.pixel_step    =  18'd442;
				mode.pixel_wrap    = 18'd1529;
				mode.is_720p       =     1'b0;
				mode.is_480p       =     1'b1;
				mode.is_120hz      =     1'b0;
				mode.is_interlaced = requested_interlace;
			end

			if (height < 12'd720) begin
				// Earlier sync moves the entire active picture right on a CRT.
				mode.hs_start = 12'(13'sd755 - horizontal_offset);
				mode.hs_end   = 12'(13'sd821 - horizontal_offset);
			end
			decode_video_mode = mode;
		end
	endfunction

	function automatic logic [1:0] height_class(input logic [11:0] height);
		begin
			if (height < 12'd480)
				height_class = 2'd0;
			else if (height < 12'd720)
				height_class = 2'd1;
			else if ((height >= 12'd1080) && (height < 12'd1400))
				height_class = 2'd3;
			else
				height_class = 2'd2;
		end
	endfunction

	wire  [11:0]                   stable_height       = control_stable[16:5];
	wire                           stable_120hz        = control_stable[4];
	wire                           request_bypass      = control_stable[3];
	wire                           stable_direct_video = control_stable[2];
	wire                           stable_direct_31khz = control_stable[1];
	wire                           stable_480i         = control_stable[0];
	wire  [1:0]                    request_orientation = control_stable[19:18] == 3 ?
	                                                     2'd0 :
	                                                     control_stable[19:18];
	wire                           layout_valid;
	vfb_layout_pkg::vfb_viewport_t layout_viewport;
	wire                           height_supports_120hz = !stable_direct_video &&
	                                                       (stable_height >= 12'd720) &&
	                                                       (stable_height <= 12'd768);
	logic [11:0]                   request_height;
	logic                          request_interlaced;

	always_comb begin
		request_height     = stable_height;
		request_interlaced = 1'b0;
		if (stable_direct_video) begin
			request_height     = stable_direct_31khz ? 12'd480 : (stable_480i ? 12'd480 : 12'd240);
			request_interlaced = !stable_direct_31khz && stable_480i;
		end else if (stable_height < 12'd480) begin
			request_height     = stable_480i ? 12'd480 : 12'd240;
			request_interlaced = stable_480i;
		end
	end

	wire request_120hz = stable_120hz && height_supports_120hz;
	// The layout query, match, selection and viewport take four clocks.
	// Seven unchanged control clocks allow that lookup to settle before capture.
	logic [39:0] layout_control_q = '0;
	logic [2:0]  layout_settle    =  0;
	always_ff @(posedge clk_125) begin
		layout_control_q <= control_stable;
		if (layout_control_q != control_stable) layout_settle <= 0;
		else if (!(&layout_settle)) layout_settle <= layout_settle + 1'b1;
	end
	wire         request_valid = stable_height > 12'd200 && (&layout_settle) &&
	                             layout_control_q == control_stable;
	mode_key_t   request_key;
	video_mode_t requested_mode;
	assign       request_key = '{height:request_height, mode_120hz:request_120hz,
	    interlaced:request_interlaced, orient:request_orientation,
	    framed:control_stable[17] && layout_valid,
	    labels_only:control_stable[20],
	    halo_grid:control_stable[33],
	    sd_pixel_aspect:control_stable[32:21] == 12'd720 && stable_height < 12'd720,
	    viewport:control_stable[17] && layout_valid ? layout_viewport :
	        {24'd0,requested_mode.fb_width,requested_mode.fb_height}};
	always_comb requested_mode = decode_video_mode(request_height, request_120hz,
	                                               request_interlaced, control_stable[36:34], control_stable[39:37]);

	typedef enum logic [2:0] {
		MODE_WAIT_START,
		MODE_START_TIMING,
		MODE_START_HOLD,
		MODE_RUN,
		MODE_WAIT_ACTIVE_VBLANK,
		MODE_WAIT_TIMING_WRAP,
		MODE_WAIT_TARGET_VBLANK,
		MODE_HOLD_TARGET_FRAME
	} mode_state_t;

	mode_state_t mode_state           = MODE_WAIT_START;
	mode_key_t   key_active_q         = '{height:12'd480, default:'0};
	mode_key_t   key_pending_q        = '{height:12'd480, default:'0};
	video_mode_t mode_q               = decode_video_mode(12'd480, 1'b0, 1'b0, 3'd0, 3'd0);
	video_mode_t pending_mode_q       = decode_video_mode(12'd480, 1'b0, 1'b0, 3'd0, 3'd0);
	logic        mode_ready           = 1'b0;
	logic        video_mode_toggle_q  = 1'b0;
	logic        video_freeze_q       = 1'b1;
	logic        active_bypass_q      = 1'b0;
	logic        pending_bypass_q     = 1'b0;
	logic        transition_timing_q  = 1'b0;
	logic        transition_restart_q = 1'b0;
	logic        mode_restart_q       = 1'b0;
	logic        frame_wrap;
	logic        raw_path_vblank;
	logic        processed_path_vblank;
	logic        raw_path_vblank_q       = 1'b1;
	logic        processed_path_vblank_q = 1'b1;
	logic        output_vblank_q         = 1'b1;
	logic        output_vblank_entry_q   = 1'b0;

	wire        raw_path_vblank_entry           = raw_path_vblank && !raw_path_vblank_q;
	wire        processed_path_vblank_entry     = processed_path_vblank && !processed_path_vblank_q;
	wire        progressive_active_vblank_entry = active_bypass_q ? raw_path_vblank_entry
	                                                              : processed_path_vblank_entry;
	wire        progressive_target_vblank_entry = pending_bypass_q ? raw_path_vblank_entry
	                                                               : processed_path_vblank_entry;
	wire        active_path_vblank_entry        = key_active_q.interlaced ?
	                                              output_vblank_entry_q :
	                                              progressive_active_vblank_entry;
	wire        target_path_vblank_entry        = key_pending_q.interlaced ?
	                                              output_vblank_entry_q :
	                                              progressive_target_vblank_entry;
	wire        request_mode_changed            = (request_key != key_active_q) ||
	                                              (requested_mode.hs_start != mode_q.hs_start) ||
	                                              (requested_mode.crt_vertical_offset != mode_q.crt_vertical_offset);
	wire        request_changed                 = request_mode_changed || (request_bypass != active_bypass_q);
	// Grid changes commit at frame wrap without restarting raster timing.
	wire        request_timing_changed = requested_mode != mode_q;
	wire        profile_path_commit    = (mode_state == MODE_WAIT_TARGET_VBLANK) &&
	                                     (transition_restart_q ? frame_wrap
	                                                           : target_path_vblank_entry) &&
	                                     (pending_bypass_q != active_bypass_q);
	wire        mode_commit            = (mode_state == MODE_WAIT_TIMING_WRAP) && frame_wrap &&
	                                     transition_timing_q;
	wire        timing_reset           = !mode_ready;
	logic       mode_commit_q          = 1'b0;
	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || timing_reset)
			mode_commit_q <= 1'b0;
		else
			// Porch adjustments preserve the pixel divider, line buffers and field parity.
			mode_commit_q <= mode_commit && ((pending_mode_q.fb_height != mode_q.fb_height) ||
			                                 (pending_mode_q.is_120hz != mode_q.is_120hz) ||
			                                 (pending_mode_q.is_interlaced != mode_q.is_interlaced));
	end
	logic [1:0] renderer_reset_sync = 2'b11;
	// Startup uses the same frozen-frame settling window as live geometry changes.
	// Keep the source adapter empty until the committed tuple has crossed clocks.
	always_ff @(posedge clk_125)
		renderer_reset_sync <= {renderer_reset_sync[0],
		                        reset ||
		                        reset_source ||
		                        !mode_ready ||
		                        mode_restart_q ||
		                        mode_state == MODE_START_HOLD};
	wire renderer_reset = renderer_reset_sync[1];

	assign       video_mode_toggle = video_mode_toggle_q;
	assign       video_freeze      = video_freeze_q;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic  [1:0] orientation_meta = 0, orientation_sync = 0;
	logic  [1:0] orientation_sync_q = 0, orientation_stable = 0;
	always_ff @(posedge clk_sys) begin
		orientation_meta   <= key_active_q.orient;
		orientation_sync   <= orientation_meta;
		orientation_sync_q <= orientation_sync;
		if (orientation_sync == orientation_sync_q) orientation_stable <= orientation_sync;
	end
	assign active_orientation = orientation_stable;

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || !mode_ready) begin
			raw_path_vblank_q       <= 1'b1;
			processed_path_vblank_q <= 1'b1;
			output_vblank_q         <= 1'b1;
			output_vblank_entry_q   <= 1'b0;
		end else begin
			raw_path_vblank_q       <= raw_path_vblank;
			processed_path_vblank_q <= processed_path_vblank;
			output_vblank_entry_q   <= ce_pixel && vblank && !output_vblank_q;
			if (ce_pixel) output_vblank_q <= vblank;
		end
	end

	always_ff @(posedge clk_125) begin
		if (upload_reset_125) begin
			key_active_q         <= '{height:12'd480, default:'0};
			key_pending_q        <= '{height:12'd480, default:'0};
			mode_q               <= decode_video_mode(12'd480, 1'b0, 1'b0, 3'd0, 3'd0);
			pending_mode_q       <= decode_video_mode(12'd480, 1'b0, 1'b0, 3'd0, 3'd0);
			active_bypass_q      <= 1'b0;
			pending_bypass_q     <= 1'b0;
			transition_timing_q  <= 1'b0;
			transition_restart_q <= 1'b0;
			mode_restart_q       <= 1'b0;
			mode_state           <= MODE_WAIT_START;
			mode_ready           <= 1'b0;
			video_mode_toggle_q  <= 1'b0;
			video_freeze_q       <= 1'b1;
		end else begin
			case (mode_state)
				MODE_WAIT_START: begin
					mode_ready     <= 1'b0;
					video_freeze_q <= 1'b1;
					mode_restart_q <= 1'b0;
					if (request_valid) begin
						key_active_q     <= request_key;
						key_pending_q    <= request_key;
						mode_q           <= requested_mode;
						pending_mode_q   <= requested_mode;
						active_bypass_q  <= request_bypass;
						pending_bypass_q <= request_bypass;
						mode_state       <= MODE_START_TIMING;
					end
				end

				MODE_START_TIMING: begin
					mode_ready     <= 1'b1;
					video_freeze_q <= 1'b1;
					mode_state     <= MODE_START_HOLD;
				end

				MODE_START_HOLD: begin
					if (frame_wrap) begin
						video_freeze_q <= 1'b0;
						mode_state     <= MODE_RUN;
					end
				end

				MODE_RUN: begin
					video_freeze_q       <= 1'b0;
					mode_restart_q       <= 1'b0;
					transition_restart_q <= 1'b0;
					if (request_valid && request_changed) begin
						key_pending_q    <= request_key;
						pending_mode_q   <= requested_mode;
						pending_bypass_q <= request_bypass;
						mode_state       <= MODE_WAIT_ACTIVE_VBLANK;
					end
				end

				MODE_WAIT_ACTIVE_VBLANK: begin
					if (request_valid && !request_changed) begin
						mode_state <= MODE_RUN;
					end else if (request_valid) begin
						key_pending_q    <= request_key;
						pending_mode_q   <= requested_mode;
						pending_bypass_q <= request_bypass;
						if (active_path_vblank_entry) begin
							transition_timing_q  <= request_timing_changed;
							transition_restart_q <= height_class(request_key.height) !=
							    height_class(key_active_q.height) ||
							    request_key.orient != key_active_q.orient ||
							    request_key.framed != key_active_q.framed ||
							    request_key.labels_only != key_active_q.labels_only ||
							    request_key.viewport != key_active_q.viewport;
							video_freeze_q       <= 1'b1;
							mode_state           <= request_mode_changed ? MODE_WAIT_TIMING_WRAP :
							                                               MODE_WAIT_TARGET_VBLANK;
						end
					end
				end

				MODE_WAIT_TIMING_WRAP: begin
					video_freeze_q <= 1'b1;
					if (frame_wrap) begin
						key_active_q <= key_pending_q;
						mode_q       <= pending_mode_q;
						if (transition_timing_q) video_mode_toggle_q <= !video_mode_toggle_q;
						mode_restart_q <= transition_restart_q;
						mode_state     <= MODE_WAIT_TARGET_VBLANK;
					end
				end

				MODE_WAIT_TARGET_VBLANK: begin
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						mode_restart_q  <= 1'b0;
						active_bypass_q <= pending_bypass_q;
						if (!transition_timing_q && pending_bypass_q != active_bypass_q)
							video_mode_toggle_q <= !video_mode_toggle_q;
						mode_state <= MODE_HOLD_TARGET_FRAME;
					end else if (!transition_restart_q && target_path_vblank_entry) begin
						active_bypass_q <= pending_bypass_q;
						if (!transition_timing_q && pending_bypass_q != active_bypass_q)
							video_mode_toggle_q <= !video_mode_toggle_q;
						mode_state <= MODE_HOLD_TARGET_FRAME;
					end
				end

				MODE_HOLD_TARGET_FRAME: begin
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						transition_restart_q <= 1'b0;
						video_freeze_q       <= 1'b0;
						mode_state           <= MODE_RUN;
					end else if (!transition_restart_q && target_path_vblank_entry) begin
						video_freeze_q <= 1'b0;
						mode_state     <= MODE_RUN;
					end
				end

				default: mode_state <= MODE_WAIT_START;
			endcase
		end
	end

	wire [11:0] fb_width  = mode_q.fb_width;
	wire [11:0] fb_height = mode_q.fb_height;
	wire        is_240p   = mode_q.is_240p;
	wire        is_120hz  = mode_q.is_120hz;

	assign profile_resolution = vfb_control_pkg::profile_resolution(fb_height);

	logic        half_rate_phase      =  1'b0;
	logic [17:0] fractional_phase     = 18'd0;
	logic [10:0] h_counter            = 11'd0;
	logic [10:0] v_counter            = 11'd0;
	logic        progressive_ce_pixel =  1'b0;
	logic        v_end_q              =  1'b0;
	logic        raw_hsync;
	logic        raw_vsync;
	logic        raw_hblank;
	logic        raw_vblank;

	wire   h_end      = h_counter >= mode_q.h_total[10:0];
	wire   v_end      = v_end_q;
	assign frame_wrap = progressive_ce_pixel && h_end && v_end;

	always_ff @(posedge clk_125) begin
		if (timing_reset || mode_commit_q)
			v_end_q <= 1'b0;
		else
			v_end_q <= v_counter >= mode_q.v_total[10:0];
	end

	always_ff @(posedge clk_125) begin
		if (timing_reset) begin
			half_rate_phase      <=  1'b0;
			fractional_phase     <= 18'd0;
			h_counter            <= mode_q.h_total[10:0];
			v_counter            <= mode_q.fb_height[10:0] + 11'd2;
			progressive_ce_pixel <= 1'b0;
		end else if (mode_commit_q) begin
			half_rate_phase      <=  1'b0;
			fractional_phase     <= 18'd0;
			h_counter            <= 11'd0;
			v_counter            <= 11'd0;
			progressive_ce_pixel <=  1'b0;
		end else begin
			half_rate_phase <= !half_rate_phase;
			case (mode_q.pixel_mode)
				PIXEL_FULL: progressive_ce_pixel <= 1'b1;
				PIXEL_HALF: progressive_ce_pixel <= !half_rate_phase;
				default:    begin
					if (fractional_phase >= mode_q.pixel_wrap) begin
						fractional_phase     <= fractional_phase - mode_q.pixel_wrap;
						progressive_ce_pixel <= 1'b1;
					end else begin
						fractional_phase     <= fractional_phase + mode_q.pixel_step;
						progressive_ce_pixel <= 1'b0;
					end
				end
			endcase

			if (progressive_ce_pixel) begin
				if (h_end) begin
					h_counter <= 11'd0;
					v_counter <= v_end ? 11'd0 : v_counter + 1'd1;
				end else begin
					h_counter <= h_counter + 1'd1;
				end
			end
		end
	end

	always_comb begin
		raw_hsync  = !((h_counter >= mode_q.hs_start[10:0]) && (h_counter < mode_q.hs_end[10:0]));
		raw_vsync  = !((v_counter >= mode_q.vs_start[10:0]) && (v_counter < mode_q.vs_end[10:0]));
		raw_hblank = h_counter >= mode_q.fb_width[10:0];
		raw_vblank = v_counter >= mode_q.fb_height[10:0];
	end

	always_comb begin
		case (aspect_ratio)
			2'd0:    begin
				// SD output samples fill a physical 4:3 frame. A ratio here would
				// apply square-pixel pillarboxing before the display's pixel aspect.
				if (key_active_q.sd_pixel_aspect) begin
					video_arx = 13'h1000 | 13'd720;
					video_ary = 13'h1000 | {1'b0,fb_height};
				end else begin
					// Rotation is already fitted inside the full physical 4:3 canvas.
					video_arx = 13'd4;
					video_ary = 13'd3;
				end
			end
			2'd1:    begin video_arx = 13'd0;         video_ary = 13'd0;         end
			default: begin
				video_arx = 13'h1000 | {1'b0, fb_width};
				video_ary = 13'h1000 | {1'b0, fb_height};
			end
		endcase
	end

	assign mode_supports_120hz = mode_ready && height_supports_120hz;
	assign mode_is_15khz       = mode_ready && (is_240p || mode_q.is_interlaced);
	assign mode_is_crt         = mode_ready && (is_240p || mode_q.is_480p);

	// ------------------------------------------------------------------
	// The endpoint queue owns accepted source events independently of DDR stalls.
	logic [1:0] adapter_reset_sync = 2'b11;
	always_ff @(posedge clk_sys)
		adapter_reset_sync <= {adapter_reset_sync[0], renderer_reset};
	wire        adapter_reset = reset_source || adapter_reset_sync[1];
	wire [10:0] fb_x, fb_y;
	wire [5:0]  fb_c;
	wire [7:0]  fb_z;
	wire        fb_beam, fb_dot, fb_frame_done, fb_ready;
	wire [15:0] fb_frame_ticks;
	aztarac_vector_adapter adapter (
		.clk(clk_sys), .reset(adapter_reset),
		.vector_x0(vector_x0), .vector_y0(vector_y0),
		.vector_x1(vector_x1), .vector_y1(vector_y1),
		.vector_color(vector_color), .vector_intensity(vector_intensity),
		.vector_valid(vector_valid), .frame_done(frame_done),
		.vector_ready(vector_ready), .overflow(vector_overflow),
		.render_width(fb_width), .render_height(fb_height), .pixel_ready(fb_ready),
		.orientation(key_active_q.orient), .viewport(key_active_q.viewport),
		.pixel_x(fb_x), .pixel_y(fb_y), .pixel_color(fb_c), .pixel_intensity(fb_z),
		.pixel_valid(fb_beam), .pixel_is_dot(fb_dot),
		.frame_done_out(fb_frame_done), .frame_tick_clks_out(fb_frame_ticks)
	);
	logic [2:0] source_div;
	logic       source_new_list;
	always_ff @(posedge clk_sys) begin
		if (adapter_reset) begin
			source_div      <= 0;
			source_new_list <= 1;
		end else begin
			source_div <= source_div + 1'b1;
			if (fb_frame_done) source_new_list <= 1;
			else if (fb_beam) source_new_list <= 0;
		end
	end

	wire [7:0] progressive_video_r;
	wire [7:0] progressive_video_g;
	wire [7:0] progressive_video_b;
	wire       progressive_hsync;
	wire       progressive_vsync;
	wire       progressive_hblank;
	wire       progressive_vblank;

	vfb_top renderer (
		.clk_sys             (clk_125),
		.clk_source          (clk_sys),
		.source_tick         (&source_div),
		.reset               (renderer_reset),
		.video_timing_reset  (timing_reset || mode_commit_q),
		.clk_io(clk_sys), .upload_reset(upload_reset),
		.artwork_enable(key_active_q.framed), .artwork_blend(artwork_blend),
		.artwork_labels_only(key_active_q.labels_only),
		.artwork_brightness(artwork_brightness), .artwork_orientation(key_active_q.orient),
		.layout_width(requested_mode.fb_width), .layout_height(requested_mode.fb_height),
		.layout_orientation(request_orientation), .layout_valid(layout_valid),
		.layout_viewport(layout_viewport),
		.artwork_available(artwork_available),
		.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data), .ioctl_wait(ioctl_wait),

		.X_VECTOR            (fb_x),
		.Y_VECTOR            (fb_y),
		.COLOR               (fb_c),
		.INTENSITY           (fb_z),
		.SOURCE_READY        (fb_ready),
		.IS_DOT              (fb_dot),
		.BEAM_ON             (fb_beam),

		.DDRAM_CLK           (ddram_clk),
		.DDRAM_BUSY          (ddram_busy),
		.DDRAM_BURSTCNT      (ddram_burst_count),
		.DDRAM_ADDR          (ddram_address),
		.DDRAM_DOUT          (ddram_data_out),
		.DDRAM_DOUT_READY    (ddram_data_ready),
		.DDRAM_RD            (ddram_read),
		.DDRAM_DIN           (ddram_data_in),
		.DDRAM_BE            (ddram_byte_enable),
		.DDRAM_WE            (ddram_write),

		.SDRAM_DQ_IN         (sdram_data_in),
		.SDRAM_DQ_OUT        (sdram_data_out),
		.SDRAM_DQ_OE         (sdram_data_oe),
		.SDRAM_CKE           (sdram_cke),
		.SDRAM_nCS           (sdram_ncs),
		.SDRAM_nRAS          (sdram_nras),
		.SDRAM_nCAS          (sdram_ncas),
		.SDRAM_nWE           (sdram_nwe),
		.SDRAM_DQM           (sdram_dqm),
		.SDRAM_A             (sdram_address),
		.SDRAM_BA            (sdram_bank),

		.RENDER_WIDTH        (fb_width),
		.RENDER_HEIGHT       (fb_height),

		.VGA_R               (progressive_video_r),
		.VGA_G               (progressive_video_g),
		.VGA_B               (progressive_video_b),
		.VGA_HS              (progressive_hsync),
		.VGA_VS              (progressive_vsync),
		.VGA_HBLANK          (progressive_hblank),
		.VGA_VBLANK          (progressive_vblank),

		.h_cnt               (h_counter),
		.v_cnt               (v_counter),
		.ce_pix              (progressive_ce_pixel),
		.hsync               (raw_hsync),
		.vsync               (raw_vsync),
		.hblank              (raw_hblank),
		.vblank              (raw_vblank),

		.OSD_120HZ           (is_120hz),
		.FRAME_DONE          (fb_frame_done),
		.FRAME_START         (fb_beam && source_new_list),
		.FRAME_TICK_CLKS     (fb_frame_ticks),
		.BUFFER_MODE         (osd_buffer_mode),
		.DOT_MODE            (resolved_settings.dot_mode),
		.FIFO_FULL_LED       (fifo_full),

		.osd_bloom_width     (resolved_settings.bloom_width),
		.osd_bloom_curve     (resolved_settings.bloom_curve),
		.osd_halo_filter     (resolved_settings.halo_filter),
		.osd_phosphor_mode   (resolved_settings.intra_frame_decay),
		.osd_inter_frame_phosphor_mode (resolved_settings.inter_frame_decay),
		.osd_halo_spread     (resolved_settings.halo_spread),
		.osd_halo_curve      (resolved_settings.halo_curve),
		.osd_halo_knee       (resolved_settings.halo_knee),
		.osd_halo_shape      (osd_halo_shape),
		.halo_grid_8         (key_active_q.halo_grid),
		.osd_tone_mapping    (resolved_settings.tonemapping),
		.osd_color_space     (resolved_settings.color_space),
		.osd_presentation_color(resolved_settings.presentation_color),
		.osd_slot_mask       (resolved_settings.slot_mask),
		.osd_slot_mask_rows  (key_active_q.orient != 0),
		.full_bypass_active  (active_bypass_q),
		.raw_path_vblank     (raw_path_vblank),
		.processed_path_vblank(processed_path_vblank)
	);

	localparam logic [1:0] INTERLACER_PATH_RESTART_CYCLES = 2'd3;
	logic [1:0]            interlacer_restart_count       = 2'd0;

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || timing_reset || !mode_q.is_interlaced)
			interlacer_restart_count <= 2'd0;
		else if (profile_path_commit)
			interlacer_restart_count <= INTERLACER_PATH_RESTART_CYCLES;
		else if (interlacer_restart_count != 2'd0)
			interlacer_restart_count <= interlacer_restart_count - 1'd1;
	end

	vfb_interlacer interlacer (
		.clk_sys(clk_125),
		.vertical_offset(mode_q.crt_vertical_offset),
		.hs_start(mode_q.hs_start[9:0]), .hs_end(mode_q.hs_end[9:0]),
		.reset(timing_reset || mode_commit_q || !mode_q.is_interlaced ||
		       (interlacer_restart_count != 2'd0)),
		.enable(mode_q.is_interlaced),
		.ce_pix_in(progressive_ce_pixel),
		.r_in(progressive_video_r),
		.g_in(progressive_video_g),
		.b_in(progressive_video_b),
		.hsync_in(progressive_hsync),
		.vsync_in(progressive_vsync),
		.hblank_in(progressive_hblank),
		.vblank_in(progressive_vblank),
		.ce_pix_out(ce_pixel),
		.r_out(video_r),
		.g_out(video_g),
		.b_out(video_b),
		.hsync_out(hsync),
		.vsync_out(vsync),
		.hblank_out(hblank),
		.vblank_out(vblank),
		.field_out(field)
	);

endmodule

`default_nettype wire

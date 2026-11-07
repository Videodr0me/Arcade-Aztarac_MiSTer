// ============================================================================
// Palette artwork loader, decoder, and video compositor.
// Written 2026 by Videodr0me
//
// Loads VART artwork from MiSTer ROM index 2 into DDRAM, selects the plane
// matching the active resolution, decodes it one row ahead, and blends it
// after final CRT presentation.
// ============================================================================

`default_nettype none

module vfb_overlay #(
	parameter logic [28:0] ARTWORK_BASE = vfb_layout_pkg::VFB_ARTWORK_BASE,
	parameter logic [28:0] ARTWORK_LAST = vfb_layout_pkg::VFB_ARTWORK_LAST,
	parameter integer      MAX_PLANES   = vfb_layout_pkg::VFB_ARTWORK_PLANES,
	parameter integer      MAX_WIDTH    = 2048
) (
	input  wire         clk_sys,
	input  wire         clk_io,
	input  wire         reset,
	input  wire         upload_reset,
	input  wire         arbiter_ready,
	input  wire         video_timing_reset,

	input  wire                           processed_path_active,
	input  wire                           artwork_enable,
	input  wire                           artwork_labels_only,
	input  wire  [2:0]                    artwork_blend,
	input  wire  [2:0]                    artwork_brightness,
	input  wire  [1:0]                    artwork_orientation,
	input  wire  [11:0]                   layout_width, layout_height,
	input  wire  [1:0]                    layout_orientation,
	output wire                           layout_valid,
	output vfb_layout_pkg::vfb_viewport_t layout_viewport,
	input  wire  [11:0]                   render_width,
	input  wire  [11:0]                   render_height,
	output logic                          artwork_available,

	input  wire         ioctl_download,
	input  wire         ioctl_wr,
	input  wire  [15:0] ioctl_index,
	input  wire  [26:0] ioctl_addr,
	input  wire   [7:0] ioctl_data,
	output logic        ioctl_wait,

	input  wire         ce_pix,
	input  wire   [7:0] video_r_in,
	input  wire   [7:0] video_g_in,
	input  wire   [7:0] video_b_in,
	input  wire         video_hs_in,
	input  wire         video_vs_in,
	input  wire         video_hblank_in,
	input  wire         video_vblank_in,
	output logic  [7:0] video_r_out,
	output logic  [7:0] video_g_out,
	output logic  [7:0] video_b_out,
	output logic        video_hs_out,
	output logic        video_vs_out,
	output logic        video_hblank_out,
	output logic        video_vblank_out,

	output logic        upload_write_ready,
	input  wire         upload_write_done,
	output logic [28:0] upload_write_addr,
	output logic  [7:0] upload_write_burstcnt,
	output logic [63:0] upload_write_data,
	output logic  [7:0] upload_write_be,
	input  wire         upload_write_advance,

	output logic        artwork_read_ready,
	input  wire         artwork_read_grant,
	output logic [28:0] artwork_read_addr,
	output logic  [7:0] artwork_read_burstcnt,
	input  wire  [63:0] artwork_read_data,
	input  wire         artwork_read_data_valid
);

	function automatic [6:0] blend_weight(input logic [2:0] selection);
		begin
			case (selection)
				3'b000:  blend_weight = 7'd26;  //  0: 40.6%
				3'b001:  blend_weight = 7'd27;  // +1: 42.2%
				3'b010:  blend_weight = 7'd32;  // +2: 50.0%
				3'b011:  blend_weight = 7'd37;  // +3: 57.8%
				3'b100:  blend_weight = 7'd20;  // -4: 31.3%
				3'b101:  blend_weight = 7'd22;  // -3: 34.4%
				3'b110:  blend_weight = 7'd24;  // -2: 37.5%
				default: blend_weight = 7'd25;  // -1: 39.1%
			endcase
		end
	endfunction

	// RGB gain / 255; alpha is unchanged. The OSD maps its default to ID 2 (100%).
	function automatic [7:0] brightness_gain(input logic [2:0] selection);
		case (selection)
			0:       brightness_gain = 8'd153;  // 60%
			1:       brightness_gain = 8'd204;  // 80%
			2:       brightness_gain = 8'd255;  // 100%
			3:       brightness_gain =  8'd26;  // 10%, nearest 8-bit gain
			4:       brightness_gain =  8'd51;  // 20%
			5:       brightness_gain =  8'd77;  // 30%, nearest 8-bit gain
			6:       brightness_gain = 8'd102;  // 40%
			default: brightness_gain = 8'd128;  // 50%, nearest 8-bit gain
		endcase
	endfunction

	function automatic [7:0] divide_255_rounded(input logic [15:0] value);
		logic [7:0] low_sum;
		logic [7:0] hi, plus_one, plus_two;
		logic       round_one, round_two;
		begin
			// Exact integer form of round(value / 255): value is 256*hi + lo,
			// so the residual hi + lo adds one at 128 and another at 383.
			// Split off the top bits: 383 requires both set and low_sum >= 127.
			hi                 = value[15:8];
			plus_one           = hi ^ {&hi[6:0], &hi[5:0], &hi[4:0], &hi[3:0],
			                      &hi[2:0], &hi[1:0], hi[0], 1'b1};
			plus_two           = hi ^ {&hi[6:1], &hi[5:1], &hi[4:1], &hi[3:1],
			                      &hi[2:1], hi[1], 1'b1, 1'b0};
			low_sum            = {1'b0, value[14:8]} + {1'b0, value[6:0]};
			round_one          = value[15] | value[7] | low_sum[7];
			round_two          = value[15] & value[7] & (low_sum[7] | (&low_sum[6:0]));
			divide_255_rounded = round_two ? plus_two : round_one ? plus_one : hi;
		end
	endfunction

	// Only the eight result bits and the half-step bit of the registered product are needed.
	function automatic [7:0] divide_64_rounded(input logic [14:0] product);
		divide_64_rounded = product[13:6] + {7'd0, product[5]};
	endfunction

	logic       processed_path_active_q =   1'b0;
	logic       artwork_enable_q        =   1'b0;
	logic [2:0] artwork_blend_q         =   3'd0;
	logic [7:0] artwork_gain_q          = 8'd153;

	always_ff @(posedge clk_sys) begin
		processed_path_active_q <= processed_path_active;
		artwork_enable_q        <= artwork_enable;
		artwork_blend_q         <= artwork_blend;
		artwork_gain_q          <= brightness_gain(artwork_brightness);
	end

	vfb_layout_pkg::vfb_artwork_plane_t active_plane;
	wire [11:0]                         palette_read_addr;
	wire [31:0]                         palette_read_data;
	wire                                input_art_valid;
	wire                                run_requested = active_plane.ready && artwork_enable_q &&
	                                                    processed_path_active_q;

	assign artwork_available = active_plane.ready;

	vfb_artwork_loader #(
		.ARTWORK_BASE(ARTWORK_BASE),
		.ARTWORK_LAST(ARTWORK_LAST),
		.MAX_PLANES(MAX_PLANES)
	) loader (
		.clk_sys(clk_sys),
		.clk_io(clk_io),
		.reset(reset),
		.upload_reset(upload_reset),
		.arbiter_ready(arbiter_ready),
		.video_timing_reset(video_timing_reset),
		.render_width(render_width),
		.render_height(render_height),
		.artwork_orientation(artwork_orientation),
		.artwork_labels_only(artwork_labels_only),
		.layout_width(layout_width), .layout_height(layout_height),
		.layout_orientation(layout_orientation), .layout_valid(layout_valid),
		.layout_viewport(layout_viewport),
		.active_plane(active_plane),
		.ioctl_download(ioctl_download),
		.ioctl_wr(ioctl_wr),
		.ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr),
		.ioctl_data(ioctl_data),
		.ioctl_wait(ioctl_wait),
		.ce_pix(ce_pix),
		.palette_read_addr(palette_read_addr),
		.palette_data(palette_read_data),
		.upload_write_ready(upload_write_ready),
		.upload_write_done(upload_write_done),
		.upload_write_addr(upload_write_addr),
		.upload_write_burstcnt(upload_write_burstcnt),
		.upload_write_data(upload_write_data),
		.upload_write_be(upload_write_be),
		.upload_write_advance(upload_write_advance)
	);

	vfb_artwork_readout #(
		.ARTWORK_BASE(ARTWORK_BASE),
		.MAX_WIDTH(MAX_WIDTH)
	) readout (
		.clk_sys(clk_sys),
		.reset(reset),
		.video_timing_reset(video_timing_reset),
		.run_requested(run_requested),
		.active_plane(active_plane),
		.render_width(render_width),
		.render_height(render_height),
		.ce_pix(ce_pix),
		.video_hblank_in(video_hblank_in),
		.video_vblank_in(video_vblank_in),
		.input_art_valid(input_art_valid),
		.palette_addr(palette_read_addr),
		.artwork_read_ready(artwork_read_ready),
		.artwork_read_grant(artwork_read_grant),
		.artwork_read_addr(artwork_read_addr),
		.artwork_read_burstcnt(artwork_read_burstcnt),
		.artwork_read_data(artwork_read_data),
		.artwork_read_data_valid(artwork_read_data_valid)
	);

	// ------------------------------------------------------------------------
	// Foreground uses alpha OVER; reflected backgrounds retain screen blending.
	// ------------------------------------------------------------------------

	typedef struct packed {
		logic [7:0] r;
		logic [7:0] g;
		logic [7:0] b;
		logic       hs;
		logic       vs;
		logic       hblank;
		logic       vblank;
		logic       art_valid;
		logic       foreground;
	} video_packet_t;

	video_packet_t pixel_s0;
	video_packet_t pixel_s1;
	video_packet_t pixel_s2;
	video_packet_t pixel_s3;
	video_packet_t pixel_s4;
	video_packet_t pixel_s5;
	video_packet_t pixel_s6;
	video_packet_t pixel_s7;
	video_packet_t pixel_s8;
	logic [7:0]    background_r_s3     =  8'd0;
	logic [7:0]    background_g_s3     =  8'd0;
	logic [7:0]    background_b_s3     =  8'd0;
	logic [7:0]    background_a_s3     =  8'd0;
	(* dont_retime *)
	logic [15:0]   background_r_s4     = 16'd0;
	(* dont_retime *)
	logic [15:0]   background_g_s4     = 16'd0;
	(* dont_retime *)
	logic [15:0]   background_b_s4     = 16'd0;
	logic [14:0]   alpha_weight_s4     = 15'd0;
	logic [6:0]    effective_weight_s5 =  7'd0;
	(* dont_retime *)
	logic [7:0]    background_r_s5     =  8'd0;
	(* dont_retime *)
	logic [7:0]    background_g_s5     =  8'd0;
	(* dont_retime *)
	logic [7:0]    background_b_s5     =  8'd0;
	logic [7:0]    foreground_alpha_s4 = 8'd0, foreground_alpha_s5 = 8'd0;
	logic [15:0]   over_r_sum_s6, over_g_sum_s6, over_b_sum_s6;
	logic [15:0]   over_r_sum_s7, over_g_sum_s7, over_b_sum_s7;
	(* dont_retime *)
	logic [14:0]   artwork_r_product_s6 = 15'd0;
	(* dont_retime *)
	logic [14:0]   artwork_g_product_s6 = 15'd0;
	(* dont_retime *)
	logic [14:0]   artwork_b_product_s6 = 15'd0;
	logic [15:0]   screen_r_product_s7 = 16'd0;
	logic [15:0]   screen_g_product_s7 = 16'd0;
	logic [15:0]   screen_b_product_s7 = 16'd0;
	// Keep rounding separate from the final blend/blanking selection.
	(* dont_retime *)
	logic [23:0]   over_rgb_s8                = 24'd0;
	(* dont_retime *)
	logic [23:0]   screen_rgb_s8              = 24'd0;
	logic          blank_s8                   =  1'b1;
	(* dont_retime *)
	logic          blank_out_q                =  1'b1;
	logic [23:0]   rgb_out_q;
	wire  [14:0]   alpha_weight_rounded       = alpha_weight_s4 + 15'd128;
	wire  [14:0]   alpha_weight_scaled        = alpha_weight_rounded + (alpha_weight_rounded >> 8);
	wire  [7:0]    screen_r_foreground_inv_s6 = pixel_s6.r ^ 8'hff;
	wire  [7:0]    screen_g_foreground_inv_s6 = pixel_s6.g ^ 8'hff;
	wire  [7:0]    screen_b_foreground_inv_s6 = pixel_s6.b ^ 8'hff;
	wire  [7:0]    screen_r_artwork_inv_s6    = ~divide_64_rounded(artwork_r_product_s6);
	wire  [7:0]    screen_g_artwork_inv_s6    = ~divide_64_rounded(artwork_g_product_s6);
	wire  [7:0]    screen_b_artwork_inv_s6    = ~divide_64_rounded(artwork_b_product_s6);

	always_ff @(posedge clk_sys) begin
		if (video_timing_reset) begin
			pixel_s0         <=   '0;
			pixel_s1         <=   '0;
			pixel_s2         <=   '0;
			pixel_s3         <=   '0;
			pixel_s4         <=   '0;
			pixel_s5         <=   '0;
			pixel_s6         <=   '0;
			pixel_s7         <=   '0;
			pixel_s8         <=   '1;
			blank_s8         <= 1'b1;
			blank_out_q      <= 1'b1;
			video_hs_out     <= 1'b1;
			video_vs_out     <= 1'b1;
			video_hblank_out <= 1'b1;
			video_vblank_out <= 1'b1;
		end else if (ce_pix) begin
			pixel_s0.r          <= reset ? 8'd0 : video_r_in;
			pixel_s0.g          <= reset ? 8'd0 : video_g_in;
			pixel_s0.b          <= reset ? 8'd0 : video_b_in;
			pixel_s0.hs         <= video_hs_in;
			pixel_s0.vs         <= video_vs_in;
			pixel_s0.hblank     <= video_hblank_in;
			pixel_s0.vblank     <= video_vblank_in;
			pixel_s0.art_valid  <= !reset && input_art_valid;
			pixel_s0.foreground <= active_plane.foreground;

			pixel_s1 <= pixel_s0;

			pixel_s2 <= pixel_s1;

			pixel_s3        <= pixel_s2;
			background_r_s3 <= palette_read_data[7:0];
			background_g_s3 <= palette_read_data[15:8];
			background_b_s3 <= palette_read_data[23:16];
			background_a_s3 <= palette_read_data[31:24];

			pixel_s4            <= pixel_s3;
			background_r_s4     <= background_r_s3 * artwork_gain_q;
			background_g_s4     <= background_g_s3 * artwork_gain_q;
			background_b_s4     <= background_b_s3 * artwork_gain_q;
			foreground_alpha_s4 <= pixel_s3.art_valid ? background_a_s3 : 8'd0;
			alpha_weight_s4     <= pixel_s3.art_valid ?
			                       (background_a_s3 * blend_weight(artwork_blend_q)) :
			                       15'd0;

			pixel_s5            <= pixel_s4;
			background_r_s5     <= divide_255_rounded(background_r_s4);
			background_g_s5     <= divide_255_rounded(background_g_s4);
			background_b_s5     <= divide_255_rounded(background_b_s4);
			foreground_alpha_s5 <= foreground_alpha_s4;
			effective_weight_s5 <= alpha_weight_scaled[14:8];

			pixel_s6            <= pixel_s5;
			over_r_sum_s6       <= 16'(background_r_s5) * 16'(foreground_alpha_s5) +
			                       16'(pixel_s5.r) * 16'(8'd255 - foreground_alpha_s5);
			over_g_sum_s6       <= 16'(background_g_s5) * 16'(foreground_alpha_s5) +
			                       16'(pixel_s5.g) * 16'(8'd255 - foreground_alpha_s5);
			over_b_sum_s6       <= 16'(background_b_s5) * 16'(foreground_alpha_s5) +
			                       16'(pixel_s5.b) * 16'(8'd255 - foreground_alpha_s5);
			artwork_r_product_s6 <= background_r_s5 * effective_weight_s5;
			artwork_g_product_s6 <= background_g_s5 * effective_weight_s5;
			artwork_b_product_s6 <= background_b_s5 * effective_weight_s5;

			pixel_s7            <= pixel_s6;
			over_r_sum_s7       <= over_r_sum_s6;
			over_g_sum_s7       <= over_g_sum_s6;
			over_b_sum_s7       <= over_b_sum_s6;
			screen_r_product_s7 <= 16'(screen_r_foreground_inv_s6) * 16'(screen_r_artwork_inv_s6);
			screen_g_product_s7 <= 16'(screen_g_foreground_inv_s6) * 16'(screen_g_artwork_inv_s6);
			screen_b_product_s7 <= 16'(screen_b_foreground_inv_s6) * 16'(screen_b_artwork_inv_s6);

			pixel_s8    <= pixel_s7;
			over_rgb_s8 <= {divide_255_rounded(over_r_sum_s7), divide_255_rounded(over_g_sum_s7),
			                divide_255_rounded(over_b_sum_s7)};
			screen_rgb_s8       <= ~{divide_255_rounded(screen_r_product_s7),
			                         divide_255_rounded(screen_g_product_s7),
			                         divide_255_rounded(screen_b_product_s7)};
			blank_s8         <= reset || pixel_s7.hblank || pixel_s7.vblank;
			blank_out_q      <= reset || blank_s8;
			video_hs_out     <= pixel_s8.hs;
			video_vs_out     <= pixel_s8.vs;
			video_hblank_out <= pixel_s8.hblank;
			video_vblank_out <= pixel_s8.vblank;
		end
	end

	// Capture the color and its blanking decision on the same pixel enable.
	always_ff @(posedge clk_sys) begin
		if (ce_pix) rgb_out_q <= pixel_s8.foreground ? over_rgb_s8 : screen_rgb_s8;
	end
	assign {video_r_out, video_g_out, video_b_out} = blank_out_q ? 24'd0 : rgb_out_q;

endmodule

`default_nettype wire

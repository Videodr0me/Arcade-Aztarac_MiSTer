// Native RGB222 and eight-bit intensity, with matched five-enable latency.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

module vfb_aztarac_color (
	input  wire         clk_sys, ce_pix,
	input  wire  [13:0] canonical_in,
	input  wire  [1:0]  tone_mapping,
	output logic [13:0] canonical_out,
	output logic [7:0]  red, green, blue
);
	logic [13:0] sample_s1, sample_s2, sample_s3, sample_s4;
	logic [1:0]  tone_s1;
	logic [7:0]  intensity_s1;
	logic [17:0] tone_product_s2;
	logic [8:0]  level_s3;
	logic [16:0] thirds_s3;
	logic [9:0]  red_level_s4, green_level_s4, blue_level_s4;
	wire         active    = canonical_in[13:8] != 0 && canonical_in[7:0] != 0;
	wire  [9:0]  tone_gain = tone_s1 == vfb_control_pkg::TONE_STANDARD ? 10'd288 :
	                         tone_s1 == vfb_control_pkg::TONE_BRIGHT   ? 10'd311 :
	                         tone_s1 == vfb_control_pkg::TONE_BOOST    ? 10'd389 : 10'd256;
	// L = floor(intensity * gain / 256) is at most 387. The table
	// supplies exact floor(L/3) and floor(2*L/3) without runtime division.
	(* romstyle = "M10K" *) logic [16:0] thirds_lut [0:511];
	integer level_idx;
	initial begin
		for (level_idx = 0; level_idx < 512; level_idx = level_idx + 1)
			thirds_lut[level_idx] = {9'((2 * level_idx) / 3), 8'(level_idx / 3)};
	end
	function automatic logic [9:0] channel_level(
		input logic [1:0] coefficient,
		input logic [8:0] level,
		input logic [16:0] thirds
	);
		case (coefficient)
			2'd0: channel_level = 10'd0;
			2'd1: channel_level = {2'd0, thirds[7:0]};
			2'd2: channel_level = {1'b0, thirds[16:8]};
			2'd3: channel_level = {1'b0, level};
		endcase
	endfunction
	function automatic logic [7:0] clamp(input logic [9:0] value);
		clamp = value > 255 ? 8'd255 : value[7:0];
	endfunction
	always_ff @(posedge clk_sys) if (ce_pix) begin
		sample_s1       <= active ? canonical_in : 14'd0;
		intensity_s1    <= canonical_in[13:8] != 0 ? canonical_in[7:0] : 8'd0;
		tone_s1         <= tone_mapping;
		sample_s2       <= sample_s1;
		tone_product_s2 <= intensity_s1 * tone_gain;
		sample_s3       <= sample_s2;
		level_s3        <= tone_product_s2[16:8];
		thirds_s3       <= thirds_lut[tone_product_s2[16:8]];
		sample_s4       <= sample_s3;
		red_level_s4    <= channel_level(sample_s3[13:12], level_s3, thirds_s3);
		green_level_s4  <= channel_level(sample_s3[11:10], level_s3, thirds_s3);
		blue_level_s4   <= channel_level(sample_s3[9:8], level_s3, thirds_s3);
		canonical_out   <= sample_s4;
		red             <= clamp(red_level_s4);
		green           <= clamp(green_level_s4);
		blue            <= clamp(blue_level_s4);
	end
endmodule

`default_nettype wire

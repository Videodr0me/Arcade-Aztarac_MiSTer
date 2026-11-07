// Shared framebuffer, artwork, memory-layout, and presentation helpers.
// Copyright (C) 2026 Videodr0me

`default_nettype none

package vfb_layout_pkg;
	typedef struct packed {
		logic [11:0] x, y, width, height;
	} vfb_viewport_t;
	localparam integer VFB_ARTWORK_PLANES = 24;

	// The loader presents the registered plane without adding a pipeline stage.
	typedef enum logic [1:0] {
		INDEX_MODE_4,
		INDEX_MODE_6,
		INDEX_MODE_8
	} vfb_artwork_index_mode_t;

	typedef struct packed {
		logic                    ready;
		logic                    foreground;
		vfb_artwork_index_mode_t index_mode;
		logic [6:0]              index_bits;
		logic [31:0]             palette_offset;
		logic [31:0]             payload_offset;
		logic [31:0]             payload_size;
	} vfb_artwork_plane_t;

	localparam integer      VFB_BUFFER_COUNT        =            5;
	localparam logic [28:0] VFB_FRAMEBUFFER_BASE    = 29'h06000000;
	localparam logic [28:0] VFB_FRAMEBUFFER_LAST    = 29'h0654ffff;
	localparam logic [28:0] VFB_ARTWORK_BASE        = 29'h06550000;
	localparam logic [28:0] VFB_ARTWORK_LAST        = 29'h065cffff;
	localparam integer      VFB_TILE_SIZE           =            8;
	localparam integer      VFB_TILEMAP_STRIDE      =          192;
	localparam logic [15:0] VFB_TILEMAP_ENTRIES_480 =    16'd11520;

	localparam integer VFB_PIXEL_COLOR_MSB       = 15;
	localparam integer VFB_PIXEL_COLOR_LSB       = 10;
	localparam integer VFB_RAW_DRAW_MSB          =  9;
	localparam integer VFB_RAW_DRAW_LSB          =  8;
	localparam integer VFB_COMPOSED_FRESH_BIT    =  9;
	localparam integer VFB_COMPOSED_RESERVED_MSB =  8;
	localparam integer VFB_COMPOSED_RESERVED_LSB =  8;
	localparam integer VFB_PIXEL_INTENSITY_MSB   =  7;
	localparam integer VFB_PIXEL_INTENSITY_LSB   =  0;

	localparam integer VFB_SAMPLE_COLOR_MSB     = 13;
	localparam integer VFB_SAMPLE_COLOR_LSB     =  8;
	localparam integer VFB_SAMPLE_INTENSITY_MSB =  7;
	localparam integer VFB_SAMPLE_INTENSITY_LSB =  0;

	localparam logic [7:0] VFB_BEAM_INTENSITY     =  8'd255;
	localparam logic [9:0] VFB_MAX_CHANNEL_ENERGY = 10'd765;

	function automatic [7:0] vfb_apply_curve_gain(
		input logic [7:0] curved,
		input logic [9:0] gain
	);
		logic [11:0] scaled;
		logic [8:0]  scaled9;
		begin
			scaled  = 12'd0;
			scaled9 = 9'd0;
			case (gain)
				10'd64:  begin
					vfb_apply_curve_gain = {2'b00, curved[7:2]};
				end
				10'd96:  begin
					scaled           = ({4'd0, curved} << 1) + {4'd0, curved} + 12'd4;
					vfb_apply_curve_gain = {1'b0, scaled[9:3]};
				end
				10'd128: begin
					vfb_apply_curve_gain = {1'b0, curved[7:1]};
				end
				10'd192: begin
					scaled           = ({4'd0, curved} << 1) + {4'd0, curved} + 12'd2;
					vfb_apply_curve_gain = scaled[9:2];
				end
				10'd256: begin
					vfb_apply_curve_gain = curved;
				end
				10'd320: begin
					scaled           = ({4'd0, curved} << 2) + {4'd0, curved} + 12'd2;
					scaled9          = scaled[10:2];
					vfb_apply_curve_gain = scaled9[8] ? 8'hff : scaled9[7:0];
				end
				10'd384: begin
					scaled           = ({4'd0, curved} << 1) + {4'd0, curved} + 12'd1;
					scaled9          = scaled[9:1];
					vfb_apply_curve_gain = scaled9[8] ? 8'hff : scaled9[7:0];
				end
				default: begin
					vfb_apply_curve_gain = curved[7] ? 8'hff : {curved[6:0], 1'b0};
				end
			endcase
		end
	endfunction

	function automatic [2:0] vfb_halo_row_bank(input logic [7:0] y);
		logic [4:0] folded;
		begin
			// 16 is congruent to 1 modulo five; the nibble sum is at most 30.
			folded = {1'b0, y[7:4]} + {1'b0, y[3:0]};
			case (folded)
				5'd0, 5'd5, 5'd10, 5'd15, 5'd20, 5'd25, 5'd30: vfb_halo_row_bank = 3'd0;
				5'd1, 5'd6, 5'd11, 5'd16, 5'd21, 5'd26:        vfb_halo_row_bank = 3'd1;
				5'd2, 5'd7, 5'd12, 5'd17, 5'd22, 5'd27:        vfb_halo_row_bank = 3'd2;
				5'd3, 5'd8, 5'd13, 5'd18, 5'd23, 5'd28:        vfb_halo_row_bank = 3'd3;
				default:                                       vfb_halo_row_bank = 3'd4;
			endcase
		end
	endfunction

	function automatic logic [28:0] vfb_buffer_base(
		input logic [2:0] index
	);
		begin
			case (index)
				3'd0:    vfb_buffer_base = 29'h06000000;
				3'd1:    vfb_buffer_base = 29'h06110000;
				3'd2:    vfb_buffer_base = 29'h06220000;
				3'd3:    vfb_buffer_base = 29'h06330000;
				3'd4:    vfb_buffer_base = 29'h06440000;
				default: vfb_buffer_base = 29'h06000000;
			endcase
		end
	endfunction

	function automatic logic [9:0] vfb_tile_columns(
		input logic [11:0] width
	);
		vfb_tile_columns = 9'((width + 12'd7) >> 3);
	endfunction

	function automatic logic [9:0] vfb_tile_rows(
		input logic [11:0] height
	);
		vfb_tile_rows = 9'((height + 12'd7) >> 3);
	endfunction

	function automatic logic [14:0] vfb_tile_row_addr(
		input logic [7:0] tile_y
	);
		logic [15:0] row_base;
		begin
			row_base          = ({8'd0, tile_y} << 7) + ({8'd0, tile_y} << 6);
			vfb_tile_row_addr = row_base[14:0];
		end
	endfunction

	function automatic logic [14:0] vfb_linear_tile_addr(
		input logic [15:0] tile_id
	);
		vfb_linear_tile_addr = 15'(vfb_tile_row_addr(tile_id[15:8]) + {8'd0, tile_id[7:0]});
	endfunction

	function automatic logic [15:0] vfb_tilemap_entries(
		input logic [9:0] rows
	);
		vfb_tilemap_entries = 16'(({8'd0, rows} << 7) + ({8'd0, rows} << 6));
	endfunction

	function automatic logic [5:0] vfb_pixel_color(
		input logic [15:0] pixel
	);
		vfb_pixel_color = pixel[VFB_PIXEL_COLOR_MSB:VFB_PIXEL_COLOR_LSB];
	endfunction

	function automatic logic [2:0] vfb_raw_draw_idx(
		input logic [15:0] pixel
	);
		vfb_raw_draw_idx = {1'b0, pixel[VFB_RAW_DRAW_MSB:VFB_RAW_DRAW_LSB]};
	endfunction

	function automatic logic [7:0] vfb_pixel_intensity(
		input logic [15:0] pixel
	);
		vfb_pixel_intensity = pixel[VFB_PIXEL_INTENSITY_MSB:VFB_PIXEL_INTENSITY_LSB];
	endfunction

	function automatic logic vfb_composed_fresh(
		input logic [15:0] pixel
	);
		vfb_composed_fresh = pixel[VFB_COMPOSED_FRESH_BIT];
	endfunction

	function automatic logic [5:0] vfb_sample_color(
		input logic [13:0] sample
	);
		vfb_sample_color = sample[VFB_SAMPLE_COLOR_MSB:VFB_SAMPLE_COLOR_LSB];
	endfunction

	function automatic logic [7:0] vfb_sample_intensity(
		input logic [13:0] sample
	);
		vfb_sample_intensity = sample[VFB_SAMPLE_INTENSITY_MSB:VFB_SAMPLE_INTENSITY_LSB];
	endfunction

	function automatic logic [15:0] vfb_pack_raw_pixel(
		input logic [5:0] color,
		input logic [2:0] draw_idx,
		input logic [7:0] intensity
	);
		logic [15:0] pixel;
		begin
			pixel = 16'd0;
			if ((color != 6'd0) && (intensity != 8'd0)) begin
				pixel[VFB_PIXEL_COLOR_MSB:VFB_PIXEL_COLOR_LSB]         = color;
				pixel[VFB_RAW_DRAW_MSB:VFB_RAW_DRAW_LSB]               = draw_idx[1:0];
				pixel[VFB_PIXEL_INTENSITY_MSB:VFB_PIXEL_INTENSITY_LSB] = intensity;
			end
			vfb_pack_raw_pixel = pixel;
		end
	endfunction

	function automatic logic [15:0] vfb_pack_composed_pixel(
		input logic [5:0] color,
		input logic       fresh,
		input logic [7:0] intensity
	);
		logic [15:0] pixel;
		begin
			pixel = 16'd0;
			if ((color != 6'd0) && (intensity != 8'd0)) begin
				pixel[VFB_PIXEL_COLOR_MSB:VFB_PIXEL_COLOR_LSB]              = color;
				pixel[VFB_COMPOSED_FRESH_BIT]                               = fresh;
				pixel[VFB_COMPOSED_RESERVED_MSB: VFB_COMPOSED_RESERVED_LSB] = 1'b0;
				pixel[VFB_PIXEL_INTENSITY_MSB:VFB_PIXEL_INTENSITY_LSB]      = intensity;
			end
			vfb_pack_composed_pixel = pixel;
		end
	endfunction

	function automatic logic [9:0] vfb_channel_energy(
		input logic [1:0] coefficient,
		input logic [7:0] intensity
	);
		logic [9:0] level;
		begin
			level = {2'd0, intensity};
			case (coefficient)
				2'd0:    vfb_channel_energy = 10'd0;
				2'd1:    vfb_channel_energy = level;
				2'd2:    vfb_channel_energy = level << 1;
				default: vfb_channel_energy = level + (level << 1);
			endcase
		end
	endfunction

	function automatic logic [9:0] vfb_soft_cross_energy(
		input logic [9:0] old_energy,
		input logic [9:0] new_energy
	);
		logic [9:0]  high_energy;
		logic [9:0]  low_energy;
		logic [10:0] sum;
		begin
			high_energy           = (old_energy >= new_energy) ? old_energy : new_energy;
			low_energy            = (old_energy >= new_energy) ? new_energy : old_energy;
			sum                   = {1'b0, high_energy} + {3'd0, low_energy[9:2]};
			vfb_soft_cross_energy = (sum > VFB_MAX_CHANNEL_ENERGY) ? VFB_MAX_CHANNEL_ENERGY
			                                                       : sum[9:0];
		end
	endfunction

	function automatic logic [1:0] vfb_quantize_coefficient(
		input logic [9:0] energy,
		input logic [7:0] intensity
	);
		logic [10:0] energy_x2;
		logic [10:0] intensity_x1;
		logic [10:0] intensity_x3;
		logic [10:0] intensity_x5;
		begin
			energy_x2    = {1'b0, energy} << 1;
			intensity_x1 = {3'd0, intensity};
			intensity_x3 = intensity_x1 + (intensity_x1 << 1);
			intensity_x5 = intensity_x1 + (intensity_x1 << 2);

			if ((intensity == 8'd0) || (energy_x2 <= intensity_x1))
				vfb_quantize_coefficient = 2'd0;
			else if (energy_x2 <= intensity_x3)
				vfb_quantize_coefficient = 2'd1;
			else if (energy_x2 <= intensity_x5)
				vfb_quantize_coefficient = 2'd2;
			else
				vfb_quantize_coefficient = 2'd3;
		end
	endfunction

	function automatic logic [9:0] vfb_peak_energy(
		input logic [9:0] red_energy,
		input logic [9:0] green_energy,
		input logic [9:0] blue_energy
	);
		logic [9:0] peak;
		begin
			peak            = (red_energy >= green_energy) ? red_energy : green_energy;
			vfb_peak_energy = (blue_energy > peak) ? blue_energy : peak;
		end
	endfunction

	function automatic logic [7:0] vfb_normalize_peak(input logic [9:0] peak);
		logic [18:0] scaled;
		begin
			scaled = (19'(peak) + 19'd2) * 19'd683;
			if (peak <= 10'd255) vfb_normalize_peak = peak[7:0];
			else if (peak <= 10'd510) vfb_normalize_peak = 8'((peak + 10'd1) >> 1);
			else vfb_normalize_peak = scaled[18:11];
		end
	endfunction

	function automatic logic [7:0] vfb_normalize_intensity(
		input logic [9:0] red_energy,
		input logic [9:0] green_energy,
		input logic [9:0] blue_energy
	);
		begin
			vfb_normalize_intensity = vfb_normalize_peak(vfb_peak_energy(red_energy, green_energy,
			                                                             blue_energy));
		end
	endfunction

	function automatic logic [5:0] vfb_normalize_color(
		input logic [9:0] red_energy,
		input logic [9:0] green_energy,
		input logic [9:0] blue_energy,
		input logic [7:0] intensity
	);
		begin
			vfb_normalize_color = (intensity == 8'd0) ?
			                      6'd0 :
			                      {vfb_quantize_coefficient(red_energy, intensity),
			                       vfb_quantize_coefficient(green_energy, intensity),
			                       vfb_quantize_coefficient(blue_energy, intensity)};
		end
	endfunction

	function automatic logic [13:0] vfb_normalize_energies(
		input logic [9:0] red_energy,
		input logic [9:0] green_energy,
		input logic [9:0] blue_energy
	);
		logic [7:0] intensity;
		logic [5:0] color;
		begin
			intensity              = vfb_normalize_intensity(red_energy, green_energy, blue_energy);
			color                  = vfb_normalize_color(red_energy, green_energy,
			                                             blue_energy, intensity);
			vfb_normalize_energies = (intensity == 8'd0) ? 14'd0 : {color, intensity};
		end
	endfunction

	// Aztarac intra-frame decay: retain the 0.94, 0.96, and 0.98 tables.
	function automatic logic [7:0] vfb_decay_factor(
		input logic [1:0] mode,
		input logic [3:0] age
	);
		case ({mode, age})
			// LUT A (mode 1, base 0.94)
			{2'd1, 4'd0}:  vfb_decay_factor = 8'd255;
			{2'd1, 4'd1}:  vfb_decay_factor = 8'd240;
			{2'd1, 4'd2}:  vfb_decay_factor = 8'd225;
			{2'd1, 4'd3}:  vfb_decay_factor = 8'd212;
			{2'd1, 4'd4}:  vfb_decay_factor = 8'd199;
			{2'd1, 4'd5}:  vfb_decay_factor = 8'd187;
			{2'd1, 4'd6}:  vfb_decay_factor = 8'd176;
			{2'd1, 4'd7}:  vfb_decay_factor = 8'd165;
			{2'd1, 4'd8}:  vfb_decay_factor = 8'd155;
			{2'd1, 4'd9}:  vfb_decay_factor = 8'd146;
			{2'd1, 4'd10}: vfb_decay_factor = 8'd137;
			{2'd1, 4'd11}: vfb_decay_factor = 8'd129;
			{2'd1, 4'd12}: vfb_decay_factor = 8'd121;
			{2'd1, 4'd13}: vfb_decay_factor = 8'd114;
			{2'd1, 4'd14}: vfb_decay_factor = 8'd107;
			{2'd1, 4'd15}: vfb_decay_factor = 8'd101;
			// LUT B (mode 2, base 0.96)
			{2'd2, 4'd0}:  vfb_decay_factor = 8'd255;
			{2'd2, 4'd1}:  vfb_decay_factor = 8'd245;
			{2'd2, 4'd2}:  vfb_decay_factor = 8'd235;
			{2'd2, 4'd3}:  vfb_decay_factor = 8'd226;
			{2'd2, 4'd4}:  vfb_decay_factor = 8'd217;
			{2'd2, 4'd5}:  vfb_decay_factor = 8'd208;
			{2'd2, 4'd6}:  vfb_decay_factor = 8'd200;
			{2'd2, 4'd7}:  vfb_decay_factor = 8'd192;
			{2'd2, 4'd8}:  vfb_decay_factor = 8'd184;
			{2'd2, 4'd9}:  vfb_decay_factor = 8'd177;
			{2'd2, 4'd10}: vfb_decay_factor = 8'd170;
			{2'd2, 4'd11}: vfb_decay_factor = 8'd163;
			{2'd2, 4'd12}: vfb_decay_factor = 8'd156;
			{2'd2, 4'd13}: vfb_decay_factor = 8'd150;
			{2'd2, 4'd14}: vfb_decay_factor = 8'd144;
			{2'd2, 4'd15}: vfb_decay_factor = 8'd138;
			// LUT C (mode 3, base 0.98)
			{2'd3, 4'd0}:  vfb_decay_factor = 8'd255;
			{2'd3, 4'd1}:  vfb_decay_factor = 8'd250;
			{2'd3, 4'd2}:  vfb_decay_factor = 8'd245;
			{2'd3, 4'd3}:  vfb_decay_factor = 8'd240;
			{2'd3, 4'd4}:  vfb_decay_factor = 8'd235;
			{2'd3, 4'd5}:  vfb_decay_factor = 8'd230;
			{2'd3, 4'd6}:  vfb_decay_factor = 8'd225;
			{2'd3, 4'd7}:  vfb_decay_factor = 8'd221;
			{2'd3, 4'd8}:  vfb_decay_factor = 8'd216;
			{2'd3, 4'd9}:  vfb_decay_factor = 8'd212;
			{2'd3, 4'd10}: vfb_decay_factor = 8'd208;
			{2'd3, 4'd11}: vfb_decay_factor = 8'd204;
			{2'd3, 4'd12}: vfb_decay_factor = 8'd200;
			{2'd3, 4'd13}: vfb_decay_factor = 8'd196;
			{2'd3, 4'd14}: vfb_decay_factor = 8'd192;
			{2'd3, 4'd15}: vfb_decay_factor = 8'd188;
			default:       vfb_decay_factor = 8'd255;
		endcase
	endfunction

endpackage

`default_nettype wire

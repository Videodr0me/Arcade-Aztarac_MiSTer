// Aztarac CRT controls and resolution-specific profiles.
// Written 2026 by Videodr0me

`default_nettype none

package vfb_control_pkg;

	typedef struct packed {
		logic       halo_grid;
		logic [2:0] halo_knee;
		logic [2:0] halo_curve;
		logic [2:0] dot_mode;
		logic [1:0] tonemapping;
		logic [2:0] bloom_width;
		logic [2:0] bloom_curve;
		logic [2:0] halo_filter;
		logic [1:0] halo_spread;
		logic [1:0] inter_frame_decay;
		logic [1:0] intra_frame_decay;
		logic       color_space;
		logic [2:0] presentation_color;
		logic       slot_mask;
	} vfb_profile_settings_t;

	localparam logic [2:0] PROFILE_TYPICAL    = 3'd0;
	localparam logic [2:0] PROFILE_OVERDRIVEN = 3'd1;
	localparam logic [2:0] PROFILE_PLASMA     = 3'd2;
	localparam logic [2:0] PROFILE_S_NEGATIVE = 3'd3;
	localparam logic [2:0] PROFILE_CUSTOM1    = 3'd4;
	localparam logic [2:0] PROFILE_CUSTOM2    = 3'd5;
	localparam logic [2:0] PROFILE_TOUCH      = 3'd6;

	localparam logic [2:0] DOT_2X  = 3'd0;
	localparam logic [2:0] DOT_25X = 3'd1;
	localparam logic [2:0] DOT_3X  = 3'd2;
	localparam logic [2:0] DOT_1X  = 3'd3;

	localparam logic [1:0] TONE_OFF      = 2'd0;
	localparam logic [1:0] TONE_STANDARD = 2'd1;
	localparam logic [1:0] TONE_BRIGHT   = 2'd2;
	localparam logic [1:0] TONE_BOOST    = 2'd3;

	localparam logic [2:0] BLOOM_OFF    = 3'd0;
	localparam logic [2:0] BLOOM_THIN   = 3'd1;
	localparam logic [2:0] BLOOM_TIGHT  = 3'd2;
	localparam logic [2:0] BLOOM_SOFT   = 3'd3;
	localparam logic [2:0] BLOOM_NORMAL = 3'd4;
	localparam logic [2:0] BLOOM_BROAD  = 3'd5;
	localparam logic [2:0] BLOOM_WIDE_M = 3'd6;
	localparam logic [2:0] BLOOM_WIDE   = 3'd7;

	localparam logic [2:0] CURVE_MINIMAL  = 3'd0;
	localparam logic [2:0] CURVE_MIN_PLUS = 3'd1;
	localparam logic [2:0] CURVE_MILD     = 3'd2;
	localparam logic [2:0] CURVE_MILD_P   = 3'd3;
	localparam logic [2:0] CURVE_MODERATE = 3'd4;
	localparam logic [2:0] CURVE_MOD_PLUS = 3'd5;
	localparam logic [2:0] CURVE_STRONG_M = 3'd6;
	localparam logic [2:0] CURVE_STRONG   = 3'd7;

	localparam logic [2:0] HALO_OFF  = 3'd0;
	localparam logic [2:0] HALO_025X = 3'd1;
	localparam logic [2:0] HALO_033X = 3'd2;
	localparam logic [2:0] HALO_050X = 3'd3;
	localparam logic [2:0] HALO_075X = 3'd4;
	localparam logic [2:0] HALO_100X = 3'd5;
	localparam logic [2:0] HALO_125X = 3'd6;
	localparam logic [2:0] HALO_150X = 3'd7;

	localparam logic [1:0] SPREAD_ORIGINAL = 2'd0;
	localparam logic [1:0] SPREAD_WIDE1    = 2'd1;
	localparam logic [1:0] SPREAD_WIDE2    = 2'd2;
	localparam logic [1:0] SPREAD_FOCUS    = 2'd3;

	localparam logic HALO_GRID_16 = 1'b0;
	localparam logic HALO_GRID_8  = 1'b1;

	localparam logic [2:0] KNEE_OFF = 3'd0;
	localparam logic [2:0] KNEE_2   = 3'd1;
	localparam logic [2:0] KNEE_4   = 3'd2;
	localparam logic [2:0] KNEE_6   = 3'd3;
	localparam logic [2:0] KNEE_8   = 3'd4;
	localparam logic [2:0] KNEE_16  = 3'd5;
	localparam logic [2:0] KNEE_24  = 3'd6;
	localparam logic [2:0] KNEE_32  = 3'd7;


	localparam logic [1:0] INTER_OFF    = 2'd0;
	localparam logic [1:0] INTER_SHORT  = 2'd1;
	localparam logic [1:0] INTER_MEDIUM = 2'd2;
	localparam logic [1:0] INTER_LONG   = 2'd3;

	localparam logic [1:0] INTRA_OFF   = 2'd0;
	localparam logic [1:0] INTRA_LUT_A = 2'd1;
	localparam logic [1:0] INTRA_LUT_B = 2'd2;
	localparam logic [1:0] INTRA_LUT_C = 2'd3;

	localparam logic COLORSPACE_OFF     = 1'b0;
	localparam logic COLORSPACE_G08_709 = 1'b1;

	localparam logic [2:0] CHANNEL_ORIGINAL = 3'd0;
	localparam logic [2:0] CHANNEL_RBG      = 3'd1;
	localparam logic [2:0] CHANNEL_GRB      = 3'd2;
	localparam logic [2:0] CHANNEL_GBR      = 3'd3;
	localparam logic [2:0] CHANNEL_BRG      = 3'd4;
	localparam logic [2:0] CHANNEL_BGR      = 3'd5;
	localparam logic [2:0] CHANNEL_BW       = 3'd6;
	localparam logic [2:0] CHANNEL_NEGATIVE = 3'd7;

	localparam logic SLOT_MASK_OFF = 1'b0;
	localparam logic SLOT_MASK_ON  = 1'b1;

	function automatic vfb_profile_settings_t pack_settings(
		input logic [2:0] dot_i,
		input logic [1:0] tone_i,
		input logic [2:0] bloom_width_i,
		input logic [2:0] bloom_curve_i,
		input logic [2:0] halo_i,
		input logic [2:0] halo_curve_i,
		input logic [1:0] halo_spread_i,
		input logic [2:0] halo_knee_i,
		input logic [1:0] inter_decay_i,
		input logic [1:0] intra_decay_i,
		input logic       color_space_i,
		input logic [2:0] color_i,
		input logic       slot_mask_i,
		input logic       halo_grid_i
	);
		begin
			pack_settings = '{
				halo_grid:          halo_grid_i,
				halo_knee:          halo_knee_i,
				halo_curve:         halo_curve_i,
				dot_mode:           dot_i,
				tonemapping:        tone_i,
				bloom_width:        bloom_width_i,
				bloom_curve:        bloom_curve_i,
				halo_filter:        halo_i,
				halo_spread:        halo_spread_i,
				inter_frame_decay:  inter_decay_i,
				intra_frame_decay:  intra_decay_i,
				color_space:        color_space_i,
				presentation_color: color_i,
				slot_mask:          slot_mask_i
			};
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_240p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:      fixed_240p = pack_settings(DOT_2X, TONE_OFF, BLOOM_THIN,
				                                               CURVE_MILD, HALO_025X,
				                                               CURVE_MILD, SPREAD_FOCUS,
				                                               KNEE_8, INTER_OFF,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_8);
				PROFILE_TYPICAL:    fixed_240p = pack_settings(DOT_2X, TONE_STANDARD, BLOOM_THIN,
				                                               CURVE_MILD, HALO_025X,
				                                               CURVE_MILD, SPREAD_FOCUS,
				                                               KNEE_32, INTER_OFF,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_8);
				PROFILE_OVERDRIVEN: fixed_240p = pack_settings(DOT_2X, TONE_STANDARD,
				                                               BLOOM_THIN, CURVE_MODERATE,
				                                               HALO_033X, CURVE_MILD,
				                                               SPREAD_FOCUS, KNEE_32, INTER_SHORT,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_8);
				PROFILE_PLASMA:     fixed_240p = pack_settings(DOT_3X, TONE_STANDARD, BLOOM_TIGHT,
				                                               CURVE_MODERATE, HALO_033X,
				                                               CURVE_MODERATE, SPREAD_FOCUS,
				                                               KNEE_8, INTER_MEDIUM,
				                                               INTRA_LUT_A, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
				PROFILE_S_NEGATIVE: fixed_240p = pack_settings(DOT_25X, TONE_BRIGHT, BLOOM_THIN,
				                                               CURVE_MODERATE, HALO_033X,
				                                               CURVE_MILD, SPREAD_FOCUS,
				                                               KNEE_8, INTER_MEDIUM,
				                                               INTRA_LUT_C, COLORSPACE_OFF,
				                                               CHANNEL_NEGATIVE, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
				default:            fixed_240p = pack_settings(DOT_1X, TONE_BRIGHT, BLOOM_OFF,
				                                               CURVE_MINIMAL, HALO_OFF,
				                                               CURVE_MINIMAL, SPREAD_ORIGINAL,
				                                               KNEE_16, INTER_OFF,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
			endcase
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_480p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:      fixed_480p = pack_settings(DOT_2X, TONE_OFF,
				                                               BLOOM_THIN, CURVE_MILD,
				                                               HALO_025X, CURVE_MILD,
				                                               SPREAD_FOCUS, KNEE_32, INTER_OFF,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_8);
				PROFILE_TYPICAL:    fixed_480p = pack_settings(DOT_2X, TONE_STANDARD, BLOOM_THIN,
				                                               CURVE_MILD, HALO_050X,
				                                               CURVE_MINIMAL, SPREAD_FOCUS,
				                                               KNEE_24, INTER_OFF,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_8);
				PROFILE_OVERDRIVEN: fixed_480p = pack_settings(DOT_25X, TONE_STANDARD, BLOOM_TIGHT,
				                                               CURVE_MILD, HALO_050X,
				                                               CURVE_MIN_PLUS, SPREAD_ORIGINAL,
				                                               KNEE_32, INTER_SHORT,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_8);
				PROFILE_PLASMA:     fixed_480p = pack_settings(DOT_3X, TONE_STANDARD, BLOOM_TIGHT,
				                                               CURVE_MODERATE, HALO_050X,
				                                               CURVE_MILD_P, SPREAD_WIDE1,
				                                               KNEE_24, INTER_MEDIUM,
				                                               INTRA_LUT_A, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
				PROFILE_S_NEGATIVE: fixed_480p = pack_settings(DOT_25X, TONE_BRIGHT, BLOOM_TIGHT,
				                                               CURVE_MILD_P, HALO_050X,
				                                               CURVE_MILD_P, SPREAD_ORIGINAL,
				                                               KNEE_24, INTER_MEDIUM,
				                                               INTRA_LUT_C, COLORSPACE_OFF,
				                                               CHANNEL_NEGATIVE, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
				default:            fixed_480p = pack_settings(DOT_1X, TONE_BRIGHT, BLOOM_OFF,
				                                               CURVE_MINIMAL, HALO_OFF,
				                                               CURVE_MINIMAL, SPREAD_ORIGINAL,
				                                               KNEE_16, INTER_OFF,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
			endcase
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_720p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:      fixed_720p = pack_settings(DOT_25X, TONE_OFF,
				                                               BLOOM_THIN, CURVE_MODERATE,
				                                               HALO_025X, CURVE_MOD_PLUS,
				                                               SPREAD_WIDE1, KNEE_2, INTER_SHORT,
				                                               INTRA_OFF, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_8);
				PROFILE_TYPICAL:    fixed_720p = pack_settings(DOT_3X, TONE_STANDARD, BLOOM_TIGHT,
				                                               CURVE_MILD_P, HALO_050X,
				                                               CURVE_MIN_PLUS, SPREAD_FOCUS,
				                                               KNEE_4, INTER_SHORT,
				                                               INTRA_OFF, COLORSPACE_G08_709,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_ON,
				                                               HALO_GRID_16);
				PROFILE_OVERDRIVEN: fixed_720p = pack_settings(DOT_3X, TONE_STANDARD, BLOOM_TIGHT,
				                                               CURVE_MOD_PLUS, HALO_050X,
				                                               CURVE_MIN_PLUS, SPREAD_ORIGINAL,
				                                               KNEE_24, INTER_MEDIUM,
				                                               INTRA_OFF, COLORSPACE_G08_709,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_ON,
				                                               HALO_GRID_16);
				PROFILE_PLASMA:     fixed_720p = pack_settings(DOT_3X, TONE_STANDARD, BLOOM_SOFT,
				                                               CURVE_MILD_P, HALO_075X,
				                                               CURVE_MOD_PLUS, SPREAD_WIDE2,
				                                               KNEE_16, INTER_MEDIUM,
				                                               INTRA_LUT_A, COLORSPACE_OFF,
				                                               CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
				PROFILE_S_NEGATIVE: fixed_720p = pack_settings(DOT_3X, TONE_OFF, BLOOM_SOFT,
				                                               CURVE_MILD_P, HALO_050X,
				                                               CURVE_MILD_P, SPREAD_ORIGINAL,
				                                               KNEE_16, INTER_LONG,
				                                               INTRA_LUT_C, COLORSPACE_OFF,
				                                               CHANNEL_NEGATIVE, SLOT_MASK_OFF,
				                                               HALO_GRID_16);
				default:            fixed_720p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_1080p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:      fixed_1080p = pack_settings(DOT_3X, TONE_OFF,
				                                                BLOOM_TIGHT, CURVE_MODERATE,
				                                                HALO_100X, CURVE_MINIMAL,
				                                                SPREAD_FOCUS, KNEE_8, INTER_SHORT,
				                                                INTRA_OFF, COLORSPACE_OFF,
				                                                CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                                HALO_GRID_16);
				PROFILE_TYPICAL:    fixed_1080p = pack_settings(DOT_3X, TONE_STANDARD, BLOOM_SOFT,
				                                                CURVE_MILD, HALO_050X,
				                                                CURVE_MILD, SPREAD_WIDE2,
				                                                KNEE_16, INTER_SHORT,
				                                                INTRA_OFF, COLORSPACE_G08_709,
				                                                CHANNEL_ORIGINAL, SLOT_MASK_ON,
				                                                HALO_GRID_16);
				PROFILE_OVERDRIVEN: fixed_1080p = pack_settings(DOT_3X, TONE_STANDARD,
				                                                BLOOM_NORMAL, CURVE_MILD,
				                                                HALO_050X, CURVE_MILD_P,
				                                                SPREAD_WIDE2, KNEE_16,
				                                                INTER_MEDIUM, INTRA_OFF,
				                                                COLORSPACE_G08_709,
				                                                CHANNEL_ORIGINAL, SLOT_MASK_ON,
				                                                HALO_GRID_16);
				PROFILE_PLASMA:     fixed_1080p = pack_settings(DOT_3X, TONE_STANDARD,
				                                                BLOOM_SOFT, CURVE_MILD_P,
				                                                HALO_150X, CURVE_MILD,
				                                                SPREAD_WIDE2, KNEE_8, INTER_MEDIUM,
				                                                INTRA_LUT_A, COLORSPACE_OFF,
				                                                CHANNEL_ORIGINAL, SLOT_MASK_OFF,
				                                                HALO_GRID_16);
				PROFILE_S_NEGATIVE: fixed_1080p = pack_settings(DOT_3X, TONE_OFF, BLOOM_SOFT,
				                                                CURVE_MOD_PLUS, HALO_100X,
				                                                CURVE_MILD_P, SPREAD_WIDE2,
				                                                KNEE_24, INTER_LONG,
				                                                INTRA_LUT_C, COLORSPACE_OFF,
				                                                CHANNEL_NEGATIVE, SLOT_MASK_OFF,
				                                                HALO_GRID_16);
				default:            fixed_1080p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	function automatic logic [1:0] profile_resolution(input logic [11:0] height);
		if (height >= 12'd1000)      profile_resolution = 2'd3;
		else if (height >= 12'd700) profile_resolution = 2'd2;
		else if (height >= 12'd400) profile_resolution = 2'd1;
		else                      profile_resolution = 2'd0;
	endfunction

	function automatic vfb_profile_settings_t fixed_profile(
		input logic [2:0] profile_i,
		input logic [1:0] resolution_i
	);
		case (resolution_i)
			2'd3:    fixed_profile = fixed_1080p(profile_i);
			2'd2:    fixed_profile = fixed_720p(profile_i);
			2'd1:    fixed_profile = fixed_480p(profile_i);
			default: fixed_profile = fixed_240p(profile_i);
		endcase
	endfunction

endpackage

`default_nettype wire

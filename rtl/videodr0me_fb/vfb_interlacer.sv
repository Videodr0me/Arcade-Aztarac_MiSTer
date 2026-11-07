//============================================================================
//  720x480p to 720x480i field converter
//  Copyright (C) 2026 Videodr0me
//============================================================================

`default_nettype none

module vfb_interlacer
(
	input  wire        clk_sys,
	input  wire        reset,
	input  wire        enable,
	input  wire signed [4:0] vertical_offset,
	input  wire  [9:0] hs_start, hs_end,

	input  wire        ce_pix_in,
	input  wire  [7:0] r_in,
	input  wire  [7:0] g_in,
	input  wire  [7:0] b_in,
	input  wire        hsync_in,
	input  wire        vsync_in,
	input  wire        hblank_in,
	input  wire        vblank_in,

	output logic       ce_pix_out,
	output logic [7:0] r_out,
	output logic [7:0] g_out,
	output logic [7:0] b_out,
	output logic       hsync_out,
	output logic       vsync_out,
	output logic       hblank_out,
	output logic       vblank_out,
	output logic       field_out
);

	localparam logic  [9:0] H_ACTIVE          =  10'd720;
	localparam logic  [9:0] LINE_SAMPLES      =  10'd884;
	localparam logic  [9:0] HALF_LINE         =  10'd442;
	localparam logic [11:0] VS_SAMPLES        = 12'd2652;
	localparam logic [18:0] FIELD_SAMPLES     = 19'd233818;
	localparam logic [18:0] ACTIVE_START_EVEN =  19'd15912;
	localparam logic [18:0] ACTIVE_START_ODD  =  19'd16354;
	localparam logic [18:0] ACTIVE_END_EVEN   = 19'd228072;
	localparam logic [18:0] ACTIVE_END_ODD    = 19'd228514;
	localparam logic [18:0] FIELD_PHASE_INIT  =  19'd15470;

	function automatic logic [18:0] shift_phase(input logic [18:0] base, input logic signed [19:0] shift);
		return 19'($signed({1'b0, base}) + shift);
	endfunction

	logic       input_hblank_q    =  1'b1;
	logic       input_vblank_q    =  1'b1;
	logic [9:0] source_x          = 10'd0;
	logic [8:0] source_y          =  9'd0;
	logic       input_vblank_seen =  1'b0;
	logic       stream_locked     =  1'b0;

	logic [18:0] field_phase      = FIELD_PHASE_INIT;
	logic [9:0]  output_x         = HALF_LINE;
	logic        output_field     = 1'b0;
	logic        active_line_bank = 1'b0;
	logic        output_primed    = 1'b0;
	logic        output_divider   = 1'b0;

	logic [18:0] active_start;
	logic [18:0] active_end;
	logic signed [19:0] vertical_shift;
	logic [18:0] active_start_even = ACTIVE_START_EVEN, active_start_odd = ACTIVE_START_ODD;
	logic [18:0] active_end_even   = ACTIVE_END_EVEN,   active_end_odd   = ACTIVE_END_ODD;
	wire  [18:0] field_phase_init  = shift_phase(FIELD_PHASE_INIT, vertical_shift);
	logic  [9:0] hs_start_q = 10'd755, hs_end_q = 10'd821;
	logic [11:0] vs_end_q = 12'd3407;
	logic        current_hblank;
	logic        current_vblank;
	logic        current_hsync;
	logic        current_vsync;
	logic [10:0] read_address;
	logic [10:0] write_address;
	logic        write_line;
	logic [10:0] read_address_q  = 11'd0;
	logic [10:0] write_address_q = 11'd0;
	logic [23:0] write_data_q    = 24'd0;
	logic        write_line_q    =  1'b0;

	(* ramstyle = "M10K, no_rw_check" *)
	logic [23:0] line_memory [0:1439];
	logic [23:0] line_read_q = 24'd0;

	logic sample_0_valid_q  = 1'b0;
	logic sample_0_hblank_q = 1'b1;
	logic sample_0_vblank_q = 1'b1;
	logic sample_0_hsync_q  = 1'b1;
	logic sample_0_vsync_q  = 1'b1;
	logic sample_0_field_q  = 1'b0;
	logic sample_0_ready_q  = 1'b0;
	logic sample_1_valid_q  = 1'b0;
	logic sample_1_hblank_q = 1'b1;
	logic sample_1_vblank_q = 1'b1;
	logic sample_1_hsync_q  = 1'b1;
	logic sample_1_vsync_q  = 1'b1;
	logic sample_1_field_q  = 1'b0;
	logic sample_1_ready_q  = 1'b0;

	logic        interlaced_ce_q     =  1'b0;
	logic [23:0] interlaced_rgb_q    = 24'd0;
	logic        interlaced_hblank_q =  1'b1;
	logic        interlaced_vblank_q =  1'b1;
	logic        interlaced_hsync_q  =  1'b1;
	logic        interlaced_vsync_q  =  1'b1;
	logic        interlaced_field_q  =  1'b0;

	wire input_frame_start = ce_pix_in && input_vblank_seen && input_vblank_q && !vblank_in;
	wire output_step       = enable && ce_pix_in && output_divider;

	// Each image row spans half a field scanline. Shift the active window and
	// its initial phase together to keep field parity and line-buffer delivery aligned.
	always_ff @(posedge clk_sys) begin
		// Apply both axes where the incoming frame re-anchors the output field.
		// Both possible horizontal phases (0 and 442) are outside the sync pulse.
		if (input_frame_start) begin
			active_start_even <= shift_phase(ACTIVE_START_EVEN, vertical_shift);
			active_start_odd  <= shift_phase(ACTIVE_START_ODD,  vertical_shift);
			active_end_even   <= shift_phase(ACTIVE_END_EVEN,   vertical_shift);
			active_end_odd    <= shift_phase(ACTIVE_END_ODD,    vertical_shift);
			hs_start_q        <= hs_start;
			hs_end_q          <= hs_end;
			vs_end_q          <= {2'b0, hs_start} + VS_SAMPLES;
		end
	end

	always_comb begin
		case (vertical_offset)
			5'sd4:   vertical_shift = 20'( 2 * int'(LINE_SAMPLES));
			5'sd8:   vertical_shift = 20'( 4 * int'(LINE_SAMPLES));
			5'sd12:  vertical_shift = 20'( 6 * int'(LINE_SAMPLES));
			-5'sd4:  vertical_shift = 20'(-2 * int'(LINE_SAMPLES));
			-5'sd8:  vertical_shift = 20'(-4 * int'(LINE_SAMPLES));
			-5'sd10: vertical_shift = 20'(-5 * int'(LINE_SAMPLES));
			default: vertical_shift = 20'sd0;
		endcase
		active_start   = output_field ? active_start_odd : active_start_even;
		active_end     = output_field ? active_end_odd   : active_end_even;
		current_hblank = (output_x >= H_ACTIVE);
		current_vblank = (field_phase < active_start) || (field_phase >= active_end);
		current_hsync  = !((output_x >= hs_start_q) && (output_x < hs_end_q));
		// Alternate fields naturally begin on opposite half-line phases.
		current_vsync = !((field_phase >= {9'd0, hs_start_q}) && (field_phase < {7'd0, vs_end_q}));

		read_address  = active_line_bank ? (11'd720 + {1'b0, output_x}) : {1'b0, output_x};
		if (output_x >= H_ACTIVE) read_address = 11'd0;

		write_address = source_y[1] ? (11'd720 + {1'b0, source_x}) : {1'b0, source_x};
		write_line    = ce_pix_in && !hblank_in && !vblank_in && (source_x < H_ACTIVE) &&
		                (source_y[0] == output_field);
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			input_hblank_q    <=  1'b1;
			input_vblank_q    <=  1'b1;
			source_x          <= 10'd0;
			source_y          <=  9'd0;
			input_vblank_seen <=  1'b0;
			stream_locked     <=  1'b0;
		end else if (ce_pix_in) begin
			input_hblank_q <= hblank_in;
			input_vblank_q <= vblank_in;

			if (vblank_in)         input_vblank_seen <= 1'b1;
			if (input_frame_start) stream_locked     <= 1'b1;

			if (vblank_in) begin
				source_x <= 10'd0;
				source_y <=  9'd0;
			end else if (hblank_in) begin
				source_x <= 10'd0;
				if (!input_hblank_q && !input_vblank_q && (source_y < 9'd479))
					source_y <= source_y + 1'd1;
			end else begin
				source_x <= source_x + 1'd1;
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset)
			output_divider <= 1'b0;
		else if (input_frame_start)
			output_divider <= 1'b0;
		else if (enable && ce_pix_in)
			output_divider <= !output_divider;
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			write_line_q        <=  1'b0;
			read_address_q      <= 11'd0;
			field_phase         <= field_phase_init;
			output_x            <= HALF_LINE;
			output_field        <=  1'b0;
			active_line_bank    <=  1'b0;
			output_primed       <=  1'b0;
			line_read_q         <= 24'd0;
			sample_0_valid_q    <=  1'b0;
			sample_0_hblank_q   <=  1'b1;
			sample_0_vblank_q   <=  1'b1;
			sample_0_hsync_q    <=  1'b1;
			sample_0_vsync_q    <=  1'b1;
			sample_0_field_q    <=  1'b0;
			sample_0_ready_q    <=  1'b0;
			sample_1_valid_q    <=  1'b0;
			sample_1_hblank_q   <=  1'b1;
			sample_1_vblank_q   <=  1'b1;
			sample_1_hsync_q    <=  1'b1;
			sample_1_vsync_q    <=  1'b1;
			sample_1_field_q    <=  1'b0;
			sample_1_ready_q    <=  1'b0;
			interlaced_ce_q     <=  1'b0;
			interlaced_rgb_q    <= 24'd0;
			interlaced_hblank_q <=  1'b1;
			interlaced_vblank_q <=  1'b1;
			interlaced_hsync_q  <=  1'b1;
			interlaced_vsync_q  <=  1'b1;
			interlaced_field_q  <=  1'b0;
		end else begin
			if (write_line_q) line_memory[write_address_q] <= write_data_q;
			write_line_q <= write_line;
			if (write_line) begin
				write_address_q <= write_address;
				write_data_q    <= {r_in, g_in, b_in};
			end

			interlaced_ce_q <= 1'b0;

			if (input_frame_start && !stream_locked) begin
				field_phase      <= field_phase_init;
				output_x         <= HALF_LINE;
				output_field     <=  1'b0;
				active_line_bank <=  1'b0;
				output_primed    <=  1'b0;
				read_address_q   <= 11'd0;
				line_read_q      <= 24'd0;
				sample_0_valid_q <=  1'b0;
				sample_0_ready_q <=  1'b0;
				sample_1_valid_q <=  1'b0;
				sample_1_ready_q <=  1'b0;
			end else if (output_step && stream_locked) begin
				interlaced_ce_q     <= sample_1_valid_q && sample_1_ready_q;
				interlaced_rgb_q    <= (sample_1_valid_q && !sample_1_hblank_q &&
				                        !sample_1_vblank_q) ? line_read_q : 24'd0;
				interlaced_hblank_q <= sample_1_hblank_q;
				interlaced_vblank_q <= sample_1_vblank_q;
				interlaced_hsync_q  <= sample_1_hsync_q;
				interlaced_vsync_q  <= sample_1_vsync_q;
				interlaced_field_q  <= sample_1_field_q;

				line_read_q         <= line_memory[read_address_q];
				read_address_q      <= read_address;
				sample_1_valid_q    <= sample_0_valid_q;
				sample_1_hblank_q   <= sample_0_hblank_q;
				sample_1_vblank_q   <= sample_0_vblank_q;
				sample_1_hsync_q    <= sample_0_hsync_q;
				sample_1_vsync_q    <= sample_0_vsync_q;
				sample_1_field_q    <= sample_0_field_q;
				sample_1_ready_q    <= sample_0_ready_q;
				sample_0_valid_q    <= 1'b1;
				sample_0_hblank_q   <= current_hblank;
				sample_0_vblank_q   <= current_vblank;
				sample_0_hsync_q    <= current_hsync;
				sample_0_vsync_q    <= current_vsync;
				sample_0_field_q    <= output_field;
				sample_0_ready_q    <= output_primed;

				if (field_phase == active_start - 1'd1)
					active_line_bank <= 1'b0;
				else if (!current_vblank && (output_x == LINE_SAMPLES - 1'd1))
					active_line_bank <= !active_line_bank;

				output_x <= (output_x == LINE_SAMPLES - 1'd1) ? 10'd0 : output_x + 1'd1;
				if (field_phase == FIELD_SAMPLES - 1'd1) begin
					field_phase   <= 19'd0;
					output_field  <= !output_field;
					output_primed <= 1'b1;
				end else begin
					field_phase <= field_phase + 1'd1;
				end
			end

			// One progressive input frame lasts exactly one output field.
			// Re-anchor every frame without changing field parity.
			if (input_frame_start && stream_locked) begin
				field_phase <= field_phase_init;
				if (output_step && (field_phase == FIELD_SAMPLES - 1'd1))
					output_x <= !output_field ? 10'd0 : HALF_LINE;
				else
					output_x <= output_field ? 10'd0 : HALF_LINE;
			end
		end
	end

	always_comb begin
		if (enable) begin
			ce_pix_out = interlaced_ce_q;
			r_out      = interlaced_rgb_q[23:16];
			g_out      = interlaced_rgb_q[15:8];
			b_out      = interlaced_rgb_q[7:0];
			hsync_out  = interlaced_hsync_q;
			vsync_out  = interlaced_vsync_q;
			hblank_out = interlaced_hblank_q;
			vblank_out = interlaced_vblank_q;
			field_out  = interlaced_field_q;
		end else begin
			ce_pix_out = ce_pix_in;
			r_out      = r_in;
			g_out      = g_in;
			b_out      = b_in;
			hsync_out  = hsync_in;
			vsync_out  = vsync_in;
			hblank_out = hblank_in;
			vblank_out = vblank_in;
			field_out  = 1'b0;
		end
	end

endmodule

`default_nettype wire

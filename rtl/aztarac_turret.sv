// Turret aiming. The game maps 128 dial counts to one revolution.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

module aztarac_turret (
	input  wire                clk, restart, sample,
	input  wire         [15:0] stick_0, stick_1,
	input  wire signed  [9:0]  wheel_delta,
	input  wire         [1:0]  mode,
	input  wire         [2:0]  sensitivity,
	input  wire                reverse,
	output wire                active,
	output logic               aim_valid = 0,
	output logic        [6:0]  aim = 0,
	output logic signed [7:0]  turn = 0
);
	function automatic [8:0] magnitude(input logic signed [7:0] value);
		logic signed [8:0] extended_value;
		begin
			extended_value = {value[7], value};
			magnitude      = value < 0 ? $unsigned(-extended_value) : $unsigned(extended_value);
		end
	endfunction
	function automatic [15:0] increment(input logic [3:0] stage);
		case (stage)
			0:       increment = 8192;
			1:       increment = 4836;
			2:       increment = 2555;
			3:       increment = 1297;
			4:       increment =  651;
			5:       increment =  326;
			6:       increment =  163;
			7:       increment =   81;
			8:       increment =   41;
			default: increment =   20;
		endcase
	endfunction

	wire         [9:0]  radius_0 = {1'b0,magnitude(stick_0[7:0])} + {1'b0,magnitude(stick_0[15:8])};
	wire         [9:0]  radius_1 = {1'b0,magnitude(stick_1[7:0])} + {1'b0,magnitude(stick_1[15:8])};
	wire         [15:0] selected = radius_1 > radius_0 ? stick_1 : stick_0;
	// TATE rotates the display for a turned monitor; aim stays in game coordinates.
	wire signed  [7:0]  x = $signed(selected[7:0]), y = $signed(selected[15:8]);
	wire         [8:0]  abs_x = magnitude(x), abs_y = magnitude(y);
	wire         [9:0]  radius = abs_x >= abs_y ? {1'b0,abs_x} + {2'd0,abs_y[8:1]}
	                                            : {1'b0,abs_y} + {2'd0,abs_x[8:1]};
	localparam [1:0] DIRECTIONAL = 0, HORIZONTAL = 1, RATE = 2, WHEEL = 3;
	logic               stick_ready = 0, engaged = 0, position_valid = 0;
	wire                neutral = mode == DIRECTIONAL ? radius <= 20 :
	                              mode == HORIZONTAL ? abs_x < 8 : abs_x <= 20;
	logic        [15:0] previous = 0;
	logic               busy     = 0;
	logic        [3:0]  stage    = 0;
	logic               x_negative, y_negative;
	logic signed [14:0] cordic_x, cordic_y;
	logic signed [16:0] cordic_angle;
	logic signed [14:0] next_x, next_y;
	logic signed [16:0] next_angle;
	logic        [15:0] quadrant_angle, angle;
	always_comb begin
		next_x     = cordic_x;
		next_y     = cordic_y;
		next_angle = cordic_angle;
		if (cordic_y > 0) begin
			next_x     = cordic_x + (cordic_y >>> stage);
			next_y     = cordic_y - (cordic_x >>> stage);
			next_angle = cordic_angle + $signed({1'b0,increment(stage)});
		end else if (cordic_y < 0) begin
			next_x     = cordic_x - (cordic_y >>> stage);
			next_y     = cordic_y + (cordic_x >>> stage);
			next_angle = cordic_angle - $signed({1'b0,increment(stage)});
		end
		quadrant_angle = next_angle < 0 ? 16'd0 : next_angle > 16384 ? 16'd16384 : next_angle[15:0];
		case ({y_negative,x_negative})
			0:       angle = quadrant_angle;
			1:       angle = 16'd32768 - quadrant_angle;
			3:       angle = 16'd32768 + quadrant_angle;
			default: angle = 16'd0 - quadrant_angle;
		endcase
	end

	// Gains in quarter units: 1, 2, 3, 4, 5, 6, 8, 12. A wheel count is
	// 1 dial count at 1x; a stick deflection of 128 gives 128 counts/second.
	wire  signed [13:0] motion = mode == WHEEL ? 14'(wheel_delta) : 14'(x);
	logic signed [13:0] scaled;
	always_comb begin
		case (sensitivity)
			0: scaled = motion;
			1: scaled = motion <<< 1;
			2: scaled = (motion <<< 1) + motion;
			3: scaled = motion <<< 2;
			4: scaled = (motion <<< 2) + motion;
			5: scaled = (motion <<< 2) + (motion <<< 1);
			6: scaled = motion <<< 3;
			7: scaled = (motion <<< 3) + (motion <<< 2);
		endcase
	end
	logic signed [10:0] phase = 0;
	wire  signed [13:0] phase_sum = scaled + 14'(phase);
	wire         [13:0] phase_abs = phase_sum < 0 ? $unsigned(-phase_sum) : $unsigned(phase_sum);
	// At 200 Hz the stick divisor is 4 * 200; a sample can cross at most two counts.
	wire          [1:0] rate_steps = phase_abs >= 1600 ? 2'd2 : {1'b0,phase_abs >= 800};
	wire          [7:0] steps = mode == WHEEL ? phase_abs[9:2] : {6'd0,rate_steps};
	wire signed  [10:0] remainder = mode == WHEEL ? $signed({9'd0,phase_abs[1:0]}) :
	                                $signed(phase_abs[10:0] - (rate_steps[1] ? 11'd1600 :
	                                                           rate_steps[0] ? 11'd800 : 11'd0));
	wire          [7:0] horizontal = selected[7:0] ^ 8'h80;
	wire          [6:0] horizontal_aim = reverse ? 7'd112 + horizontal[7:1] :
	                                              7'd112 - horizontal[7:1];

	// Immediate ownership also covers host button updates before the next sample.
	assign active = mode == DIRECTIONAL ? (radius >= 28 || (engaged && radius > 20)) :
	                mode == HORIZONTAL ? x != 0 : mode == RATE && abs_x > 20;

	always_ff @(posedge clk) begin
		aim_valid <= 0;
		turn      <= 0;
		if (restart) begin
			stick_ready    <= neutral;
			engaged        <= 0;
			position_valid <= 0;
			busy           <= 0;
			phase          <= 0;
		end else begin
			if (neutral) stick_ready <= 1;
			if ((mode == WHEEL && wheel_delta != 0) ||
			    (mode == RATE && sample && stick_ready && !neutral)) begin
				phase <= phase_sum < 0 ? -remainder : remainder;
				// Positive physical motion decrements the original cabinet dial.
				turn  <= ((phase_sum < 0) ^ reverse) ? $signed(steps) : -$signed(steps);
			end else if (mode == RATE && sample && neutral) phase <= 0;
			if (sample && stick_ready && !busy) begin
				if (mode == DIRECTIONAL) begin
					if (radius <= 20) begin
						engaged        <= 0;
						position_valid <= 0;
					end
					else if ((engaged || radius >= 28) && (!position_valid || previous != selected)) begin
						engaged        <= 1;
						position_valid <= 1;
						previous       <= selected;
						cordic_x       <= $signed({1'b0,abs_x,5'd0});
						cordic_y       <= $signed({1'b0,abs_y,5'd0});
						cordic_angle   <= 0;
						x_negative     <= x[7];
						y_negative     <= y[7];
						stage          <= 0;
						busy           <= 1;
					end
				end else if (mode == HORIZONTAL &&
				             (position_valid ? previous[7:0] != selected[7:0] : !neutral)) begin
					position_valid <= 1;
					previous       <= selected;
					aim            <= horizontal_aim;
					aim_valid      <= 1;
				end
			end
			if (busy) begin
				cordic_x     <= next_x;
				cordic_y     <= next_y;
				cordic_angle <= next_angle;
				if (stage == 9) begin
					busy      <= 0;
					aim_valid <= 1;
					// ROM angle zero points diagonally up/right; 112 points right.
					aim <= 7'd112 - (7'(angle[15:9]) + {6'd0,angle[8]});
				end else stage <= stage + 1'd1;
			end
		end
	end
endmodule

`default_nettype wire

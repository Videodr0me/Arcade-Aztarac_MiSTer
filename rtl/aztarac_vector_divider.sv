// SPDX-License-Identifier: GPL-3.0-or-later
// Written 2026 by Videodr0me
// Signed floor division by a nonzero positive 15-bit span. Two quotient
// bits per clock bound the carry chain; all four coordinate lanes finish together.
`default_nettype none

module aztarac_vector_divider (
	input  wire                clk, reset, start,
	input  wire  signed [31:0] numerator,
	input  wire         [14:0] divisor,
	output wire  signed [31:0] quotient,
	output logic               done
);
	logic   [31:0] quotient_q, quotient_d;
	logic   [14:0] remainder_q, remainder_d, divisor_q;
	logic   [15:0] trial, difference;
	logic          negative_q, busy;
	logic   [3:0]  pairs_left;
	integer        bit_step;

	assign quotient = negative_q ? (~$signed(quotient_q) + (remainder_q == 0 ? 32'sd1 : 32'sd0))
	                             : $signed(quotient_q);
	always_comb begin
		quotient_d  = quotient_q;
		remainder_d = remainder_q;
		trial       = 16'd0;
		difference  = 16'd0;
		bit_step    =     0;
		for (bit_step = 0; bit_step < 2; bit_step = bit_step + 1) begin
			trial       = {remainder_d, quotient_d[31]};
			difference  = trial - {1'b0, divisor_q};
			remainder_d = difference[15] ? trial[14:0] : difference[14:0];
			quotient_d  = {quotient_d[30:0], !difference[15]};
		end
	end

	always_ff @(posedge clk) begin
		done <= 1'b0;
		if (reset) begin
			quotient_q  <= 32'd0;
			remainder_q <= 15'd0;
			divisor_q   <= 15'd1;
			negative_q  <=  1'b0;
			busy        <=  1'b0;
			pairs_left  <=  4'd0;
		end else if (start && !busy) begin
			quotient_q  <= numerator[31] ? -numerator : numerator;
			remainder_q <= 15'd0;
			divisor_q   <= divisor;
			negative_q  <= numerator[31];
			busy        <=  1'b1;
			pairs_left  <= 4'd15;
		end else if (busy) begin
			quotient_q  <= quotient_d;
			remainder_q <= remainder_d;
			pairs_left  <= pairs_left - 1'b1;
			if (pairs_left == 0) begin
				busy <= 1'b0;
				done <= 1'b1;
			end
		end
	end
endmodule

`default_nettype wire

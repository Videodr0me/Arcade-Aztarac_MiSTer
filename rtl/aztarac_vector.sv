// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Videodr0me
// Aztarac object/definition display list. Functional reference: MAME (BSD-3-Clause).
`default_nettype none

module aztarac_vector (
	input  wire                clk,
	input  wire                reset,
	input  wire                pause,
	input  wire                ce,
	input  wire                start,
	input  wire         [7:0]  brightness,
	output logic        [10:0] ram_addr,
	input  wire         [15:0] ram_c,
	input  wire         [9:0]  ram_x,
	input  wire         [9:0]  ram_y,
	output logic               busy,
	output logic               fault,
	output logic               vector_valid,
	output logic signed [11:0] vector_x0, vector_y0, vector_x1, vector_y1,
	output logic        [5:0]  vector_color,
	output logic        [7:0]  vector_intensity,
	output logic               frame_done
);
	typedef enum logic [2:0] { IDLE, OBJECT_WAIT, OBJECT_READ, HEADER_WAIT,
		HEADER_READ, DEFINITION_WAIT, DEFINITION_READ } state_t;
	state_t             state;
	logic        [10:0] object_addr;
	logic        [9:0]  definitions_left;
	logic signed [9:0]  offset_x, offset_y;
	logic signed [11:0] beam_x, beam_y;
	logic               color_latched;
	logic        [5:0]  color;
	logic        [7:0]  intensity;
	logic        [13:0] fetch_count;
	wire  signed [11:0] endpoint_x = {{2{offset_x[9]}},offset_x} + {{2{ram_x[9]}},ram_x};
	wire  signed [11:0] endpoint_y = {{2{offset_y[9]}},offset_y} + {{2{ram_y[9]}},ram_y};

	always_ff @(posedge clk) begin
		vector_valid <= 1'b0;
		frame_done   <= 1'b0;
		if (reset) begin
			state            <= IDLE;
			busy             <=   1'b0;
			fault            <=   1'b0;
			ram_addr         <=  11'd0;
			object_addr      <=  11'd0;
			definitions_left <=  10'd0;
			offset_x         <= 10'sd0;
			offset_y         <= 10'sd0;
			beam_x           <= 12'sd0;
			beam_y           <= 12'sd0;
			color_latched    <=   1'b0;
			color            <=   6'd0;
			intensity        <=   8'd0;
			fetch_count      <=  14'd0;
			vector_x0        <= 12'sd0;
			vector_y0        <= 12'sd0;
			vector_x1        <= 12'sd0;
			vector_y1        <= 12'sd0;
			vector_color     <=   6'd0;
			vector_intensity <=   8'd0;
		end else if (start && !pause) begin
			// UBR zero acknowledges the frame IRQ without replacing the list.
			if (brightness != 0) begin
				if (busy) fault <= 1'b1;
				state       <= OBJECT_WAIT;
				busy        <=  1'b1;
				ram_addr    <= 11'd0;
				object_addr <= 11'd0;
				fetch_count <= 14'd0;
			end
		end else if (ce && !pause && busy) begin
			case (state)
				OBJECT_WAIT:     state <= OBJECT_READ;
				OBJECT_READ:     begin
					fetch_count <= fetch_count + 1'b1;
					if (ram_c[14]) begin
						busy       <= 1'b0;
						state      <= IDLE;
						frame_done <= 1'b1;
					end else if (&object_addr || &fetch_count) begin
						busy  <= 1'b0;
						state <= IDLE;
						fault <= 1'b1;
					end else begin
						object_addr <= object_addr + 1'b1;
						if (ram_c[13]) begin
							ram_addr <= object_addr + 1'b1;
							state    <= OBJECT_WAIT;
						end else begin
							offset_x <= $signed(ram_x);
							offset_y <= $signed(ram_y);
							beam_x   <= {{2{ram_x[9]}},ram_x};
							beam_y   <= {{2{ram_y[9]}},ram_y};
							ram_addr <= ram_c[11:1];
							state    <= HEADER_WAIT;
						end
					end
				end
				HEADER_WAIT:     state <= HEADER_READ;
				HEADER_READ:     begin
					if (ram_y[9]) begin
						// A negative definition count is not a valid game list.
						fault <= 1'b1;
						busy  <= 1'b0;
						state <= IDLE;
					end else begin
						definitions_left <= ram_y + 1'b1;
						color_latched    <= |ram_c[15:8];
						color            <= ram_c[5:0];
						intensity        <= ram_c[15:8];
						ram_addr         <= ram_addr + 1'b1;
						state            <= DEFINITION_WAIT;
					end
				end
				DEFINITION_WAIT: state <= DEFINITION_READ;
				DEFINITION_READ: begin
					vector_valid     <= 1'b1;
					vector_x0        <= beam_x;
					vector_y0        <= beam_y;
					vector_x1        <= endpoint_x;
					vector_y1        <= endpoint_y;
					vector_color     <= color_latched ? color : ram_c[5:0];
					vector_intensity <= color_latched ? ((|ram_c[15:8]) ? intensity : 8'd0)
					                                  : ram_c[15:8];
					beam_x           <= endpoint_x;
					beam_y           <= endpoint_y;
					definitions_left <= definitions_left - 1'b1;
					fetch_count      <= fetch_count + 1'b1;
					if (&fetch_count) begin
						fault <= 1'b1;
						busy  <= 1'b0;
						state <= IDLE;
					end else if (definitions_left == 1) begin
						ram_addr <= object_addr;
						state    <= OBJECT_WAIT;
					end else begin
						ram_addr <= ram_addr + 1'b1;
						state    <= DEFINITION_WAIT;
					end
				end
				default:         begin state <= IDLE; busy <= 1'b0; end
			endcase
		end
	end
endmodule

`default_nettype wire

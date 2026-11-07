// Selectable cubic reconstruction of the compressed RGB halo.
// Copyright (C) 2026 Videodr0me
// Five rows per epoch retain four contributing rows and the row being written.
`default_nettype none
module vfb_halo_bspline #(
	parameter integer COARSE_WIDTH =  184,
	parameter integer MAX_WIDTH    = 1472,
	parameter integer H_DELAY      =   77,
	parameter integer ADDR_W       = $clog2(COARSE_WIDTH + 5)
) (
	input  wire               clk_sys, reset, ce_pix, grid_8,
	input  wire  [1:0]        shape,
	input  wire               wr_valid, wr_epoch,
	input  wire  [2:0]        wr_bank,
	input  wire  [ADDR_W-1:0] wr_x,
	input  wire  [23:0]       wr_rgb,
	input  wire               line_start, line_epoch,
	input  wire  [11:0]       line_y, active_height,
	input  wire  [7:0]        rows_done_a, rows_done_b,
	input  wire  [ADDR_W-1:0] coarse_width,
	output logic [23:0]       rgb,
	output logic              valid
);
	// Q12 cubic coefficients at t=(phase+0.5)/grid, normalized to 4096.
	// Shapes (B,C): (1,0), (1.5,-0.25), (1.75,-0.375), (2,-0.5).
	// All taps are nonnegative; mirrored phases and the Normal table are exact.
	function automatic [47:0] bspline_weights(
		input logic [3:0] phase, input logic grid, input logic [1:0] shape_sel
	);
		case ({shape_sel, grid, phase})
			// B=1, C=0; 16x16 grid.
			7'd0:  bspline_weights = {12'd0, 12'd749, 12'd2726, 12'd621};
			7'd1:  bspline_weights = {12'd1, 12'd891, 12'd2696, 12'd508};
			7'd2:  bspline_weights = {12'd3, 12'd1045, 12'd2638, 12'd410};
			7'd3:  bspline_weights = {12'd7, 12'd1207, 12'd2556, 12'd326};
			7'd4:  bspline_weights = {12'd15, 12'd1375, 12'd2453, 12'd253};
			7'd5:  bspline_weights = {12'd28, 12'd1545, 12'd2330, 12'd193};
			7'd6:  bspline_weights = {12'd46, 12'd1715, 12'd2192, 12'd143};
			7'd7:  bspline_weights = {12'd70, 12'd1882, 12'd2042, 12'd102};
			7'd8:  bspline_weights = {12'd102, 12'd2042, 12'd1882, 12'd70};
			7'd9:  bspline_weights = {12'd143, 12'd2192, 12'd1715, 12'd46};
			7'd10: bspline_weights = {12'd193, 12'd2330, 12'd1545, 12'd28};
			7'd11: bspline_weights = {12'd253, 12'd2453, 12'd1375, 12'd15};
			7'd12: bspline_weights = {12'd326, 12'd2556, 12'd1207, 12'd7};
			7'd13: bspline_weights = {12'd410, 12'd2638, 12'd1045, 12'd3};
			7'd14: bspline_weights = {12'd508, 12'd2696, 12'd891, 12'd1};
			7'd15: bspline_weights = {12'd621, 12'd2726, 12'd749, 12'd0};
			// B=1, C=0; 8x8 grid.
			7'd16: bspline_weights = {12'd0, 12'd818, 12'd2715, 12'd563};
			7'd17: bspline_weights = {12'd5, 12'd1125, 12'd2600, 12'd366};
			7'd18: bspline_weights = {12'd21, 12'd1460, 12'd2393, 12'd222};
			7'd19: bspline_weights = {12'd57, 12'd1799, 12'd2118, 12'd122};
			7'd20: bspline_weights = {12'd122, 12'd2118, 12'd1799, 12'd57};
			7'd21: bspline_weights = {12'd222, 12'd2393, 12'd1460, 12'd21};
			7'd22: bspline_weights = {12'd366, 12'd2600, 12'd1125, 12'd5};
			7'd23: bspline_weights = {12'd563, 12'd2715, 12'd818, 12'd0};
			// B=1.5, C=-0.25; 16x16 grid.
			7'd32: bspline_weights = {12'd1, 12'd1087, 12'd2047, 12'd961};
			7'd33: bspline_weights = {12'd9, 12'd1207, 12'd2039, 12'd841};
			7'd34: bspline_weights = {12'd25, 12'd1319, 12'd2023, 12'd729};
			7'd35: bspline_weights = {12'd49, 12'd1423, 12'd1999, 12'd625};
			7'd36: bspline_weights = {12'd81, 12'd1519, 12'd1967, 12'd529};
			7'd37: bspline_weights = {12'd121, 12'd1607, 12'd1927, 12'd441};
			7'd38: bspline_weights = {12'd169, 12'd1687, 12'd1879, 12'd361};
			7'd39: bspline_weights = {12'd225, 12'd1759, 12'd1823, 12'd289};
			7'd40: bspline_weights = {12'd289, 12'd1823, 12'd1759, 12'd225};
			7'd41: bspline_weights = {12'd361, 12'd1879, 12'd1687, 12'd169};
			7'd42: bspline_weights = {12'd441, 12'd1927, 12'd1607, 12'd121};
			7'd43: bspline_weights = {12'd529, 12'd1967, 12'd1519, 12'd81};
			7'd44: bspline_weights = {12'd625, 12'd1999, 12'd1423, 12'd49};
			7'd45: bspline_weights = {12'd729, 12'd2023, 12'd1319, 12'd25};
			7'd46: bspline_weights = {12'd841, 12'd2039, 12'd1207, 12'd9};
			7'd47: bspline_weights = {12'd961, 12'd2047, 12'd1087, 12'd1};
			// B=1.5, C=-0.25; 8x8 grid.
			7'd48: bspline_weights = {12'd4, 12'd1148, 12'd2044, 12'd900};
			7'd49: bspline_weights = {12'd36, 12'd1372, 12'd2012, 12'd676};
			7'd50: bspline_weights = {12'd100, 12'd1564, 12'd1948, 12'd484};
			7'd51: bspline_weights = {12'd196, 12'd1724, 12'd1852, 12'd324};
			7'd52: bspline_weights = {12'd324, 12'd1852, 12'd1724, 12'd196};
			7'd53: bspline_weights = {12'd484, 12'd1948, 12'd1564, 12'd100};
			7'd54: bspline_weights = {12'd676, 12'd2012, 12'd1372, 12'd36};
			7'd55: bspline_weights = {12'd900, 12'd2044, 12'd1148, 12'd4};
			// B=1.75, C=-0.375; 16x16 grid.
			7'd64: bspline_weights = {12'd1, 12'd1256, 12'd1708, 12'd1131};
			7'd65: bspline_weights = {12'd13, 12'd1365, 12'd1711, 12'd1007};
			7'd66: bspline_weights = {12'd36, 12'd1456, 12'd1716, 12'd888};
			7'd67: bspline_weights = {12'd70, 12'd1531, 12'd1720, 12'd775};
			7'd68: bspline_weights = {12'd114, 12'd1591, 12'd1724, 12'd667};
			7'd69: bspline_weights = {12'd168, 12'd1638, 12'd1725, 12'd565};
			7'd70: bspline_weights = {12'd231, 12'd1673, 12'd1722, 12'd470};
			7'd71: bspline_weights = {12'd302, 12'd1698, 12'd1714, 12'd382};
			7'd72: bspline_weights = {12'd382, 12'd1714, 12'd1698, 12'd302};
			7'd73: bspline_weights = {12'd470, 12'd1722, 12'd1673, 12'd231};
			7'd74: bspline_weights = {12'd565, 12'd1725, 12'd1638, 12'd168};
			7'd75: bspline_weights = {12'd667, 12'd1724, 12'd1591, 12'd114};
			7'd76: bspline_weights = {12'd775, 12'd1720, 12'd1531, 12'd70};
			7'd77: bspline_weights = {12'd888, 12'd1716, 12'd1456, 12'd36};
			7'd78: bspline_weights = {12'd1007, 12'd1711, 12'd1365, 12'd13};
			7'd79: bspline_weights = {12'd1131, 12'd1708, 12'd1256, 12'd1};
			// B=1.75, C=-0.375; 8x8 grid.
			7'd80: bspline_weights = {12'd6, 12'd1313, 12'd1708, 12'd1069};
			7'd81: bspline_weights = {12'd52, 12'd1495, 12'd1718, 12'd831};
			7'd82: bspline_weights = {12'd140, 12'd1616, 12'd1725, 12'd615};
			7'd83: bspline_weights = {12'd265, 12'd1686, 12'd1720, 12'd425};
			7'd84: bspline_weights = {12'd425, 12'd1720, 12'd1686, 12'd265};
			7'd85: bspline_weights = {12'd615, 12'd1725, 12'd1616, 12'd140};
			7'd86: bspline_weights = {12'd831, 12'd1718, 12'd1495, 12'd52};
			7'd87: bspline_weights = {12'd1069, 12'd1708, 12'd1313, 12'd6};
			// B=2, C=-0.5; 16x16 grid.
			7'd96:  bspline_weights = {12'd2, 12'd1425, 12'd1368, 12'd1301};
			7'd97:  bspline_weights = {12'd17, 12'd1523, 12'd1382, 12'd1174};
			7'd98:  bspline_weights = {12'd47, 12'd1593, 12'd1408, 12'd1048};
			7'd99:  bspline_weights = {12'd91, 12'd1639, 12'd1442, 12'd924};
			7'd100: bspline_weights = {12'd147, 12'd1663, 12'd1481, 12'd805};
			7'd101: bspline_weights = {12'd214, 12'd1669, 12'd1524, 12'd689};
			7'd102: bspline_weights = {12'd292, 12'd1659, 12'd1566, 12'd579};
			7'd103: bspline_weights = {12'd380, 12'd1636, 12'd1604, 12'd476};
			7'd104: bspline_weights = {12'd476, 12'd1604, 12'd1636, 12'd380};
			7'd105: bspline_weights = {12'd579, 12'd1566, 12'd1659, 12'd292};
			7'd106: bspline_weights = {12'd689, 12'd1524, 12'd1669, 12'd214};
			7'd107: bspline_weights = {12'd805, 12'd1481, 12'd1663, 12'd147};
			7'd108: bspline_weights = {12'd924, 12'd1442, 12'd1639, 12'd91};
			7'd109: bspline_weights = {12'd1048, 12'd1408, 12'd1593, 12'd47};
			7'd110: bspline_weights = {12'd1174, 12'd1382, 12'd1523, 12'd17};
			7'd111: bspline_weights = {12'd1301, 12'd1368, 12'd1425, 12'd2};
			// B=2, C=-0.5; 8x8 grid.
			7'd112:  bspline_weights = {12'd8, 12'd1478, 12'd1372, 12'd1238};
			7'd113:  bspline_weights = {12'd68, 12'd1619, 12'd1423, 12'd986};
			7'd114:  bspline_weights = {12'd179, 12'd1668, 12'd1503, 12'd746};
			7'd115:  bspline_weights = {12'd335, 12'd1649, 12'd1585, 12'd527};
			7'd116:  bspline_weights = {12'd527, 12'd1585, 12'd1649, 12'd335};
			7'd117:  bspline_weights = {12'd746, 12'd1503, 12'd1668, 12'd179};
			7'd118:  bspline_weights = {12'd986, 12'd1423, 12'd1619, 12'd68};
			7'd119:  bspline_weights = {12'd1238, 12'd1372, 12'd1478, 12'd8};
			default: bspline_weights = '0;
		endcase
	endfunction

	logic  [ADDR_W-1:0] rd_addr;
	logic  [23:0]       ram_q [0:1][0:4];
	genvar              e,b;
	generate
	for (e=0;e<2;e=e+1) begin : epoch
		for (b=0;b<5;b=b+1) begin : bank
			vfb_halo_bspline_row #(.DEPTH(COARSE_WIDTH+5), .ADDR_W(ADDR_W)) row_memory (
				.clk(clk_sys), .rd_enable(ce_pix), .rd_address(rd_addr), .rd_data(ram_q[e][b]),
				.wr_enable(wr_valid && wr_epoch == 1'(e) && wr_bank == 3'(b)),
				.wr_address(wr_x), .wr_data(wr_rgb)
			);
		end
	end
	endgenerate

	localparam integer H_STAGES    = 5;
	localparam integer READ_STAGES = 8;
	logic [11:0]       age;
	logic              running;
	logic              line_ready_q, tap_rows_ready_q, line_visible_q, epoch_q;
	logic [7:0]        rows_done_q;
	(* dont_retime *)
	logic [7:0]        tap_y_q [0:3];
	logic [2:0]        banks_q [0:3];
	logic [3:0]        rows_valid_q;
	logic [47:0]       vertical_weights_q;
	logic [12:0]       sample_y_q;
	wire  [12:0]       sample_y    = grid_8 ? ((line_y != 0) ? {1'b0,line_y} - 13'd1 : 13'd0)
	                                        : {1'b0,line_y} + 13'd7;
	wire  [7:0]        coarse_y    = grid_8 ? sample_y_q[10:3] : sample_y_q[11:4];
	wire  [3:0]        v_phase     = grid_8 ? {1'b0,sample_y_q[2:0]} : sample_y_q[3:0];
	wire  [11:0]       first_fetch = 12'(H_DELAY-H_STAGES-READ_STAGES) - (grid_8 ? 12'd24 : 12'd48);
	wire  [11:0]       fetch_delta = age - first_fetch;
	wire               fetch       = running &&
	                                 age >= first_fetch &&
	                                 (grid_8 ? fetch_delta[2:0] == 3'd0 : fetch_delta[3:0] == 4'd0);
	wire  [ADDR_W-1:0] column      = (grid_8 ? ADDR_W'(fetch_delta[11:3])
	                                         : ADDR_W'(fetch_delta[11:4])) + ADDR_W'(2);
	// Prefetch may start the next line before the previous horizontal tail ends.
	wire         horizontal_start = running && age == 12'(H_DELAY-H_STAGES);
	logic [11:0] next_pixel_x;
	logic        horizontal_visible_q;
	wire  [11:0] pixel_x     = horizontal_start ? 12'd0 : next_pixel_x;
	wire  [3:0]  h_phase     = grid_8 ? {1'b0,pixel_x[2:0]} : pixel_x[3:0];
	wire         pixel_valid = (horizontal_start ? (line_visible_q && (|rows_valid_q))
	                                             : horizontal_visible_q) &&
	                           pixel_x < 12'(MAX_WIDTH);
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			next_pixel_x         <= 12'(MAX_WIDTH);
			horizontal_visible_q <= 1'b0;
		end else if (ce_pix) begin
			if (horizontal_start) begin
				next_pixel_x         <= 12'd1;
				horizontal_visible_q <= line_visible_q && (|rows_valid_q);
			end else if (next_pixel_x < 12'(MAX_WIDTH)) begin
				next_pixel_x <= next_pixel_x + 1'b1;
			end
		end
	end

	logic [2:0]  read_phase;
	logic        column_valid_q;
	logic [7:0]  vertical_sample [0:2];
	logic [11:0] vertical_weight;
	logic [19:0] vertical_product [0:2];
	logic [19:0] vertical_acc [0:2];
	logic [13:0] window [0:3][0:2];
	logic [41:0] vertical_result;
	logic [23:0] selected_row [0:3];
	always_comb begin
		for (int k=0;k<4;k=k+1)
			selected_row[k] = (column_valid_q && rows_valid_q[k]) ? ram_q[epoch_q][banks_q[k]]
			                                                      : 24'd0;
		for (int c=0;c<3;c=c+1)
			vertical_result[c*14+:14] = 14'((vertical_acc[c] + vertical_product[c] + 20'd32) >> 6);
	end

	// Three products are reused over four coarse rows. A new column is needed
	// only once per eight or sixteen pixel enables, even at full pixel rate.
	always_ff @(posedge clk_sys) begin
		if (ce_pix)
			for (int c=0;c<3;c=c+1)
				vertical_product[c] <= vertical_sample[c] * vertical_weight;
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			age                <= 0;
			running            <= 0;
			line_ready_q       <= 0;
			tap_rows_ready_q   <= 0;
			line_visible_q     <= 0;
			epoch_q            <= 0;
			rows_done_q        <= 0;
			rows_valid_q       <= 0;
			sample_y_q         <= 0;
			vertical_weights_q <= 0;
			rd_addr            <= 0;
			read_phase         <= 0;
			column_valid_q     <= 0;
			vertical_weight    <= 0;
			for (int k=0;k<4;k=k+1) begin
				banks_q[k] <= 0;
				for (int c=0;c<3;c=c+1) window[k][c] <= 0;
			end
			for (int c=0;c<3;c=c+1) begin
				vertical_sample[c] <= 0;
				vertical_acc[c]    <= 0;
			end
		end else if (ce_pix) begin
			line_ready_q     <= line_start;
			tap_rows_ready_q <= line_ready_q && !line_start;
			if (line_start) begin
				age            <= 0;
				running        <= 1;
				epoch_q        <= line_epoch;
				sample_y_q     <= sample_y;
				rows_done_q    <= line_epoch ? rows_done_b : rows_done_a;
				line_visible_q <= line_y >= 12'd9 && line_y < active_height + 12'd9;
				rows_valid_q   <= 0;
				read_phase     <= 0;
			end else begin
				if (running) begin
					if (age == 12'(MAX_WIDTH + H_DELAY - 1)) running <= 0;
					else age <= age + 1'b1;
				end
				if (line_ready_q) begin
					vertical_weights_q <= bspline_weights(v_phase, grid_8, shape);
					// Capture the four wrapped row numbers before decoding their banks.
					for (int k=0;k<4;k=k+1) tap_y_q[k] <= coarse_y + 8'(k + 1);
				end
				if (tap_rows_ready_q) begin
					for (int k=0;k<4;k=k+1) begin
						banks_q[k]      <= vfb_layout_pkg::vfb_halo_row_bank(tap_y_q[k]);
						rows_valid_q[k] <= tap_y_q[k] >= 8'd2 && tap_y_q[k] < rows_done_q &&
						                   rows_done_q - tap_y_q[k] <= 8'd5;
					end
				end
				if (fetch) begin
					rd_addr        <= (column < coarse_width + ADDR_W'(5)) ? column : '0;
					column_valid_q <= column < coarse_width + ADDR_W'(5);
					read_phase     <= 3'd1;
				end else if (read_phase != 0) begin
					read_phase <= read_phase + 1'b1;
					case (read_phase)
						3'd2:    begin
							for (int c=0;c<3;c=c+1) vertical_sample[c] <= selected_row[0][c*8+:8];
							vertical_weight <= vertical_weights_q[11:0];
						end
						3'd3:    begin
							for (int c=0;c<3;c=c+1) vertical_sample[c] <= selected_row[1][c*8+:8];
							vertical_weight <= vertical_weights_q[23:12];
						end
						3'd4:    begin
							for (int c=0;c<3;c=c+1) begin
								vertical_sample[c] <= selected_row[2][c*8+:8];
								vertical_acc[c]    <= vertical_product[c];
							end
							vertical_weight <= vertical_weights_q[35:24];
						end
						3'd5:    begin
							for (int c=0;c<3;c=c+1) begin
								vertical_sample[c] <= selected_row[3][c*8+:8];
								vertical_acc[c]    <= vertical_acc[c] + vertical_product[c];
							end
							vertical_weight <= vertical_weights_q[47:36];
						end
						3'd6:    begin
							for (int c=0;c<3;c=c+1)
								vertical_acc[c] <= vertical_acc[c] + vertical_product[c];
						end
						3'd7:    begin
							for (int c=0;c<3;c=c+1) begin
								window[0][c] <= window[1][c];
								window[1][c] <= window[2][c];
								window[2][c] <= window[3][c];
								window[3][c] <= vertical_result[c*14+:14];
							end
						end
						default: begin end
					endcase
				end
			end
		end
	end

	logic [47:0] horizontal_weights_q;
	logic [13:0] horizontal_sample [0:3][0:2];
	logic [25:0] horizontal_product [0:3][0:2];
	logic [25:0] horizontal_pair [0:1][0:2];
	logic [25:0] horizontal_sum [0:2];
	logic [3:0]  valid_pipe;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			horizontal_weights_q <= bspline_weights(h_phase, grid_8, shape);
			for (int c=0;c<3;c=c+1) begin
				for (int k=0;k<4;k=k+1) begin
					horizontal_sample[k][c]  <= window[k][c];
					horizontal_product[k][c] <= horizontal_sample[k][c] *
					                            horizontal_weights_q[k*12+:12];
				end
				horizontal_pair[0][c] <= horizontal_product[0][c] + horizontal_product[1][c];
				horizontal_pair[1][c] <= horizontal_product[2][c] + horizontal_product[3][c];
				horizontal_sum[c]     <= horizontal_pair[0][c] + horizontal_pair[1][c] + 26'd131072;
			end
		end
		if (reset) begin
			valid_pipe <= 0;
			valid      <= 0;
			rgb        <= 0;
		end else if (ce_pix) begin
			valid_pipe <= {valid_pipe[2:0],pixel_valid};
			valid      <= valid_pipe[3];
			for (int c=0;c<3;c=c+1)
				rgb[c*8+:8] <= valid_pipe[3] ? horizontal_sum[c][25:18] : 8'd0;
		end
	end
endmodule

// A module boundary preserves RAM inference for the generated row banks.
module vfb_halo_bspline_row #(
	parameter integer DEPTH  = 189,
	parameter integer ADDR_W =   8
) (
	input  wire               clk, rd_enable, wr_enable,
	input  wire  [ADDR_W-1:0] rd_address, wr_address,
	input  wire  [23:0]       wr_data,
	output logic [23:0]       rd_data
);
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] memory [0:DEPTH-1];
	always_ff @(posedge clk) begin
		if (wr_enable) memory[wr_address] <= wr_data;
		if (rd_enable) rd_data            <= memory[rd_address];
	end
endmodule
`default_nettype wire

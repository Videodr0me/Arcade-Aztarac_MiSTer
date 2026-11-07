// Ordered endpoint/EOF queue and inclusive Bresenham line expansion.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
// Raw coordinates remain signed until display scaling. No CPU wait is inserted.
`default_nettype none

module aztarac_vector_adapter #(
	parameter integer FIFO_ADDR_W = 10
) (
	input  wire                           clk, reset,
	input  wire  signed [11:0]            vector_x0, vector_y0, vector_x1, vector_y1,
	input  wire         [5:0]             vector_color,
	input  wire         [7:0]             vector_intensity,
	input  wire                           vector_valid, frame_done,
	output logic                          vector_ready, overflow,
	input  wire         [11:0]            render_width, render_height,
	input  wire         [1:0]             orientation,
	input  vfb_layout_pkg::vfb_viewport_t viewport,
	input  wire                           pixel_ready,
	output logic        [10:0]            pixel_x, pixel_y,
	output logic        [5:0]             pixel_color,
	output logic        [7:0]             pixel_intensity,
	output logic                          pixel_valid, pixel_is_dot, frame_done_out,
	output logic        [15:0]            frame_tick_clks_out
);
	localparam integer FIFO_DEPTH = 1 << FIFO_ADDR_W;
	typedef struct packed {
		logic               eof, draw;
		logic        [5:0]  color;
		logic        [7:0]  intensity;
		logic        [15:0] frame_ticks;
		logic signed [11:0] x0, y0, x1, y1;
	} vector_t;
	(* ramstyle = "M10K, no_rw_check" *) logic [$bits(vector_t)-1:0] fifo [0:FIFO_DEPTH-1];
	logic [FIFO_ADDR_W-1:0] wr_ptr, rd_ptr;
	logic [FIFO_ADDR_W:0]   used;
	logic                   frame_done_q;
	vector_t                vector_q;
	typedef enum logic [2:0] {IDLE, MULTIPLY, SCALE, SCALE_WAIT, PREPARE, DRAW, EOF_WAIT} state_t;
	state_t state;
	wire    eof_rise     = frame_done && !frame_done_q;
	wire    pop          = state == IDLE && used != 0;
	assign  vector_ready = !reset && used < (FIFO_ADDR_W+1)'(FIFO_DEPTH);
	wire    push         = (vector_valid || eof_rise) && vector_ready;
	// 50 MHz / 8 raw time base; four phase intervals per completed source list.
	logic [2:0]  source_div;
	logic [19:0] frame_period;
	logic        have_frame_period;
	wire  [18:0] rounded_ticks = 19'(({1'b0, frame_period} + 21'd2) >> 2);
	wire  [15:0] frame_ticks   = !have_frame_period ?
	                             16'd39063 :
	                             (rounded_ticks > 65535 ?
	                                  16'hffff :
	                                  (rounded_ticks == 0 ? 16'd1 : rounded_ticks[15:0]));
	always_ff @(posedge clk) begin
		if (reset) begin
			wr_ptr            <= '0;
			rd_ptr            <= '0;
			used              <= '0;
			frame_done_q      <=  0;
			overflow          <=  0;
			source_div        <=  0;
			frame_period      <=  0;
			have_frame_period <=  0;
		end else begin
			frame_done_q <= frame_done;
			source_div   <= source_div + 1'b1;
			if (eof_rise) begin
				frame_period      <= 1;
				have_frame_period <= 1;
			end else if (&source_div && frame_period != 20'hfffff)
				frame_period <= frame_period + 1'b1;
			if (push) begin
				fifo[wr_ptr] <= {eof_rise, vector_valid, vector_color, vector_intensity,
				                 frame_ticks, vector_x0, vector_y0, vector_x1, vector_y1};
				wr_ptr       <= wr_ptr + 1'b1;
			end
			if (pop) rd_ptr <= rd_ptr + 1'b1;
			case ({push, pop})
				2'b10:   used <= used + 1'b1;
				2'b01:   used <= used - 1'b1;
				default: ;
			endcase
			if ((vector_valid || eof_rise) && !vector_ready) overflow <= 1;
		end
	end
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [73:0] geometry_meta = {50'd0,12'd960,12'd720}, geometry_sync = {50'd0,12'd960,12'd720};
	logic [73:0] geometry_prev = {50'd0,12'd960,12'd720}, geometry_stable = {50'd0,12'd960,12'd720};
	always_ff @(posedge clk) begin
		geometry_meta <= {orientation, viewport, render_width, render_height};
		geometry_sync <= geometry_meta;
		geometry_prev <= geometry_sync;
		if (geometry_sync == geometry_prev && geometry_sync[23:12] > 1 && geometry_sync[11:0] > 1)
			geometry_stable <= geometry_sync;
	end
	logic        [11:0]            width_q, height_q;
	logic        [1:0]             orientation_q;
	vfb_layout_pkg::vfb_viewport_t viewport_q;
	wire  signed [31:0]            native_x0   = 32'sd511 + 32'(vector_q.x0);
	wire  signed [31:0]            native_x1   = 32'sd511 + 32'(vector_q.x1);
	wire  signed [31:0]            native_y0   = 32'sd383 - 32'(vector_q.y0);
	wire  signed [31:0]            native_y1   = 32'sd383 - 32'(vector_q.y1);
	wire  signed [31:0]            oriented_x0 = orientation_q == 1 ? native_y0 :
	                                             orientation_q == 2 ? 32'sd767 - native_y0 :
	                                                 native_x0;
	wire  signed [31:0]            oriented_x1 = orientation_q == 1 ? native_y1 :
	                                             orientation_q == 2 ? 32'sd767 - native_y1 :
	                                                 native_x1;
	wire  signed [31:0]            oriented_y0 = orientation_q == 1 ? 32'sd1023 - native_x0 :
	                                             orientation_q == 2 ? native_x0 : native_y0;
	wire  signed [31:0]            oriented_y1 = orientation_q == 1 ? 32'sd1023 - native_x1 :
	                                             orientation_q == 2 ? native_x1 : native_y1;
	// Half-cell coordinates preserve the 1024:768 metric, including pixel centers.
	// Geometry gain is 197/200. Tate fits within the full physical 4:3 output,
	// then zooms by 1024/979 while retaining one raster row around the 240p HUD.
	wire  signed [31:0] gain_x    = orientation_q != 0 ? (height_q == 720 ? 32'sd3546 : 32'sd5319)
	                                                   : (height_q == 720 ? 32'sd591 : 32'sd1773);
	wire  signed [31:0] gain_y    = orientation_q != 0 ?
	                                (height_q == 1080 ?
	                                     32'sd5319 :
	                                     height_q == 720 ?
	                                         32'sd3546 :
	                                         height_q == 480 ? 32'sd2364 : 32'sd1182) :
	                                (height_q == 1080 ? 32'sd1773
	                                                  : height_q == 720 ? 32'sd591 : 32'sd197);
	wire         [14:0] den_x     = orientation_q != 0 ?
	                                (height_q >= 720 ? 15'd4895 : 15'd9790) :
	                                (height_q == 1080 ? 15'd1280
	                                                  : height_q == 720 ? 15'd640 : 15'd2560);
	wire         [14:0] den_y     = orientation_q != 0 ?
	                                15'd4895 :
	                                (height_q == 1080 ?
	                                     15'd1280 :
	                                     height_q == 720 ? 15'd640
	                                                     : height_q == 480 ? 15'd320 : 15'd640);
	wire  signed [31:0] extent_x  = orientation_q == 0 ? 32'sd1024 : 32'sd768;
	wire  signed [31:0] extent_y  = orientation_q == 0 ? 32'sd768 : 32'sd1024;
	wire         [14:0] divisor_x = den_x << 1;
	wire         [14:0] divisor_y = den_y << 1;
	logic signed [31:0] x0_product, y0_product, x1_product, y1_product;
	wire  signed [31:0] x0_scaled, y0_scaled, x1_scaled, y1_scaled;
	wire                scale_done;
	aztarac_vector_divider divide_x0 (
		.clk(clk), .reset(reset), .start(state == SCALE), .numerator(x0_product),
		.divisor(divisor_x), .quotient(x0_scaled), .done(scale_done));
	aztarac_vector_divider divide_y0 (
		.clk(clk), .reset(reset), .start(state == SCALE), .numerator(y0_product),
		.divisor(divisor_y), .quotient(y0_scaled), .done());
	aztarac_vector_divider divide_x1 (
		.clk(clk), .reset(reset), .start(state == SCALE), .numerator(x1_product),
		.divisor(divisor_x), .quotient(x1_scaled), .done());
	aztarac_vector_divider divide_y1 (
		.clk(clk), .reset(reset), .start(state == SCALE), .numerator(y1_product),
		.divisor(divisor_y), .quotient(y1_scaled), .done());
	logic  signed [15:0] x_q, y_q, x_end, y_end;
	logic  signed [16:0] delta_x, delta_y, error_q;
	logic  signed [1:0]  step_x, step_y;
	wire   signed [17:0] error_twice         = {error_q,1'b0};
	wire                 advance_x           = error_twice >= -(18'(delta_y));
	wire                 advance_y           = error_twice <= 18'(delta_x);
	wire   signed [16:0] error_next          = error_q - (advance_x ? delta_y : 17'sd0) +
	                                           (advance_y ? delta_x : 17'sd0);
	wire                 visible             =
	    vector_q.intensity != 0
	    && vector_q.color != 0
	    && !x_q[15]
	    && !y_q[15]
	    && x_q < $signed({4'd0,width_q})
	    && y_q < $signed({4'd0,height_q});
	assign               pixel_x             = x_q[10:0];
	assign               pixel_y             = y_q[10:0];
	assign               pixel_color         = vector_q.color;
	assign               pixel_intensity     = vector_q.intensity;
	assign               pixel_is_dot        = vector_q.x0 == vector_q.x1 &&
	                                           vector_q.y0 == vector_q.y1;
	assign               pixel_valid         = !reset && state == DRAW && visible && pixel_ready;
	assign               frame_done_out      = !reset && state == EOF_WAIT && pixel_ready;
	assign               frame_tick_clks_out = vector_q.frame_ticks;
	always_ff @(posedge clk) begin
		if (reset) begin
			state         <= IDLE;
			vector_q      <=  '0;
			width_q       <= 960;
			height_q      <= 720;
			orientation_q <=   0;
			viewport_q    <= {12'd0,12'd0,12'd960,12'd720};
			x0_product    <= 0;
			y0_product    <= 0;
			x1_product    <= 0;
			y1_product    <= 0;
			x_q           <= 0;
			y_q           <= 0;
			x_end         <= 0;
			y_end         <= 0;
			delta_x       <= 0;
			delta_y       <= 0;
			error_q       <= 0;
			step_x        <= 1;
			step_y        <= 1;
		end else case (state)
			IDLE:       if (pop) begin
				vector_q      <= fifo[rd_ptr];
				orientation_q <= geometry_stable[73:72];
				viewport_q    <= geometry_stable[47:36] > 1 && geometry_stable[35:24] > 1 ?
				                 geometry_stable[71:24] :
				                 {24'd0,geometry_stable[23:0]};
				// Only the full framebuffer clips pixels after the geometry transform.
				width_q  <= geometry_stable[23:12];
				height_q <= geometry_stable[11:0];
				state    <= MULTIPLY;
			end
			MULTIPLY:   begin
				if (!vector_q.draw) state <= EOF_WAIT;
				else if (vector_q.color == 0 || vector_q.intensity == 0)
					state <= vector_q.eof ? EOF_WAIT : IDLE;
				else begin
					x0_product <= (oriented_x0 * 32'sd2 + 32'sd1 - extent_x) * gain_x +
					              $signed({1'b0,width_q}) * $signed({1'b0,den_x});
					x1_product <= (oriented_x1 * 32'sd2 + 32'sd1 - extent_x) * gain_x +
					              $signed({1'b0,width_q}) * $signed({1'b0,den_x});
					y0_product <= (oriented_y0 * 32'sd2 + 32'sd1 - extent_y) * gain_y +
					              $signed({1'b0,height_q}) * $signed({1'b0,den_y});
					y1_product <= (oriented_y1 * 32'sd2 + 32'sd1 - extent_y) * gain_y +
					              $signed({1'b0,height_q}) * $signed({1'b0,den_y});
					state      <= SCALE;
				end
			end
			SCALE:      state <= SCALE_WAIT;
			SCALE_WAIT: if (scale_done) begin
				// Floor selects the containing pixel; negative offscreen cells stay outside.
				x_q   <= x0_scaled[15:0] + {4'd0,viewport_q.x};
				x_end <= x1_scaled[15:0] + {4'd0,viewport_q.x};
				y_q   <= y0_scaled[15:0] + {4'd0,viewport_q.y};
				y_end <= y1_scaled[15:0] + {4'd0,viewport_q.y};
				state <= PREPARE;
			end
			PREPARE:    begin
				delta_x <= x_end >= x_q ? 17'(x_end) - 17'(x_q) : 17'(x_q) - 17'(x_end);
				delta_y <= y_end >= y_q ? 17'(y_end) - 17'(y_q) : 17'(y_q) - 17'(y_end);
				error_q <= (x_end >= x_q ? 17'(x_end) - 17'(x_q) : 17'(x_q) - 17'(x_end)) -
				           (y_end >= y_q ? 17'(y_end) - 17'(y_q) : 17'(y_q) - 17'(y_end));
				step_x  <= x_end >= x_q ? 2'sd1 : -2'sd1;
				step_y  <= y_end >= y_q ? 2'sd1 : -2'sd1;
				// Reject wholly offscreen lines after scaling, without moving endpoints.
				if ((x_q < 0 && x_end < 0) || (y_q < 0 && y_end < 0) ||
					(x_q >= $signed({4'd0,width_q}) && x_end >= $signed({4'd0,width_q})) ||
					(y_q >= $signed({4'd0,height_q}) && y_end >= $signed({4'd0,height_q})))
					state <= vector_q.eof ? EOF_WAIT : IDLE;
				else state <= DRAW;
			end
			DRAW:       if (!visible || pixel_ready) begin
				if (x_q == x_end && y_q == y_end) state <= vector_q.eof ? EOF_WAIT : IDLE;
				else begin
					if (advance_x) x_q <= x_q + 16'(step_x);
					if (advance_y) y_q <= y_q + 16'(step_y);
					error_q <= error_next;
				end
			end
			EOF_WAIT:   if (pixel_ready) state <= IDLE;
			default:    state                  <= IDLE;
		endcase
	end
endmodule

`default_nettype wire

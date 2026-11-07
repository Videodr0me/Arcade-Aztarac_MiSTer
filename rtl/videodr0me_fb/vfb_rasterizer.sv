// ============================================================================
// Vector pixel rasterizer.
// Written 2026 by Videodr0me
// Transfers source pixels to the framebuffer clock and adds dot or diagonal
// fill pixels where selected.
// ============================================================================

`default_nettype none

module vfb_rasterizer #(
	parameter TILE_SIZE   =  8,
	parameter FIFO_ADDR_W = 10
) (
	input  wire  clk_sys,
	input  wire  clk_source,
	input  wire  reset,

	// Vector input
	input  wire  [10:0] X_VECTOR,
	input  wire  [10:0] Y_VECTOR,
	input  wire  [5:0]  COLOR,   // RRGGBB, 2 bits per gun
	input  wire  [7:0]  INTENSITY,
	output logic        SOURCE_READY,
	input  wire         IS_DOT,
	input  wire         BEAM_ON,
	input  wire         FRAME_DONE,
	input  wire  [2:0]  DOT_MODE,
	input  wire  [11:0] FB_WIDTH,
	input  wire  [11:0] FB_HEIGHT,

	// Tile cache output
	output logic        pixel_valid,
	input  wire         pixel_ready,
	output logic [15:0] pixel_tile_id,
	output logic [5:0]  pixel_offset,
	output logic [15:0] pixel_data,
	input  wire  [2:0]  draw_idx,         // Source-domain pixel draw-time phase
	input  wire  [15:0] frame_tick_clks,  // Source clocks per draw-index phase
	input  wire  [15:0] completed_frame_tick_clks,

	output logic        eof_token,
	output logic [15:0] eof_completed_frame_tick_clks,
	output logic        fifo_full_led,
	output logic        fifo_empty
);
	import vfb_layout_pkg::*;
	import vfb_control_pkg::*;

	localparam FIFO_DEPTH = 1 << FIFO_ADDR_W;
	localparam FIFO_PTR_W = FIFO_ADDR_W + 1;

	logic [2:0]  dot_mode_q  = DOT_2X;
	logic [11:0] fb_width_q  = 12'd720;
	logic [11:0] fb_height_q = 12'd480;
	always_ff @(posedge clk_sys) begin
		dot_mode_q  <= DOT_MODE;
		fb_width_q  <= FB_WIDTH;
		fb_height_q <= FB_HEIGHT;
	end

	function [FIFO_PTR_W-1:0] b2g(input [FIFO_PTR_W-1:0] b);
		b2g = b ^ (b >> 1);
	endfunction

	function [FIFO_PTR_W-1:0] g2b(input [FIFO_PTR_W-1:0] g);
		logic [FIFO_PTR_W-1:0] b;
		begin
			b[FIFO_PTR_W-1] = g[FIFO_PTR_W-1];
			for (int i=FIFO_PTR_W-2; i>=0; i=i-1)
				b[i] = b[i+1] ^ g[i];
			g2b = b;
		end
	endfunction

	// The FIFO lets vector drawing continue while the framebuffer is busy.
	(* ramstyle = "M10K" *) logic [39:0] fifo_mem [0:FIFO_DEPTH-1];

	logic [FIFO_PTR_W-1:0] wr_ptr   = 0;
	logic [FIFO_PTR_W-1:0] wr_ptr_g = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr   = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr_g = 0;

	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] wr_ptr_g_sync1 = 0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] wr_ptr_g_sync2 = 0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] rd_ptr_g_sync1 = 0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] rd_ptr_g_sync2 = 0;

	// Source-clock side
	logic last_frame_done = 0;

	wire push_eof = (FRAME_DONE && !last_frame_done);
	wire push_pix = BEAM_ON;
	wire fifo_we  = push_eof || push_pix;

	// EOF metadata and vector pixels share one fixed-width FIFO word.
	wire [39:0] fifo_din = push_eof ? {
		2'd0, 1'b1, 5'd0, completed_frame_tick_clks, frame_tick_clks
	} : {
		draw_idx[1:0],  // 39:38, retained through stalls and expansion
		1'b0,           // 37
		IS_DOT,         // 36
		COLOR,          // 35:30 = RRGGBB
		Y_VECTOR,       // 29:19
		X_VECTOR,       // 18:8
		INTENSITY       // 7:0 native intensity
	};

	wire  [FIFO_PTR_W-1:0] wr_ptr_next     = wr_ptr + 1'b1;
	wire  [FIFO_PTR_W-1:0] wr_ptr_g_next   = b2g(wr_ptr_next);
	wire                   fifo_full       = (wr_ptr_g_next ==
	                                          {~rd_ptr_g_sync2[FIFO_PTR_W-1:FIFO_PTR_W-2],
	                                           rd_ptr_g_sync2[FIFO_PTR_W-3:0]});
	logic [1:0]            rst_source_sync = 2'b11;
	always_ff @(posedge clk_source)
		rst_source_sync <= {rst_source_sync[0], reset};
	wire   rst_source   = rst_source_sync[1];
	assign SOURCE_READY = !rst_source && !fifo_full;

	// Synchronize the Gray-coded read pointer back to the write domain so a
	// prolonged DDR/cache stall cannot silently overwrite unread entries.
	always_ff @(posedge clk_source) begin
		if (rst_source) begin
			rd_ptr_g_sync1 <= 0;
			rd_ptr_g_sync2 <= 0;
		end else begin
			rd_ptr_g_sync1 <= rd_ptr_g;
			rd_ptr_g_sync2 <= rd_ptr_g_sync1;
		end
	end

	always_ff @(posedge clk_source) begin
		last_frame_done <= FRAME_DONE;

		if (rst_source) begin
			wr_ptr   <= 0;
			wr_ptr_g <= 0;
		end else if (fifo_we) begin
			if (!fifo_full) begin
				fifo_mem[wr_ptr[FIFO_ADDR_W-1:0]] <= fifo_din;
				wr_ptr                            <= wr_ptr_next;
				wr_ptr_g                          <= wr_ptr_g_next;
			end
		end
	end

	// Framebuffer-clock side
	always_ff @(posedge clk_sys) begin
		wr_ptr_g_sync1 <= wr_ptr_g;
		wr_ptr_g_sync2 <= wr_ptr_g_sync1;
	end
	assign fifo_empty = (rd_ptr_g == wr_ptr_g_sync2);

	// FIFO high-water LED, held for about 75 ms.
	wire [FIFO_PTR_W-1:0] wr_ptr_bin = g2b(wr_ptr_g_sync2);
	wire [FIFO_PTR_W-1:0] fifo_used  = wr_ptr_bin - rd_ptr;

	logic        fifo_full_flag_q = 0;
	logic [23:0] led_timer        = 0;
	always_ff @(posedge clk_sys) begin
		fifo_full_flag_q <= (fifo_used > FIFO_PTR_W'(128));
		if (fifo_full_flag_q) led_timer <= 24'd9349794;
		else if (led_timer != 0) led_timer <= led_timer - 1'b1;
	end
	assign fifo_full_led = (led_timer != 0);

	logic [1:0] rst_sys_sync = 2'b11;
	always_ff @(posedge clk_sys) rst_sys_sync <= {rst_sys_sync[0], reset};
	wire rst_sys = rst_sys_sync[1];

	// Flow: FIFO -> input register -> expansion stage -> tile cache.
	//
	// The input register holds one FIFO entry. The expansion stage emits the
	// source pixel, then any diagonal fill or dot-scale pixels.
	//   B_IDLE      - accept and emit a source pixel
	//   B_CHECK_SUB - choose and emit a diagonal fill pixel
	//   B_DOT_SUB   - emit dot-scale pixels

	// Input register
	logic [39:0] a_data;
	logic        a_valid = 0;
	wire         a_ready;

	wire a_fifo_read = !fifo_empty && (!a_valid || a_ready);

	always_ff @(posedge clk_sys) begin
		if (rst_sys) begin
			a_valid  <= 0;
			rd_ptr   <= 0;
			rd_ptr_g <= 0;
		end else begin
			if (a_ready && a_valid) a_valid <= 0;
			if (a_fifo_read) begin
				a_data   <= fifo_mem[rd_ptr[FIFO_ADDR_W-1:0]];
				rd_ptr   <= rd_ptr + 1'b1;
				rd_ptr_g <= b2g(rd_ptr + 1'b1);
				a_valid  <= 1;
			end
		end
	end

	wire [10:0] a_x      = a_data[18:8];
	wire [10:0] a_y      = a_data[29:19];
	wire [5:0]  a_c      = a_data[35:30];
	wire [7:0]  a_z      = a_data[7:0];
	wire        a_is_dot = a_data[36];
	wire        a_eof    = a_data[37];
	wire [2:0]  a_dot    = dot_mode_q;
	wire [1:0]  a_phase  = a_data[39:38];

	// Expansion state
	typedef enum logic [1:0] {
		B_IDLE,
		B_CHECK_SUB,
		B_DOT_SUB
	} b_state_t;

	b_state_t b_state = B_IDLE;

	logic [10:0] s2_out_x;
	logic [7:0]  s2_out_z;
	logic [7:0]  dot_base_z, fill_intensity;
	logic [10:0] s2_out_y;
	logic [5:0]  s2_out_c;
	logic [1:0]  s2_out_phase;
	logic        s2_out_valid                     = 0;
	logic [15:0] s2_eof_frame_tick_clks           = 0;
	logic [15:0] s2_eof_completed_frame_tick_clks = 0;

	wire   b_output_free = pixel_ready || !s2_out_valid;
	assign pixel_valid   = s2_out_valid;

	logic [5:0] fill_colour;
	logic       fill_prev_horizontal;
	logic       fill_prev_vertical;

	// Retain two source positions for traversal-independent corner selection.
	logic [10:0] hist_x [2];
	logic [10:0] hist_y [2];
	logic [1:0]  hist_count = 0;

	logic [10:0] read_last_x = 0;
	logic [10:0] read_last_y = 0;

	// Dot-scale state
	logic [2:0]  dot_idx;
	logic [2:0]  dot_last_idx;
	logic [2:0]  dot_mode;
	logic [5:0]  dot_base_c;
	logic [10:0] dot_x, dot_y;
	logic [11:0] dot_candidate_x;
	logic [11:0] dot_candidate_y;
	logic        dot_candidate_valid;

	always_comb begin
		dot_candidate_x = {1'b0, dot_x};
		dot_candidate_y = {1'b0, dot_y};

		case (dot_mode)
		DOT_2X: begin
			case (dot_idx)
				3'd0:    dot_candidate_x = {1'b0, dot_x} + 12'd1;
				3'd1:    dot_candidate_y = {1'b0, dot_y} + 12'd1;
				default: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
			endcase
		end

		DOT_25X: begin
			case (dot_idx)
				3'd0:    dot_candidate_x = {1'b0, dot_x} + 12'd1;
				3'd1:    dot_candidate_x = {1'b0, dot_x} + 12'd2;
				3'd2:    dot_candidate_y = {1'b0, dot_y} + 12'd1;
				3'd3:    begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
				default: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd2;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
			endcase
		end

		DOT_3X: begin
			case (dot_idx)
				3'd0:    begin
					dot_candidate_x = {1'b0, dot_x} - 12'd1;
					dot_candidate_y = {1'b0, dot_y} - 12'd1;
				end
				3'd1:    dot_candidate_y = {1'b0, dot_y} - 12'd1;
				3'd2:    begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} - 12'd1;
				end
				3'd3:    dot_candidate_x = {1'b0, dot_x} - 12'd1;
				3'd4:    dot_candidate_x = {1'b0, dot_x} + 12'd1;
				3'd5:    begin
					dot_candidate_x = {1'b0, dot_x} - 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
				3'd6:    dot_candidate_y = {1'b0, dot_y} + 12'd1;
				default: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
			endcase
		end

		default: begin
			dot_candidate_x = {1'b0, dot_x};
			dot_candidate_y = {1'b0, dot_y};
		end
		endcase
	end

	assign dot_candidate_valid = (dot_candidate_x < fb_width_q) && (dot_candidate_y < fb_height_q);

	function automatic logic unit_step(input logic [10:0] a, b);
		// Extend the addition so 2047 and zero cannot become neighbors.
		unit_step = ({1'b0, a} + 12'd1 == {1'b0, b}) ||
		            ({1'b0, b} + 12'd1 == {1'b0, a});
	endfunction

	// Only equality and one-pixel steps are needed for diagonal-fill geometry.
	wire        step_x_equal   = a_x == read_last_x;
	wire        step_y_equal   = a_y == read_last_y;
	wire        step_x_unit    = unit_step(a_x, read_last_x);
	wire        step_y_unit    = unit_step(a_y, read_last_y);
	wire        step_is_diag   = (hist_count != 0) && step_x_unit && step_y_unit;
	wire        primary_is_dot = a_is_dot && (a_dot < DOT_1X);
	wire        is_neighbor    = (step_x_equal || step_x_unit) && (step_y_equal || step_y_unit);

	wire        hist_is_horizontal = (hist_count >= 2'd2) &&
	                                 unit_step(hist_x[0], hist_x[1]) &&
	                                 (hist_y[0] == hist_y[1]);
	wire        hist_is_vertical   = (hist_count >= 2'd2) &&
	                                 (hist_x[0] == hist_x[1]) &&
	                                 unit_step(hist_y[0], hist_y[1]);
	wire        next_is_horizontal = !a_eof && step_x_unit && step_y_equal;
	wire        next_is_vertical   = !a_eof && step_x_equal && step_y_unit;
	wire [1:0]  x_first_cost       = {1'b0, fill_prev_horizontal} + {1'b0, next_is_vertical};
	wire [1:0]  y_first_cost       = {1'b0, fill_prev_vertical} + {1'b0, next_is_horizontal};
	wire        choose_x_first     = (x_first_cost < y_first_cost) ||
	                                 ((x_first_cost == y_first_cost) && (hist_x[0] > hist_x[1]));

	assign a_ready = a_valid && b_output_free && (b_state == B_IDLE);

	always_ff @(posedge clk_sys) begin
		if (rst_sys) begin
			s2_out_valid                     <=     0;
			eof_token                        <=     0;
			s2_eof_frame_tick_clks           <= 16'd0;
			s2_eof_completed_frame_tick_clks <= 16'd0;
			b_state                          <= B_IDLE;
			hist_count                       <= 0;
		end else begin
			if (pixel_ready) begin
				s2_out_valid <= 0;
				eof_token    <= 0;
			end

			case (b_state)
			B_IDLE: begin
				if (a_valid && b_output_free) begin
					if (a_eof) begin
						// The next frame starts a new stroke history.
						hist_count                       <= 0;
						eof_token                        <= 1;
						s2_out_valid                     <= 1;
						s2_eof_frame_tick_clks           <= a_data[15:0];
						s2_eof_completed_frame_tick_clks <= a_data[31:16];
					end else begin
						s2_out_x       <= a_x;
						s2_out_y       <= a_y;
						s2_out_c       <= a_c;
						s2_out_z       <= a_z;
						s2_out_phase   <= a_phase;
						s2_out_valid   <= 1;
						fill_colour    <= a_c;
						fill_intensity <= a_z;

						hist_x[1]  <= hist_x[0];
						hist_y[1]  <= hist_y[0];
						hist_x[0]  <= a_x;
						hist_y[0]  <= a_y;
						hist_count <= is_neighbor ? ((hist_count < 2'd2) ? hist_count + 2'd1 : 2'd2)
						                          : 2'd1;

						if (primary_is_dot) begin
							b_state      <= B_DOT_SUB;
							dot_mode     <= a_dot;
							dot_idx      <= 3'd0;
							dot_last_idx <= (a_dot == DOT_2X) ? 3'd2 :
							                (a_dot == DOT_25X) ? 3'd4 : 3'd7;
							dot_base_c   <= a_c;
							dot_base_z   <= a_z;
							dot_x        <= a_x;
							dot_y        <= a_y;
						end else if (step_is_diag) begin
							fill_prev_horizontal <= hist_is_horizontal;
							fill_prev_vertical   <= hist_is_vertical;
							b_state              <= B_CHECK_SUB;
						end

						read_last_x <= a_x;
						read_last_y <= a_y;
					end
				end
			end

			// Score both corners against the neighboring steps. The greater-X
			// tie break makes reversed traversal choose the same physical pixel.
			B_CHECK_SUB: begin
				if (a_valid && b_output_free) begin
					if (choose_x_first) begin
						s2_out_x <= hist_x[0];
						s2_out_y <= hist_y[1];
					end else begin
						s2_out_x <= hist_x[1];
						s2_out_y <= hist_y[0];
					end
					s2_out_c     <= fill_colour;
					s2_out_z     <= fill_intensity;
					s2_out_valid <= 1;
					b_state      <= B_IDLE;
				end
			end

			B_DOT_SUB: begin
				if (b_output_free) begin
					// Bounds qualify the pixel, not the idle payload registers.
					s2_out_x     <= dot_candidate_x[10:0];
					s2_out_y     <= dot_candidate_y[10:0];
					s2_out_c     <= dot_base_c;
					s2_out_z     <= dot_base_z;
					s2_out_valid <= dot_candidate_valid;

					if (dot_idx == dot_last_idx) begin
						b_state <= B_IDLE;
					end else begin
						dot_idx <= dot_idx + 3'd1;
					end
				end
			end
			endcase
		end
	end

	assign pixel_tile_id                 = {s2_out_y[10:3], s2_out_x[10:3]};
	assign pixel_offset                  = {s2_out_y[2:0],  s2_out_x[2:0]};
	assign pixel_data                    = eof_token ?
	                                       s2_eof_frame_tick_clks :
	                                       vfb_pack_raw_pixel(s2_out_c, {1'b0, s2_out_phase},
	                                                          s2_out_z);
	assign eof_completed_frame_tick_clks = s2_eof_completed_frame_tick_clks;

endmodule

`default_nettype wire

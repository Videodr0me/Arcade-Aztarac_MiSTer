// ============================================================================
// Line-local RLE encoder for canonical Aztarac pixels.
// Written 2026 by Videodr0me
//
// Colored runs carry RRGGBB, eight-bit intensity, and a count of one to four.
// Color zero selects a black or repeat token with a count of one to 256. The
// previous sample resets at each line boundary, so every line is independent.
// ============================================================================

`default_nettype none

module vfb_rle_encoder (
	input  wire         clk_sys,
	input  wire         reset,

	input  wire         pixel_valid,
	input  wire  [13:0] canonical_in,
	input  wire         line_end,

	output logic        token_valid,
	input  wire         token_ready,
	output logic [15:0] token_data,
	output logic        token_eol,

	output logic overflow
);

	localparam integer RUN_FIFO_DEPTH = 16;
	localparam integer RUN_FIFO_AW    = $clog2(RUN_FIFO_DEPTH);
	localparam integer RUN_ENTRY_W    = 1 + 14 + 13;

	typedef enum logic [1:0] {
		EMIT_IDLE,
		EMIT_BLACK,
		EMIT_COLOR,
		EMIT_REPEAT
	} emit_state_t;

	function automatic logic [13:0] canonicalize(
		input logic [13:0] sample
	);
		begin
			canonicalize = ((sample[13:8] == 0) || (sample[7:0] == 0)) ? 14'd0 : sample;
		end
	endfunction

	function automatic logic [7:0] count_m1_256(
		input logic [12:0] count
	);
		count_m1_256 = (count >= 13'd256) ? 8'hff : count[7:0] - 8'd1;
	endfunction

	function automatic logic [1:0] count_m1_4(
		input logic [3:0] count
	);
		count_m1_4 = (count >= 4'd4) ? 2'd3 : count[1:0] - 2'd1;
	endfunction

	logic        input_valid;
	logic [13:0] input_sample;
	logic        input_line_end;
	logic        run_valid;
	logic [13:0] run_sample;
	logic [12:0] run_count;

	(* ramstyle = "logic" *) logic [RUN_ENTRY_W-1:0]
		run_fifo [0:RUN_FIFO_DEPTH-1];
	logic [RUN_FIFO_AW:0]   run_fifo_used;
	logic [RUN_FIFO_AW-1:0] run_fifo_rd_ptr;
	logic [RUN_FIFO_AW-1:0] run_fifo_wr_ptr;
	logic                   pending_valid;
	logic [RUN_ENTRY_W-1:0] pending_entry;
	logic                   prefetch_valid;
	logic [RUN_ENTRY_W-1:0] prefetch_entry;

	emit_state_t emit_state;
	logic [13:0] emit_sample;
	logic [12:0] emit_remaining;
	logic        emit_eol;

	wire                   run_fifo_empty   = (run_fifo_used == 0);
	wire                   run_fifo_full    = (run_fifo_used == RUN_FIFO_DEPTH);
	wire [RUN_ENTRY_W-1:0] run_fifo_head    = run_fifo[run_fifo_rd_ptr];
	wire                   emit_can_write   = !token_valid || token_ready;
	wire                   emit_busy        = (emit_state != EMIT_IDLE);
	wire                   emit_finishes    = emit_can_write &&
	                                          emit_busy &&
	                                          (((emit_state == EMIT_COLOR) &&
	                                            (emit_remaining <= 13'd4)) ||
	                                           ((emit_state != EMIT_COLOR) &&
	                                            (emit_remaining <= 13'd256)));
	wire                   emit_available   = !emit_busy || emit_finishes;
	wire                   run_fifo_pop     = !prefetch_valid && !run_fifo_empty;
	wire                   start_prefetch   = emit_available && prefetch_valid;
	wire                   start_fifo_head  = emit_available && !prefetch_valid && run_fifo_pop;
	wire                   start_emit       = start_prefetch || start_fifo_head;
	wire [RUN_ENTRY_W-1:0] start_entry      = prefetch_valid ? prefetch_entry : run_fifo_head;
	wire                   start_eol        = start_entry[27];
	wire [12:0]            start_count      = start_entry[26:14];
	wire [13:0]            start_sample     = start_entry[13:0];
	wire [3:0]             emit_color_count = (emit_remaining >= 13'd4) ?
	                                          4'd4 :
	                                          {1'b0, emit_remaining[2:0]};

	wire                   run_fifo_can_push  = !run_fifo_full || run_fifo_pop;
	wire                   run_fifo_push      = pending_valid && run_fifo_can_push;
	wire                   pixel_extends_run  = input_valid && run_valid &&
	                                            (input_sample == run_sample) &&
	                                            (run_count < 13'd4096);
	wire                   pixel_finishes_run = input_valid && run_valid && !pixel_extends_run;
	wire                   line_finishes_run  = input_line_end && run_valid;
	wire                   run_close_request  = pixel_finishes_run || line_finishes_run;
	wire                   pending_ready      = !pending_valid || run_fifo_can_push;
	wire                   run_close_accept   = run_close_request && pending_ready;
	wire [RUN_ENTRY_W-1:0] completed_run      = {line_finishes_run, run_count, run_sample};

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			token_valid     <=  1'b0;
			token_data      <= 16'd0;
			token_eol       <=  1'b0;
			input_valid     <=  1'b0;
			input_sample    <= 14'd0;
			input_line_end  <=  1'b0;
			run_valid       <=  1'b0;
			run_sample      <= 14'd0;
			run_count       <= 13'd0;
			run_fifo_used   <=    '0;
			run_fifo_rd_ptr <=    '0;
			run_fifo_wr_ptr <=    '0;
			pending_valid   <=  1'b0;
			pending_entry   <=    '0;
			prefetch_valid  <=  1'b0;
			prefetch_entry  <=    '0;
			emit_state      <= EMIT_IDLE;
			emit_sample     <= 14'd0;
			emit_remaining  <= 13'd0;
			emit_eol        <=  1'b0;
			overflow        <=  1'b0;
		end else begin
			input_valid    <= pixel_valid;
			input_sample   <= canonicalize(canonical_in);
			input_line_end <= line_end;

			if (token_valid && token_ready) token_valid <= 1'b0;

			if (emit_busy && emit_can_write) begin
				token_valid <= 1'b1;
				case (emit_state)
					EMIT_BLACK: begin
						token_data <= {6'd0, 2'b00, count_m1_256(emit_remaining)};
						if (emit_remaining > 13'd256) begin
							emit_remaining <= emit_remaining - 13'd256;
							token_eol      <= 1'b0;
						end else begin
							emit_state <= EMIT_IDLE;
							token_eol  <= emit_eol;
						end
					end

					EMIT_COLOR: begin
						token_data <= {emit_sample[13:8], emit_sample[7:0],
						               count_m1_4(emit_color_count)};
						if (emit_remaining > 13'd4) begin
							emit_remaining <= emit_remaining - 13'd4;
							emit_state     <= EMIT_REPEAT;
							token_eol      <= 1'b0;
						end else begin
							emit_state <= EMIT_IDLE;
							token_eol  <= emit_eol;
						end
					end

					EMIT_REPEAT: begin
						token_data <= {6'd0, 2'b01, count_m1_256(emit_remaining)};
						if (emit_remaining > 13'd256) begin
							emit_remaining <= emit_remaining - 13'd256;
							token_eol      <= 1'b0;
						end else begin
							emit_state <= EMIT_IDLE;
							token_eol  <= emit_eol;
						end
					end

					default: begin
						token_valid <=  1'b0;
						token_data  <= 16'd0;
						token_eol   <=  1'b0;
						emit_state  <= EMIT_IDLE;
					end
				endcase
			end

			if (start_emit) begin
				emit_sample    <= start_sample;
				emit_remaining <= start_count;
				emit_eol       <= start_eol;
				emit_state     <= (start_sample == 0) ? EMIT_BLACK : EMIT_COLOR;
			end

			if (start_prefetch) prefetch_valid <= 1'b0;
			if (run_fifo_pop) begin
				if (!start_fifo_head) begin
					prefetch_entry <= run_fifo_head;
					prefetch_valid <= 1'b1;
				end
				run_fifo_rd_ptr <= run_fifo_rd_ptr + 1'b1;
			end
			if (run_fifo_push) begin
				run_fifo[run_fifo_wr_ptr] <= pending_entry;
				run_fifo_wr_ptr           <= run_fifo_wr_ptr + 1'b1;
			end
			case ({run_fifo_push, run_fifo_pop})
				2'b10:   run_fifo_used <= run_fifo_used + 1'b1;
				2'b01:   run_fifo_used <= run_fifo_used - 1'b1;
				default: run_fifo_used <= run_fifo_used;
			endcase

			if (run_fifo_push) pending_valid <= 1'b0;
			if (run_close_request) begin
				if (pending_ready) begin
					pending_entry <= completed_run;
					pending_valid <= 1'b1;
				end else begin
					overflow <= 1'b1;
				end
			end

			if (line_finishes_run && run_close_accept) begin
				run_valid <=  1'b0;
				run_count <= 13'd0;
			end

			if (input_valid) begin
				if (!run_valid) begin
					run_valid  <= 1'b1;
					run_sample <= input_sample;
					run_count  <= 13'd1;
				end else if (pixel_extends_run) begin
					run_count <= run_count + 1'b1;
				end else begin
					run_valid  <= 1'b1;
					run_sample <= input_sample;
					run_count  <= 13'd1;
				end
			end
		end
	end

endmodule

`default_nettype wire

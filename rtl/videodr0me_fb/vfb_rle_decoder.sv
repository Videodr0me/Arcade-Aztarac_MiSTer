// ============================================================================
// Line-local RLE decoder for canonical Aztarac pixels.
// Written 2026 by Videodr0me
//
// A small run FIFO prefetches boundaries so decoding sustains one pixel per
// advance while input data is available.
// ============================================================================

`default_nettype none

module vfb_rle_decoder (
	input  wire         clk_sys,
	input  wire         reset,

	input  wire         token_valid,
	output logic        token_ready,
	input  wire  [15:0] token_data,
	input  wire         token_eol,

	input  wire         advance,
	output logic [13:0] canonical_out,
	output logic        pixel_valid,
	output logic        line_done,
	output logic        underflow
);

	localparam integer RUN_FIFO_DEPTH = 16;
	localparam integer RUN_FIFO_AW    = $clog2(RUN_FIFO_DEPTH);

	logic [13:0] previous_sample;
	(* ramstyle = "logic" *) logic [13:0]
		fifo_sample [0:RUN_FIFO_DEPTH-1];
	logic [8:0]             fifo_count [0:RUN_FIFO_DEPTH-1];
	logic                   fifo_eol [0:RUN_FIFO_DEPTH-1];
	logic [RUN_FIFO_AW-1:0] fifo_wr_ptr;
	logic [RUN_FIFO_AW-1:0] fifo_rd_ptr;
	logic [RUN_FIFO_AW:0]   fifo_used;
	logic [13:0]            run_sample;
	logic [8:0]             run_remaining;
	logic                   run_eol;

	wire fifo_full    = (fifo_used == RUN_FIFO_DEPTH);
	wire fifo_empty   = (fifo_used == 0);
	wire consume_run  = advance && (run_remaining != 0);
	wire consume_fifo = advance && (run_remaining == 0) && !fifo_empty;
	wire fifo_pop     = consume_fifo;

	logic        token_supported;
	logic [13:0] push_sample;
	logic [8:0]  push_count;
	always_comb begin
		token_supported =  1'b1;
		push_sample     = 14'd0;
		push_count      =  9'd0;

		if (token_data[15:10] != 0) begin
			push_sample = {token_data[15:10], token_data[9:2]};
			push_count  = {7'd0, token_data[1:0]} + 1'b1;
			if (token_data[9:2] == 0) token_supported = 1'b0;
		end else begin
			push_count = {1'b0, token_data[7:0]} + 1'b1;
			case (token_data[9:8])
				2'b00:   push_sample     = 14'd0;
				2'b01:   push_sample     = previous_sample;
				default: token_supported = 1'b0;
			endcase
		end
	end

	// Hold the source token while full; intake resumes after a run frees a slot.
	assign token_ready = !fifo_full;
	wire   fifo_push   = token_valid && token_ready && token_supported;

	always_comb begin
		if (run_remaining != 0)
			canonical_out = run_sample;
		else if (!fifo_empty)
			canonical_out = fifo_sample[fifo_rd_ptr];
		else
			canonical_out = 14'd0;
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			previous_sample <= 14'd0;
			fifo_wr_ptr     <=    '0;
			fifo_rd_ptr     <=    '0;
			fifo_used       <=    '0;
			run_sample      <= 14'd0;
			run_remaining   <=  9'd0;
			run_eol         <=  1'b0;
			pixel_valid     <=  1'b0;
			line_done       <=  1'b0;
			underflow       <=  1'b0;
		end else begin
			pixel_valid <= 1'b0;
			line_done   <= 1'b0;

			if (token_valid && token_ready) begin
				if (token_supported) begin
					fifo_sample[fifo_wr_ptr] <= push_sample;
					fifo_count[fifo_wr_ptr]  <= push_count;
					fifo_eol[fifo_wr_ptr]    <= token_eol;
					fifo_wr_ptr              <= fifo_wr_ptr + 1'b1;
					if (token_data[15:10] != 0)
						previous_sample <= push_sample;
					else if (token_data[9:8] == 2'b00)
						previous_sample <= 14'd0;
					if (token_eol) previous_sample <= 14'd0;
				end else begin
					underflow <= 1'b1;
				end
			end

			if (consume_run) begin
				pixel_valid <= 1'b1;
				if (run_remaining == 9'd1) begin
					run_remaining <= 9'd0;
					if (run_eol) line_done <= 1'b1;
				end else begin
					run_remaining <= run_remaining - 1'b1;
				end
			end else if (consume_fifo) begin
				pixel_valid <= 1'b1;
				run_sample  <= fifo_sample[fifo_rd_ptr];
				run_eol     <= fifo_eol[fifo_rd_ptr];
				if (fifo_count[fifo_rd_ptr] == 9'd1) begin
					run_remaining <= 9'd0;
					if (fifo_eol[fifo_rd_ptr]) line_done <= 1'b1;
				end else begin
					run_remaining <= fifo_count[fifo_rd_ptr] - 1'b1;
				end
				fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
			end else if (advance) begin
				underflow <= 1'b1;
			end

			case ({fifo_push, fifo_pop})
				2'b10:   fifo_used <= fifo_used + 1'b1;
				2'b01:   fifo_used <= fifo_used - 1'b1;
				default: fifo_used <= fifo_used;
			endcase
		end
	end

endmodule

`default_nettype wire

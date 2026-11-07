// SPDX-License-Identifier: GPL-3.0-or-later
// Written 2026 by Videodr0me
// Two-level validity keeps atomic list clears in 64 block flags. The per-word
// bits live in synchronous RAM; the bus pending phase supplies the RMW read.
`default_nettype none

module aztarac_snapshot_valid (
	input  wire        clk, clear, save,
	input  wire [10:0] cpu_addr, vector_addr,
	output wire        cpu_saved, vector_saved
);
	(* ramstyle = "M10K, no_rw_check" *) logic [31:0] words[0:63];
	logic  [63:0] blocks;
	logic  [31:0] cpu_word_q, vector_word_q;
	logic  [4:0]  vector_bit_q;
	logic         vector_block_q, vector_forward_q, vector_forward_bit_q;
	wire          write_word   = save && !clear;
	assign        cpu_saved    = blocks[cpu_addr[10:5]] && cpu_word_q[cpu_addr[4:0]];
	assign        vector_saved = vector_block_q &&
	                             (vector_forward_q ? vector_forward_bit_q
	                                               : vector_word_q[vector_bit_q]);
	always_ff @(posedge clk) begin
		cpu_word_q    <= words[cpu_addr[10:5]];
		vector_word_q <= words[vector_addr[10:5]];
		if (write_word)
			words[cpu_addr[10:5]] <= (blocks[cpu_addr[10:5]] ? cpu_word_q : 32'd0) |
			                         (32'd1 << cpu_addr[4:0]);
		vector_bit_q   <= vector_addr[4:0];
		vector_block_q <= blocks[vector_addr[10:5]];
		// A write can collide with a different display bit in the same RAM word.
		// Forward the old CPU read so mixed-port read-during-write is irrelevant.
		vector_forward_q     <= write_word && cpu_addr[10:5] == vector_addr[10:5];
		vector_forward_bit_q <= cpu_word_q[vector_addr[4:0]];
		if (clear) blocks <= 64'd0;
		else if (save) blocks[cpu_addr[10:5]] <= 1'b1;
	end
endmodule

`default_nettype wire

// ============================================================================
// VART burst ownership, row decoding, and pixel-enable aligned palette lookup.
// Written 2026 by Videodr0me
// ============================================================================

`default_nettype none

module vfb_artwork_readout #(
	parameter logic [28:0] ARTWORK_BASE = vfb_layout_pkg::VFB_ARTWORK_BASE,
	parameter integer      MAX_WIDTH    = 2048
) (
	input wire                                clk_sys,
	input wire                                reset,
	input wire                                video_timing_reset,
	input wire                                run_requested,
	input vfb_layout_pkg::vfb_artwork_plane_t active_plane,
	input wire  [11:0]                        render_width,
	input wire  [11:0]                        render_height,

	input  wire         ce_pix,
	input  wire         video_hblank_in,
	input  wire         video_vblank_in,
	output logic        input_art_valid,
	output logic [11:0] palette_addr,

	output logic        artwork_read_ready,
	input  wire         artwork_read_grant,
	output logic [28:0] artwork_read_addr,
	output logic [7:0]  artwork_read_burstcnt,
	input  wire  [63:0] artwork_read_data,
	input  wire         artwork_read_data_valid
);

	import vfb_layout_pkg::*;

	initial begin
		if ((MAX_WIDTH < 1440) || (MAX_WIDTH > 4096) || ((MAX_WIDTH & (MAX_WIDTH - 1)) != 0))
			$error("vfb_artwork_readout row depth must cover 1440 pixels and fit 12 bits");
	end

	localparam integer COMPRESSED_FIFO_DEPTH  = 128;
	localparam integer COMPRESSED_FIFO_ADDR_W = $clog2(COMPRESSED_FIFO_DEPTH);
	localparam integer ROW_ADDR_W             = $clog2(MAX_WIDTH);

	function automatic [10:0] row_word_count(input logic [15:0] encoded_bits);
		logic [16:0] padded_bits;
		begin
			padded_bits    = {1'b0, encoded_bits} + 17'd79;
			row_word_count = padded_bits[16:6];
		end
	endfunction

	logic                            compressed_fifo_reset =  1'b1;
	logic                            compressed_fifo_wr    =  1'b0;
	logic [63:0]                     compressed_fifo_wdata = 64'd0;
	logic                            compressed_fifo_rd    =  1'b0;
	wire  [63:0]                     compressed_fifo_data;
	wire                             compressed_fifo_full;
	wire                             compressed_fifo_empty;
	wire  [COMPRESSED_FIFO_ADDR_W:0] compressed_fifo_used;

	vfb_sync_fifo #(
		.WIDTH(64),
		.DEPTH(COMPRESSED_FIFO_DEPTH)
	) compressed_fifo (
		.clk_sys(clk_sys),
		.reset(compressed_fifo_reset),
		.wr_en(compressed_fifo_wr),
		.wr_data(compressed_fifo_wdata),
		.full(compressed_fifo_full),
		.rd_en(compressed_fifo_rd),
		.rd_data(compressed_fifo_data),
		.empty(compressed_fifo_empty),
		.used(compressed_fifo_used)
	);

	logic        packet_vblank_q        = 1'b1;
	logic        run_requested_q        = 1'b0;
	logic        stream_restart_pending = 1'b0;
	logic        stream_active          = 1'b0;
	logic        stream_discard         = 1'b1;
	logic        stream_decoder_reset   = 1'b1;
	logic        read_inflight          = 1'b0;
	logic [7:0]  read_beats_left        = 8'd0;
	logic [28:0] stream_fetch_addr      = ARTWORK_BASE;
	logic [31:0] stream_words_left      = 32'd0;

	wire vblank_rise         = ce_pix && video_vblank_in && !packet_vblank_q;
	wire start_during_vblank = run_requested && !run_requested_q && video_vblank_in;
	wire restart_now         = vblank_rise || start_during_vblank;

	always_ff @(posedge clk_sys) begin
		compressed_fifo_wr    <= 1'b0;
		compressed_fifo_reset <= 1'b0;
		stream_decoder_reset  <= 1'b0;
		run_requested_q       <= run_requested;
		if (ce_pix) packet_vblank_q <= video_vblank_in;

		if (reset) begin
			artwork_read_ready     <=  1'b0;
			read_inflight          <=  1'b0;
			read_beats_left        <=  8'd0;
			stream_restart_pending <=  1'b0;
			stream_active          <=  1'b0;
			stream_discard         <=  1'b1;
			compressed_fifo_reset  <=  1'b1;
			stream_decoder_reset   <=  1'b1;
			compressed_fifo_wdata  <= 64'd0;
			packet_vblank_q        <=  1'b1;
			run_requested_q        <=  1'b0;
		end else begin
			if (!run_requested || video_timing_reset) begin
				// Timing changes stop decoding, but the arbiter still owns
				// any pending or granted read until its last beat returns.
				stream_restart_pending <= 1'b0;
				stream_active          <= 1'b0;
				stream_discard         <= 1'b1;
				compressed_fifo_reset  <= 1'b1;
				stream_decoder_reset   <= 1'b1;
			end else if (restart_now) begin
				// Retain a pending request until its registered grant arrives.
				stream_restart_pending <= 1'b1;
				stream_active          <= 1'b0;
				stream_discard         <= 1'b1;
			end

			if (artwork_read_grant) begin
				artwork_read_ready <= 1'b0;
				read_inflight      <= 1'b1;
				read_beats_left    <= artwork_read_burstcnt;
				stream_fetch_addr  <= stream_fetch_addr + {21'd0, artwork_read_burstcnt};
				stream_words_left  <= stream_words_left - {24'd0, artwork_read_burstcnt};
			end

			if (artwork_read_data_valid && read_inflight) begin
				if (!stream_discard && !restart_now && run_requested &&
				    !video_timing_reset && !compressed_fifo_full) begin
					compressed_fifo_wr    <= 1'b1;
					compressed_fifo_wdata <= artwork_read_data;
				end
				if (read_beats_left == 8'd1) begin
					read_beats_left <= 8'd0;
					read_inflight   <= 1'b0;
				end else begin
					read_beats_left <= read_beats_left - 1'b1;
				end
			end

			if (run_requested && !video_timing_reset && !restart_now &&
			    stream_restart_pending && !read_inflight && !artwork_read_ready) begin
				compressed_fifo_reset  <= 1'b1;
				stream_decoder_reset   <= 1'b1;
				stream_fetch_addr      <= ARTWORK_BASE + active_plane.payload_offset[31:3];
				stream_words_left      <= active_plane.payload_size >> 3;
				stream_restart_pending <= 1'b0;
				stream_active          <= 1'b1;
				stream_discard         <= 1'b0;
			end else if (run_requested && !video_timing_reset && !restart_now &&
			             stream_active && !read_inflight &&
			             !artwork_read_ready && (stream_words_left != 0) &&
			             (compressed_fifo_used <= 8'd64)) begin
				artwork_read_addr     <= stream_fetch_addr;
				artwork_read_burstcnt <= (stream_words_left >= 32'd32) ? 8'd32
				                                                       : stream_words_left[7:0];
				artwork_read_ready    <= 1'b1;
			end
		end
	end

	// ------------------------------------------------------------------------
	// Every encoded artwork command sustains one output pixel per clock.
	// ------------------------------------------------------------------------

	typedef enum logic [3:0] {
		DEC_IDLE,
		DEC_ROW_START,
		DEC_TOKEN,
		DEC_LITERAL,
		DEC_REPEAT,
		DEC_COPY,
		DEC_FINISH,
		DEC_ERROR,
		DEC_ROW_PRIME
	} decode_state_t;

	decode_state_t decode_state = DEC_IDLE;
	// The front stays byte-aligned. The phase selects one of four pair offsets.
	logic [31:0] decode_front           = 32'd0;
	logic  [1:0] decode_front_phase     =  2'd0;
	logic [79:0] decode_tail            = 80'd0;
	logic  [3:0] decode_tail_count      =  4'd0;
	logic  [6:0] decode_buffered_pairs  =  7'd0;
	logic [14:0] decode_pairs_left      = 15'd0;
	logic [10:0] decode_words_remaining = 11'd0;
	logic        decode_word_available  =  1'b0;
	logic [11:0] decode_row             = 12'd0;
	logic [11:0] decode_x               = 12'd0;
	logic [11:0] decode_x_plus_one      = 12'd1;
	logic [11:0] decode_room            = 12'd0;
	logic  [7:0] decode_run_left        =  8'd0;
	logic  [7:0] decode_repeat_value    =  8'd0;
	logic        row_write_enable       =  1'b0;
	logic        row_write_bank         =  1'b0;
	logic [11:0] row_write_addr         = 12'd0;
	logic  [7:0] row_write_data         =  8'd0;
	logic  [1:0] row_valid              = 2'b00;
	logic [11:0] row_number [0:1];
	logic        stream_error       =  1'b0;
	logic [63:0] decode_input_word  = 64'd0;
	logic        decode_input_valid =  1'b0;

	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] row0_memory [0:MAX_WIDTH-1];
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] row1_memory [0:MAX_WIDTH-1];
	logic [ROW_ADDR_W-1:0] row0_port_a_addr;
	logic [ROW_ADDR_W-1:0] row1_port_a_addr;
	logic [7:0]            row0_copy_data    = 8'd0;
	logic [7:0]            row1_copy_data    = 8'd0;
	logic [7:0]            copy_hold_data    = 8'd0;
	logic                  copy_hold_valid   = 1'b0;
	logic [7:0]            row0_display_data = 8'd0;
	logic [7:0]            row1_display_data = 8'd0;
	logic [ROW_ADDR_W-1:0] display_read_addr =   '0;

	wire       decode_target_bank       = decode_row[0];
	wire       decode_previous_bank     = ~decode_target_bank;
	wire [7:0] decode_previous_ram_data = decode_previous_bank ? row1_copy_data : row0_copy_data;
	wire [7:0] decode_previous_data     = copy_hold_valid ? copy_hold_data
	                                                      : decode_previous_ram_data;

	logic [15:0] decode_window;
	always_comb begin
		case (decode_front_phase)
			2'd0:    decode_window = decode_front[15:0];
			2'd1:    decode_window = decode_front[17:2];
			2'd2:    decode_window = decode_front[19:4];
			default: decode_window = decode_front[21:6];
		endcase
	end

	// All encoded fields contain an even number of bits, so occupancy is tracked in pairs.
	wire [2:0]  active_index_pairs    = active_plane.index_bits[3:1];
	wire        token_is_literal      = !decode_window[7];
	wire        token_is_repeat       = decode_window[7:6] == 2'b10;
	wire        token_is_copy         = decode_window[7:6] == 2'b11;
	wire [6:0]  token_count_minus_one = token_is_literal ? decode_window[6:0]
	                                                     : {1'b0, decode_window[5:0]};
	wire [3:0]  token_required_pairs  = token_is_copy ? 4'd4 : ({1'b0, active_index_pairs} + 4'd4);
	wire        token_fits            = {5'd0, token_count_minus_one} < decode_room;
	wire [10:0] row_start_word_count  = row_word_count(decode_input_word[15:0]);

	wire        decoder_stream_state       = ((decode_state == DEC_TOKEN) ||
	                                          (decode_state == DEC_LITERAL) ||
	                                          (decode_state == DEC_REPEAT) ||
	                                          (decode_state == DEC_COPY));
	wire        decoder_candidate_consumes = (decode_state == DEC_TOKEN) ||
	                                         (decode_state == DEC_LITERAL);
	wire  [3:0] decoder_candidate_pairs    = !decoder_candidate_consumes ? 4'd0 :
	                                         (decode_state == DEC_TOKEN) ? token_required_pairs :
	                                             {1'b0, active_index_pairs};
	wire  [3:0] decoder_index_phase_sum    = {2'd0, decode_front_phase} +
	                                         {1'b0, active_index_pairs};
	logic [1:0] decoder_candidate_bytes;
	logic [1:0] decoder_candidate_phase;
	always_comb begin
		decoder_candidate_bytes = 2'd0;
		decoder_candidate_phase = decode_front_phase;
		case (decode_state)
			DEC_TOKEN:   begin
				if (token_is_copy) begin
					decoder_candidate_bytes = 2'd1;
				end else begin
					decoder_candidate_bytes = decoder_index_phase_sum[3:2] + 2'd1;
					decoder_candidate_phase = decoder_index_phase_sum[1:0];
				end
			end
			DEC_LITERAL: begin
				decoder_candidate_bytes = decoder_index_phase_sum[3:2];
				decoder_candidate_phase = decoder_index_phase_sum[1:0];
			end
			default:     begin end
		endcase
	end

	wire         decoder_prefetch_tail = (decoder_stream_state || decode_state == DEC_ROW_PRIME) &&
	                                     (decode_tail_count <= 4'd2) && decode_word_available &&
	                                     decode_input_valid;
	logic [79:0] decode_tail_prefetched;
	logic [3:0]  decode_tail_count_prefetched;
	always_comb begin
		decode_tail_prefetched       = decode_tail;
		decode_tail_count_prefetched = decode_tail_count;
		if (decoder_prefetch_tail) begin
			case (decode_tail_count)
				4'd0:    decode_tail_prefetched = {16'd0, decode_input_word};
				4'd1:    decode_tail_prefetched = {8'd0, decode_input_word, decode_tail[7:0]};
				default: decode_tail_prefetched = {decode_input_word, decode_tail[15:0]};
			endcase
			decode_tail_count_prefetched = decode_tail_count + 4'd8;
		end
	end

	logic decoder_pairs_available;
	always_comb begin
		decoder_pairs_available = 1'b1;
		case (decode_state)
			DEC_TOKEN:   begin
				if (token_is_copy) begin
					decoder_pairs_available = decode_buffered_pairs >= 7'd4;
				end else begin
					case (active_plane.index_mode)
						INDEX_MODE_4:
							decoder_pairs_available = decode_buffered_pairs >= 7'd6;
						INDEX_MODE_6:
							decoder_pairs_available = decode_buffered_pairs >= 7'd7;
						default:
							decoder_pairs_available = decode_buffered_pairs >= 7'd8;
					endcase
				end
			end
			DEC_LITERAL: begin
				case (active_plane.index_mode)
					INDEX_MODE_4:
						decoder_pairs_available = decode_buffered_pairs >= 7'd2;
					INDEX_MODE_6:
						decoder_pairs_available = decode_buffered_pairs >= 7'd3;
					default:
						decoder_pairs_available = decode_buffered_pairs >= 7'd4;
				endcase
			end
			default:     begin end
		endcase
	end
	// Keep the four-byte front contiguous while further source words remain.
	// Consuming valid front bytes without replacement would insert tail padding
	// before a later DDR refill. The final word may shift harmless row padding.
	wire  decoder_front_replenished = !decode_word_available ||
	                                  (decode_tail_count_prefetched >=
	                                   {2'd0, decoder_candidate_bytes});
	wire  decoder_stream_ready      = (decoder_prefetch_tail || decoder_pairs_available) &&
	                                  decoder_front_replenished;
	logic front_advance_ok;
	always_comb begin
		front_advance_ok = 1'b0;
		case (decode_state)
			DEC_TOKEN:   begin
				front_advance_ok = (decode_pairs_left >= {11'd0, token_required_pairs}) &&
				                   (decode_room != 0) &&
				                   token_fits;
			end
			DEC_LITERAL: begin
				front_advance_ok = (decode_pairs_left >= {12'd0, active_index_pairs}) &&
				                   (decode_room != 0);
			end
			default:     begin end
		endcase
	end

	logic decoder_advance_without_stream;
	always_comb begin
		decoder_advance_without_stream = 1'b0;
		case (decode_state)
			DEC_TOKEN:   begin
				decoder_advance_without_stream = (decode_room != 0) && token_fits;
			end
			DEC_LITERAL: begin
				decoder_advance_without_stream = (decode_room != 0) && (decode_run_left != 0);
			end
			DEC_REPEAT,
			DEC_COPY: begin
				decoder_advance_without_stream = (decode_room != 0) && (decode_run_left != 0);
			end
			default: begin end
		endcase
	end
	wire decoder_advance_without_refill = decoder_advance_without_stream &&
	                                      decoder_pairs_available && decoder_front_replenished;
	wire decoder_prefetch_advance       = decoder_prefetch_tail ? decoder_advance_without_stream
	                                                            : decoder_advance_without_refill;

	wire        decoder_consumes_front             = front_advance_ok && decoder_stream_ready;
	wire        decoder_consumes_front_with_refill = front_advance_ok;
	wire        decoder_pair_count_commit          = decoder_consumes_front &&
	                                                 ((decode_state == DEC_TOKEN) ||
	                                                  (decode_run_left != 0));
	wire [14:0] decode_pairs_left_consumed         = decode_pairs_left -
	                                                 {11'd0, decoder_candidate_pairs};
	wire        decoder_row_load                   = (decode_state == DEC_ROW_START) &&
	                                                 decode_input_valid && !decode_input_word[0];
	wire [1:0]  decoder_byte_advance               = decoder_consumes_front ?
	                                                 decoder_candidate_bytes :
	                                                 2'd0;
	wire [6:0]  decode_buffered_pairs_consumed     = decode_buffered_pairs -
	                                                 {3'd0, decoder_candidate_pairs};
	// A refill occurs with at most two tail bytes, so occupancy is below 32 pairs.
	wire [6:0] decode_buffered_pairs_refilled          = {1'b0, 1'b1, decode_buffered_pairs[4:0]};
	wire [6:0] decode_buffered_pairs_refilled_consumed = decode_buffered_pairs_refilled -
	                                                     {3'd0, decoder_candidate_pairs};

	logic [31:0] decode_front_next;
	logic [79:0] decode_tail_next;
	logic  [3:0] decode_tail_count_next;
	always_comb begin
		case (decoder_byte_advance)
			2'd1:    begin
				decode_front_next = {decode_tail_prefetched[7:0], decode_front[31:8]};
				decode_tail_next  = decode_tail_prefetched >> 8;
			end
			2'd2:    begin
				decode_front_next = {decode_tail_prefetched[15:0], decode_front[31:16]};
				decode_tail_next  = decode_tail_prefetched >> 16;
			end
			default: begin
				decode_front_next = decode_front;
				decode_tail_next  = decode_tail_prefetched;
			end
		endcase
		decode_tail_count_next = (decode_tail_count_prefetched >= {2'd0, decoder_byte_advance}) ?
		                         (decode_tail_count_prefetched - {2'd0, decoder_byte_advance}) :
		                         4'd0;
	end

	wire [11:0] copy_source_addr = decoder_stream_state ? decode_x_plus_one : 12'd0;

	always_comb begin
		row0_port_a_addr = '0;
		row1_port_a_addr = '0;
		if (row_write_enable && !row_write_bank)
			row0_port_a_addr = row_write_addr[ROW_ADDR_W-1:0];
		else if (decode_previous_bank == 1'b0)
			row0_port_a_addr = copy_source_addr[ROW_ADDR_W-1:0];

		if (row_write_enable && row_write_bank)
			row1_port_a_addr = row_write_addr[ROW_ADDR_W-1:0];
		else if (decode_previous_bank == 1'b1)
			row1_port_a_addr = copy_source_addr[ROW_ADDR_W-1:0];
	end

	always_ff @(posedge clk_sys) begin
		if (row_write_enable && !row_write_bank)
			row0_memory[row0_port_a_addr] <= row_write_data;
		else
			row0_copy_data <= row0_memory[row0_port_a_addr];
		if (ce_pix) row0_display_data <= row0_memory[display_read_addr];
	end

	always_ff @(posedge clk_sys) begin
		if (row_write_enable && row_write_bank)
			row1_memory[row1_port_a_addr] <= row_write_data;
		else
			row1_copy_data <= row1_memory[row1_port_a_addr];
		if (ce_pix) row1_display_data <= row1_memory[display_read_addr];
	end

	logic        packet_hblank_q  =  1'b1;
	logic [11:0] display_line     = 12'd0;
	logic        display_bank     =  1'b0;
	logic        frame_artwork_ok =  1'b0;

	wire        active_line_start  = ce_pix && !video_hblank_in && packet_hblank_q;
	wire        active_frame_start = active_line_start && !video_vblank_in && packet_vblank_q;
	wire [11:0] line_at_start      = active_frame_start ? 12'd0 : (display_line + 1'b1);
	wire        bank_at_start      = line_at_start[0];
	wire        row_ready_at_start = row_valid[bank_at_start] &&
	                                 (row_number[bank_at_start] == line_at_start);

	// Row start replaces stale payload before decoder state permits its use.
	always_ff @(posedge clk_sys) begin
		if (decoder_row_load) begin
			decode_front       <= decode_input_word[47:16];
			decode_front_phase <= 2'd0;
		end else if (decoder_consumes_front) begin
			decode_front       <= decode_front_next;
			decode_front_phase <= decoder_candidate_phase;
		end
	end

	always_ff @(posedge clk_sys) begin
		compressed_fifo_rd <= 1'b0;
		row_write_enable   <= 1'b0;

		if (ce_pix) packet_hblank_q <= video_hblank_in;

		if (reset || video_timing_reset || stream_decoder_reset) begin
			decode_state           <= DEC_IDLE;
			copy_hold_data         <=  8'd0;
			copy_hold_valid        <=  1'b0;
			decode_tail            <= 80'd0;
			decode_tail_count      <=  4'd0;
			decode_buffered_pairs  <=  7'd0;
			decode_pairs_left      <= 15'd0;
			decode_words_remaining <= 11'd0;
			decode_word_available  <=  1'b0;
			decode_row             <= 12'd0;
			decode_x               <= 12'd0;
			decode_x_plus_one      <= 12'd1;
			decode_room            <= 12'd0;
			decode_run_left        <=  8'd0;
			row_valid              <= 2'b00;
			row_number[0]          <= 12'd0;
			row_number[1]          <= 12'd0;
			stream_error           <=  1'b0;
			display_line           <= 12'd0;
			display_bank           <=  1'b0;
			frame_artwork_ok       <=  1'b0;
			packet_hblank_q        <=  1'b1;
			decode_input_word      <= 64'd0;
			decode_input_valid     <=  1'b0;
		end else begin
			if (!decoder_stream_state || decoder_prefetch_advance) begin
				copy_hold_valid <= 1'b0;
			end else if (!copy_hold_valid) begin
				copy_hold_data  <= decode_previous_ram_data;
				copy_hold_valid <= 1'b1;
			end

			if (!decode_input_valid && !compressed_fifo_empty) begin
				compressed_fifo_rd <= 1'b1;
				decode_input_word  <= compressed_fifo_data;
				decode_input_valid <= 1'b1;
			end
			if (decode_state == DEC_TOKEN) decode_run_left <= {1'b0, token_count_minus_one};

			if (decoder_prefetch_tail) begin
				decode_input_valid     <= 1'b0;
				decode_words_remaining <= decode_words_remaining - 1'b1;
				decode_word_available  <= (decode_words_remaining != 11'd1);
			end
			if (decoder_prefetch_tail || (decoder_consumes_front && (decoder_byte_advance != 0))) begin
				decode_tail       <= decode_tail_next;
				decode_tail_count <= decode_tail_count_next;
			end
			if (decoder_prefetch_tail) begin
				decode_buffered_pairs <= decoder_consumes_front_with_refill ?
				                         decode_buffered_pairs_refilled_consumed :
				                         decode_buffered_pairs_refilled;
			end else if (decoder_consumes_front) begin
				decode_buffered_pairs <= decode_buffered_pairs_consumed;
			end
			if (decoder_pair_count_commit) decode_pairs_left <= decode_pairs_left_consumed;
			if (decoder_prefetch_advance)  decode_x_plus_one <= decode_x_plus_one + 1'b1;

			if (vblank_rise) frame_artwork_ok <= 1'b0;

			if (active_line_start && !video_vblank_in) begin
				if (active_frame_start) begin
					display_line     <= 12'd0;
					display_bank     <=  1'b0;
					frame_artwork_ok <= run_requested && row_ready_at_start;
				end else begin
					row_valid[display_bank] <= 1'b0;
					display_line            <= line_at_start;
					display_bank            <= bank_at_start;
					if (!row_ready_at_start) frame_artwork_ok <= 1'b0;
				end
			end

			case (decode_state)
				DEC_IDLE: begin
					if (stream_active && !stream_error &&
					    (decode_row < render_height) &&
					    !row_valid[decode_target_bank] &&
					    ((decode_row == 0) ||
					     (row_valid[decode_previous_bank] &&
					      (row_number[decode_previous_bank] == decode_row - 1'b1))) &&
					    decode_input_valid)
						decode_state <= DEC_ROW_START;
				end

				DEC_ROW_START: begin
					if (decode_input_valid) begin
						decode_input_valid <= 1'b0;
						if (decode_input_word[0]) begin
							decode_state <= DEC_ERROR;
						end else begin
							decode_pairs_left      <= decode_input_word[15:1];
							decode_words_remaining <= row_start_word_count - 1'b1;
							decode_word_available  <= (row_start_word_count > 11'd1);
							decode_tail            <= {64'd0, decode_input_word[63:48]};
							decode_tail_count      <=  4'd2;
							decode_buffered_pairs  <= 7'd24;
							decode_x               <= 12'd0;
							decode_x_plus_one      <= 12'd1;
							decode_room            <= render_width;
							decode_run_left        <= 8'd0;
							decode_state           <= DEC_ROW_PRIME;
						end
					end
				end

				DEC_ROW_PRIME: begin
					// Fill the tail before the first literal can shift its bytes
					// into the front. DDR startup latency must not insert zeros.
					if (!decode_word_available || decoder_prefetch_tail) decode_state <= DEC_TOKEN;
				end

				DEC_TOKEN: begin
					if ((decode_room == 0) && (decode_pairs_left == 0)) begin
						decode_state <= DEC_FINISH;
					end else if ((decode_room == 0) || (decode_pairs_left < 4)) begin
						decode_state <= DEC_ERROR;
					end else if (!token_fits) begin
						decode_state <= DEC_ERROR;
					end else if (decode_pairs_left < {11'd0, token_required_pairs}) begin
						decode_state <= DEC_ERROR;
					end else if (!decoder_stream_ready) begin
						if (!decode_word_available) decode_state <= DEC_ERROR;
					end else begin
						row_write_enable <= 1'b1;
						row_write_bank   <= decode_target_bank;
						row_write_addr   <= decode_x;
						decode_x         <= decode_x + 1'b1;
						decode_room      <= decode_room - 1'b1;

						if (token_is_literal || token_is_repeat) begin
							case (active_plane.index_mode)
								INDEX_MODE_4: begin
									row_write_data      <= {4'd0, decode_window[11:8]};
									decode_repeat_value <= {4'd0, decode_window[11:8]};
								end
								INDEX_MODE_6: begin
									row_write_data      <= {2'd0, decode_window[13:8]};
									decode_repeat_value <= {2'd0, decode_window[13:8]};
								end
								default:      begin
									row_write_data      <= decode_window[15:8];
									decode_repeat_value <= decode_window[15:8];
								end
							endcase
							if (token_count_minus_one == 0)
								decode_state <= DEC_TOKEN;
							else if (token_is_literal)
								decode_state <= DEC_LITERAL;
							else
								decode_state <= DEC_REPEAT;
						end else begin
							row_write_data <= decode_previous_data;
							decode_state   <= (token_count_minus_one == 0) ? DEC_TOKEN : DEC_COPY;
						end
					end
				end

				DEC_LITERAL: begin
					if ((decode_room == 0) ||
					    (decode_run_left == 0) ||
					    (decode_pairs_left < {12'd0, active_index_pairs})) begin
						decode_state <= DEC_ERROR;
					end else if (!decoder_stream_ready) begin
						if (!decode_word_available) decode_state <= DEC_ERROR;
					end else begin
						row_write_enable <= 1'b1;
						row_write_bank   <= decode_target_bank;
						row_write_addr   <= decode_x;
						case (active_plane.index_mode)
							INDEX_MODE_4: begin
								row_write_data <= {4'd0, decode_window[3:0]};
							end
							INDEX_MODE_6: begin
								row_write_data <= {2'd0, decode_window[5:0]};
							end
							default:      begin
								row_write_data <= decode_window[7:0];
							end
						endcase
						decode_x        <= decode_x + 1'b1;
						decode_room     <= decode_room - 1'b1;
						decode_run_left <= decode_run_left - 1'b1;
						if (decode_run_left == 8'd1) decode_state <= DEC_TOKEN;
					end
				end

				DEC_REPEAT: begin
					if ((decode_room == 0) || (decode_run_left == 0)) begin
						decode_state <= DEC_ERROR;
					end else begin
						row_write_enable <= 1'b1;
						row_write_bank   <= decode_target_bank;
						row_write_addr   <= decode_x;
						row_write_data   <= decode_repeat_value;
						decode_x         <= decode_x + 1'b1;
						decode_room      <= decode_room - 1'b1;
						decode_run_left  <= decode_run_left - 1'b1;
						if (decode_run_left == 8'd1) decode_state <= DEC_TOKEN;
					end
				end

				DEC_COPY: begin
					if ((decode_room == 0) || (decode_run_left == 0)) begin
						decode_state <= DEC_ERROR;
					end else begin
						row_write_enable <= 1'b1;
						row_write_bank   <= decode_target_bank;
						row_write_addr   <= decode_x;
						row_write_data   <= decode_previous_data;
						decode_x         <= decode_x + 1'b1;
						decode_room      <= decode_room - 1'b1;
						decode_run_left  <= decode_run_left - 1'b1;
						if (decode_run_left == 8'd1) decode_state <= DEC_TOKEN;
					end
				end

				DEC_FINISH: begin
					if (!row_write_enable) begin
						if (decode_words_remaining != 0) begin
							decode_state <= DEC_ERROR;
						end else begin
							row_valid[decode_target_bank]  <= 1'b1;
							row_number[decode_target_bank] <= decode_row;
							decode_row                     <= decode_row + 1'b1;
							decode_state                   <= DEC_IDLE;
						end
					end
				end

				DEC_ERROR: begin
					stream_error     <= 1'b1;
					frame_artwork_ok <= 1'b0;
				end

				default: decode_state <= DEC_ERROR;
			endcase
		end
	end

	wire [11:0] input_line_number = active_line_start ? line_at_start : display_line;
	wire        input_row_bank    = active_line_start ? bank_at_start : display_bank;
	wire        input_line_ready  = active_line_start ?
	                                (active_frame_start ?
	                                     row_ready_at_start :
	                                     (frame_artwork_ok && row_ready_at_start)) :
	                                (frame_artwork_ok &&
	                                 row_valid[display_bank] &&
	                                 (row_number[display_bank] == display_line));

	logic [11:0] display_x         = 12'd0;
	logic [11:0] palette_read_addr = 12'd0;
	logic        row_bank_s0       =  1'b0;

	assign input_art_valid = run_requested && input_line_ready &&
	                         (input_line_number < render_height);
	assign palette_addr    = palette_read_addr;

	// These registers share ce_pix with the wrapper's RGB, sync, and blanking.
	// Row RAM -> palette address -> palette RAM retains the original latency.
	always_ff @(posedge clk_sys) begin
		if (reset || video_timing_reset) begin
			display_x         <= 12'd0;
			display_read_addr <=    '0;
			palette_read_addr <= 12'd0;
			row_bank_s0       <=  1'b0;
		end else if (ce_pix) begin
			if (video_hblank_in || video_vblank_in) begin
				display_x         <= 12'd0;
				display_read_addr <=    '0;
			end else begin
				display_read_addr <= display_x[ROW_ADDR_W-1:0] + 1'b1;
				display_x         <= display_x + 1'b1;
			end
			row_bank_s0       <= input_row_bank;
			palette_read_addr <= active_plane.palette_offset[13:2] +
			                     {4'd0, (row_bank_s0 ? row1_display_data : row0_display_data)};
		end
	end

endmodule

`default_nettype wire

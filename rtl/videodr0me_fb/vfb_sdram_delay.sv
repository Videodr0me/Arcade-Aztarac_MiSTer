// ============================================================================
// RLE-compressed scanline delay in the MiSTer SDRAM.
// Written 2026 by Videodr0me
//
// Canonical pixels are encoded into independent 8 KiB line slots. Readout
// follows the current horizontal timing and uses timing from the matching line.
// ============================================================================

`default_nettype none

module vfb_sdram_delay #(
	parameter integer SDRAM_MHZ       =  125,
	parameter integer SLOT_COUNT      =  128,
	parameter integer SLOT_BYTES      = 8192,
	parameter integer FIFO_DEPTH      =  256,
	parameter integer READ_FIFO_DEPTH =  512,
	parameter integer SLOT_W          = $clog2(SLOT_COUNT),
	parameter integer FIFO_AW         = $clog2(FIFO_DEPTH),
	parameter integer READ_FIFO_AW    = $clog2(READ_FIFO_DEPTH)
) (
	input  wire         clk_sys,
	input  wire         reset,
	input  wire         ce_pix,
	input  wire  [11:0] line_delay,

	input  wire  [13:0] CANONICAL_IN,
	input  wire         VGA_HS_IN,
	input  wire         VGA_VS_IN,
	input  wire         VGA_HBLANK_IN,
	input  wire         VGA_VBLANK_IN,

	output logic [13:0] CANONICAL_OUT,
	output logic        VGA_HS_OUT,
	output logic        VGA_VS_OUT,
	output logic        VGA_HBLANK_OUT,
	output logic        VGA_VBLANK_OUT,

	input  wire  [15:0] sdram_data_in,
	output logic [15:0] sdram_data_out,
	output logic        sdram_data_oe,
	output logic        sdram_cke,
	output logic        sdram_cs,
	output logic        sdram_ras,
	output logic        sdram_cas,
	output logic        sdram_we,
	output logic [1:0]  sdram_dqm,
	output logic [12:0] sdram_addr,
	output logic [1:0]  sdram_ba,

	output logic        overflow,
	output logic        underflow,
	output logic        init_done
);

	localparam integer MAX_WORDS    = SLOT_BYTES / 2;
	localparam integer MAX_PAIRS    = SLOT_BYTES / 4;
	localparam integer WORD_W       = $clog2(MAX_WORDS);
	localparam integer PAIR_W       = $clog2(MAX_PAIRS);
	localparam integer WRITE_FIFO_W = 1 + SLOT_W + PAIR_W + 32;
	// READ_FIFO_DEPTH counts 16-bit codec words; storage holds half as many
	// 32-bit SDRAM response entries.
	localparam integer READ_PAIR_FIFO_DEPTH = READ_FIFO_DEPTH / 2;
	localparam integer READ_PAIR_FIFO_AW    = $clog2(READ_PAIR_FIFO_DEPTH);
	localparam integer READ_FIFO_W          = 34;
	localparam integer READ_DESC_DEPTH      =  4;
	localparam integer READ_DESC_AW         = $clog2(READ_DESC_DEPTH);
	localparam [5:0]   ARB_QUOTA            = 6'd32;
	localparam integer WRITE_URGENT_LEVEL   = (FIFO_DEPTH > 128) ? (FIFO_DEPTH - 64)
	                                                             : (FIFO_DEPTH - 8);
	localparam integer READ_URGENT_LEVEL    = (READ_PAIR_FIFO_DEPTH > 128) ?
	                                          64 :
	                                          (READ_PAIR_FIFO_DEPTH / 4);
	localparam integer WRITE_READY_MARGIN   = (FIFO_DEPTH > 16) ? 8 : (FIFO_DEPTH > 8)  ? 4 : 1;

	initial begin
		if ((SLOT_BYTES != 8192) || (SLOT_COUNT < 4) || (SLOT_COUNT > 4096))
			$error("vfb_sdram_delay requires 8 KiB slots within 32 MiB SDRAM");
		if ((SLOT_W != $clog2(SLOT_COUNT)) || (FIFO_AW != $clog2(FIFO_DEPTH)) ||
		    (READ_FIFO_AW != $clog2(READ_FIFO_DEPTH)))
			$error("vfb_sdram_delay address widths must match their storage depths");
		if (FIFO_DEPTH < 4)
			$error("vfb_sdram_delay requires at least four FIFO entries");
		if ((SLOT_COUNT & (SLOT_COUNT - 1)) != 0)
			$error("vfb_sdram_delay SLOT_COUNT must be a power of two");
		if ((FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0)
			$error("vfb_sdram_delay FIFO_DEPTH must be a power of two");
		if ((READ_FIFO_DEPTH & (READ_FIFO_DEPTH - 1)) != 0)
			$error("vfb_sdram_delay READ_FIFO_DEPTH must be a power of two");
		if (READ_FIFO_DEPTH < 4)
			$error("vfb_sdram_delay READ_FIFO_DEPTH must be at least four");
		if ((READ_DESC_DEPTH & (READ_DESC_DEPTH - 1)) != 0)
			$error("vfb_sdram_delay READ_DESC_DEPTH must be a power of two");
	end

	// Payload and ownership metadata retain their original registers and enables.
	typedef struct packed {
		logic              valid;
		logic [15:0]       word;
		logic [PAIR_W-1:0] pair_index;
		logic [SLOT_W-1:0] slot;
	} packed_word_t;

	typedef struct packed {
		logic              valid;
		logic              eol;
		logic [SLOT_W-1:0] slot;
		logic [PAIR_W-1:0] index;
		logic [31:0]       data;
	} write_head_t;

	typedef struct packed {
		logic              pending;
		logic [SLOT_W-1:0] slot;
		logic              vsync;
		logic              vblank;
	} line_finalize_t;

	typedef struct packed {
		logic              pending;
		logic              warmed;
		logic [SLOT_W-1:0] slot;
	} descriptor_lookup_t;

	typedef struct packed {
		logic              pending;
		logic              warmed;
		logic [SLOT_W-1:0] slot;
		logic [WORD_W:0]   words;
		logic              vsync;
		logic              vblank;
		logic              valid;
		logic              written;
	} descriptor_apply_t;

	typedef struct packed {
		logic valid;
		logic vsync;
		logic vblank;
	} line_status_t;

	typedef struct packed {
		logic              valid;
		logic              read;
		logic              write;
		logic [31:0]       addr;
		logic [31:0]       wdata;
		logic              write_eol;
		logic [SLOT_W-1:0] write_slot;
	} issue_packet_t;

	// Detect lines and encode canonical pixels.
	logic              hblank_d;
	logic              line_had_pixels;
	logic              line_vsync;
	logic              line_vblank;
	logic [15:0]       line_sequence;
	logic [SLOT_W-1:0] encode_slot;
	logic [WORD_W-1:0] encode_word_index;

	wire active_pixel = ce_pix && !VGA_HBLANK_IN && !VGA_VBLANK_IN;
	wire line_start   = ce_pix && hblank_d && !VGA_HBLANK_IN;
	wire line_end     = ce_pix && !hblank_d && VGA_HBLANK_IN;

	always_ff @(posedge clk_sys) begin
		if (reset)
			hblank_d <= 1'b1;
		else if (ce_pix)
			hblank_d <= VGA_HBLANK_IN;
	end

	logic        enc_token_valid;
	logic        enc_token_ready;
	logic [15:0] enc_token_data;
	logic        enc_token_eol;
	logic        enc_overflow;

	vfb_rle_encoder encoder (
		.clk_sys(clk_sys),
		.reset(reset),
		.pixel_valid(active_pixel),
		.canonical_in(CANONICAL_IN),
		.line_end(line_end),
		.token_valid(enc_token_valid),
		.token_ready(enc_token_ready),
		.token_data(enc_token_data),
		.token_eol(enc_token_eol),
		.overflow(enc_overflow)
	);

	// Each queued 32-bit word carries its line slot and word index, so writing
	// can begin before the line ends.
	logic                    write_fifo_full;
	logic                    write_fifo_empty;
	logic [WRITE_FIFO_W-1:0] write_fifo_data;
	logic [FIFO_AW:0]        write_fifo_used;
	packed_word_t            pack_pending;
	logic                    write_fifo_room_q;
	logic                    encoder_fifo_room_q;
	logic                    write_pair_valid_q;
	logic [WRITE_FIFO_W-1:0] write_pair_data_q;
	wire                     enc_packet_accept = enc_token_valid && enc_token_ready;
	wire                     write_pair_accept = enc_packet_accept &&
	                                             (pack_pending.valid || enc_token_eol);
	wire                     write_fifo_push   = write_pair_valid_q;
	logic [31:0]             write_fifo_pair_data;
	logic [PAIR_W-1:0]       write_fifo_pair_index;
	logic [SLOT_W-1:0]       write_fifo_pair_slot;
	logic                    write_fifo_pair_eol;
	wire  [WRITE_FIFO_W-1:0] write_pair_data            = {write_fifo_pair_eol,
	                                                       write_fifo_pair_slot,
	                                                       write_fifo_pair_index,
	                                                       write_fifo_pair_data};
	wire  [WORD_W:0]         encoded_words_after_packet = {1'b0, encode_word_index} +
	                                                      {{WORD_W{1'b0}}, 1'b1};
	wire                     write_fifo_pop;
	write_head_t             write_head;
	wire                     write_head_consume;

	always_comb begin
		write_fifo_pair_data  = 32'd0;
		write_fifo_pair_index = encode_word_index[WORD_W-1:1];
		write_fifo_pair_slot  = encode_slot;
		write_fifo_pair_eol   = 1'b0;

		if (pack_pending.valid) begin
			write_fifo_pair_data  = {enc_token_data, pack_pending.word};
			write_fifo_pair_index = pack_pending.pair_index;
			write_fifo_pair_slot  = pack_pending.slot;
			write_fifo_pair_eol   = enc_token_eol;
		end else begin
			write_fifo_pair_data = {16'd0, enc_token_data};
			write_fifo_pair_eol  = enc_token_eol;
		end
	end

	assign enc_token_ready = !(pack_pending.valid || enc_token_eol) || encoder_fifo_room_q;

	vfb_sync_fifo #(
		.WIDTH(WRITE_FIFO_W),
		.DEPTH(FIFO_DEPTH)
	) write_fifo (
		.clk_sys(clk_sys),
		.reset(reset),
		.wr_en(write_fifo_push),
		.wr_data(write_pair_data_q),
		.full(write_fifo_full),
		.rd_en(write_fifo_pop),
		.rd_data(write_fifo_data),
		.empty(write_fifo_empty),
		.used(write_fifo_used)
	);

	// Register available-space checks and reserve room for accepted encoder
	// data that has not reached the FIFO yet.
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			write_fifo_room_q   <= 1'b0;
			encoder_fifo_room_q <= 1'b0;
			write_pair_valid_q  <= 1'b0;
		end else begin
			write_fifo_room_q   <= (write_fifo_used < (FIFO_DEPTH - WRITE_READY_MARGIN));
			encoder_fifo_room_q <= write_fifo_room_q;
			write_pair_valid_q  <= write_pair_accept;
			if (write_pair_accept) write_pair_data_q <= write_pair_data;
		end
	end

	assign write_fifo_pop = !write_fifo_empty && (!write_head.valid || write_head_consume);

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			write_head.valid <=  1'b0;
			write_head.eol   <=  1'b0;
			write_head.slot  <=    '0;
			write_head.index <=    '0;
			write_head.data  <= 32'd0;
		end else begin
			if (write_fifo_pop) begin
				write_head.valid <= 1'b1;
				write_head.eol   <= write_fifo_data[WRITE_FIFO_W-1];
				write_head.slot  <= write_fifo_data[WRITE_FIFO_W-2 -: SLOT_W];
				write_head.index <= write_fifo_data[31+PAIR_W:32];
				write_head.data  <= write_fifo_data[31:0];
			end else if (write_head_consume) begin
				write_head.valid <= 1'b0;
			end
		end
	end

	// Line descriptors
	logic [WORD_W:0] descriptor_words [0:SLOT_COUNT-1];
	logic            descriptor_vsync [0:SLOT_COUNT-1];
	logic            descriptor_vblank [0:SLOT_COUNT-1];
	logic            descriptor_valid [0:SLOT_COUNT-1];
	logic            descriptor_written [0:SLOT_COUNT-1];

	line_finalize_t     finalize;
	line_finalize_t     blank_finalize;
	descriptor_lookup_t descriptor_lookup;
	descriptor_apply_t  descriptor_apply;

	// Read preparation runs one line ahead. A line selected after line N is
	// stored in prefetch_line, moved to pending_line at the next line start,
	// and shown at the following line start. SDRAM therefore has one full line
	// to prepare the data.
	line_status_t prefetch_line;
	line_status_t pending_line;
	line_status_t output_line;

	logic [15:0] delayed_sequence;
	always_comb
		delayed_sequence = line_sequence + 16'd2 - {4'd0, line_delay};
	wire  [SLOT_W-1:0] delayed_slot = delayed_sequence[SLOT_W-1:0];
	logic              delay_warmed_r;
	wire               delay_warmed_now = (line_sequence + 16'd2 >= {4'd0, line_delay});
	wire               delay_warmed     = delay_warmed_r || delay_warmed_now;

	// Read compressed data and decode it.
	logic                       read_fifo_full;
	logic                       read_fifo_empty;
	logic [READ_FIFO_W-1:0]     read_fifo_data;
	logic [READ_PAIR_FIFO_AW:0] read_fifo_used;
	logic                       read_fifo_push;
	logic                       read_fifo_pop;
	logic [READ_FIFO_W-1:0]     read_fifo_write_data;

	vfb_sync_fifo #(
		.WIDTH(READ_FIFO_W),
		.DEPTH(READ_PAIR_FIFO_DEPTH)
	) read_fifo (
		.clk_sys(clk_sys),
		.reset(reset),
		.wr_en(read_fifo_push),
		.wr_data(read_fifo_write_data),
		.full(read_fifo_full),
		.rd_en(read_fifo_pop),
		.rd_data(read_fifo_data),
		.empty(read_fifo_empty),
		.used(read_fifo_used)
	);

	logic                  read_active;
	logic [SLOT_W-1:0]     read_slot;
	logic [PAIR_W:0]       read_pair_count;
	logic [PAIR_W:0]       read_issue_index;
	logic [PAIR_W:0]       read_response_remaining;
	logic                  read_words_odd;
	logic [READ_FIFO_AW:0] read_outstanding;

	logic [SLOT_W-1:0]       read_desc_slot [0:READ_DESC_DEPTH-1];
	logic [WORD_W:0]         read_desc_words [0:READ_DESC_DEPTH-1];
	logic [READ_DESC_AW-1:0] read_desc_wr_ptr;
	logic [READ_DESC_AW-1:0] read_desc_rd_ptr;
	logic [READ_DESC_AW:0]   read_desc_used;

	wire                  read_engine_idle             = !read_active && (read_outstanding == 0);
	wire                  descriptor_apply_ok          = descriptor_apply.pending &&
	                                                     descriptor_apply.warmed &&
	                                                     descriptor_apply.valid &&
	                                                     descriptor_apply.written;
	wire                  descriptor_apply_read_needed = descriptor_apply_ok &&
	                                                     (descriptor_apply.words != 0);
	wire                  read_desc_pop                = read_engine_idle && (read_desc_used != 0);
	wire [READ_DESC_AW:0] read_desc_used_after_pop     = read_desc_used -
	                                                     {{READ_DESC_AW{1'b0}}, read_desc_pop};
	wire                  read_desc_can_push           = (read_desc_used_after_pop < READ_DESC_DEPTH);
	wire                  read_desc_push               = descriptor_apply_read_needed &&
	                                                     !(read_engine_idle &&
	                                                       (read_desc_used == 0)) &&
	                                                     read_desc_can_push;
	wire                  read_desc_overflow           = descriptor_apply_read_needed &&
	                                                     !(read_engine_idle &&
	                                                       (read_desc_used == 0)) &&
	                                                     !read_desc_can_push;
	wire                  read_start_direct            = descriptor_apply_read_needed &&
	                                                     read_engine_idle && (read_desc_used == 0);
	wire                  read_start_queued            = read_desc_pop;
	wire                  read_start                   = read_start_direct || read_start_queued;
	wire [SLOT_W-1:0]     read_start_slot              = read_start_queued ?
	                                                     read_desc_slot[read_desc_rd_ptr] :
	                                                     descriptor_apply.slot;
	wire [WORD_W:0]       read_start_words             = read_start_queued ?
	                                                     read_desc_words[read_desc_rd_ptr] :
	                                                     descriptor_apply.words;
	wire [PAIR_W:0]       read_start_pairs             = read_start_words[WORD_W:1] +
	                                                     {{PAIR_W{1'b0}}, read_start_words[0]};

	logic [13:0] decoded_canonical;
	logic        decoded_valid;
	logic        decoded_line_done;
	logic        decoder_underflow;
	logic        decoder_token_ready;
	// Four words cover two SDRAM responses and absorb response/token phasing.
	logic [63:0] decoder_words;
	logic [3:0]  decoder_word_eol;
	logic [2:0]  decoder_word_count;
	logic [63:0] decoder_words_next;
	logic [3:0]  decoder_word_eol_next;
	logic [2:0]  decoder_word_count_next;

	wire decoder_token_valid  = (decoder_word_count != 0);
	wire decoder_token_accept = decoder_token_valid && decoder_token_ready;
	wire decoder_token_eol    = decoder_word_eol[0];

	wire       read_pair_high_valid       = read_fifo_data[32];
	wire       read_pair_eol              = read_fifo_data[33];
	wire [2:0] read_pair_words            = read_pair_high_valid ? 3'd2 : 3'd1;
	wire [2:0] decoder_words_after_accept = decoder_word_count -
	                                        (decoder_token_accept ? 3'd1 : 3'd0);

	assign read_fifo_pop = !read_fifo_empty &&
	                       (decoder_words_after_accept + read_pair_words <= 3'd4);

	always_comb begin
		decoder_words_next      = decoder_words;
		decoder_word_eol_next   = decoder_word_eol;
		decoder_word_count_next = decoder_word_count;

		if (decoder_token_accept) begin
			decoder_words_next      = {16'd0, decoder_words[63:16]};
			decoder_word_eol_next   = {1'b0, decoder_word_eol[3:1]};
			decoder_word_count_next = decoder_word_count - 1'b1;
		end

		if (read_fifo_pop) begin
			case (decoder_word_count_next)
				3'd0: begin
					decoder_words_next[15:0] = read_fifo_data[15:0];
					decoder_word_eol_next[0] = read_pair_eol && !read_pair_high_valid;
					if (read_pair_high_valid) begin
						decoder_words_next[31:16] = read_fifo_data[31:16];
						decoder_word_eol_next[1]  = read_pair_eol;
					end
				end

				3'd1: begin
					decoder_words_next[31:16] = read_fifo_data[15:0];
					decoder_word_eol_next[1]  = read_pair_eol && !read_pair_high_valid;
					if (read_pair_high_valid) begin
						decoder_words_next[47:32] = read_fifo_data[31:16];
						decoder_word_eol_next[2]  = read_pair_eol;
					end
				end

				3'd2: begin
					decoder_words_next[47:32] = read_fifo_data[15:0];
					decoder_word_eol_next[2]  = read_pair_eol && !read_pair_high_valid;
					if (read_pair_high_valid) begin
						decoder_words_next[63:48] = read_fifo_data[31:16];
						decoder_word_eol_next[3]  = read_pair_eol;
					end
				end

				default: begin
					decoder_words_next[63:48] = read_fifo_data[15:0];
					decoder_word_eol_next[3]  = read_pair_eol;
				end
			endcase
			decoder_word_count_next = decoder_word_count_next + read_pair_words;
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			decoder_words      <= 64'd0;
			decoder_word_eol   <=  4'd0;
			decoder_word_count <=  3'd0;
		end else begin
			decoder_words      <= decoder_words_next;
			decoder_word_eol   <= decoder_word_eol_next;
			decoder_word_count <= decoder_word_count_next;
		end
	end

	// Select the pending line at line start and hold its timing through the line.
	wire  current_line_valid  = line_start ? pending_line.valid : output_line.valid;
	wire  current_line_vsync  = line_start ? pending_line.vsync : output_line.vsync;
	wire  current_line_vblank = line_start ? pending_line.vblank : output_line.vblank;
	logic decoder_line_complete;
	wire  decoder_line_open      = !(line_start ? 1'b0 : decoder_line_complete) &&
	                               !decoded_line_done;
	wire  decoder_active_advance = ce_pix && !VGA_HBLANK_IN && !current_line_vblank &&
	                               decoder_line_open;
	wire  decoder_drain_advance  = ce_pix && VGA_HBLANK_IN && output_line.valid &&
	                               !output_line.vblank && decoder_line_open;
	wire  decoder_advance        = decoder_active_advance || decoder_drain_advance;

	always_ff @(posedge clk_sys) begin
		if (reset || line_start)
			decoder_line_complete <= 1'b0;
		else if (decoded_line_done)
			decoder_line_complete <= 1'b1;
	end

	vfb_rle_decoder decoder (
		.clk_sys(clk_sys),
		.reset(reset),
		.token_valid(decoder_token_valid),
		.token_ready(decoder_token_ready),
		.token_data(decoder_words[15:0]),
		.token_eol(decoder_token_eol),
		.advance(decoder_advance),
		.canonical_out(decoded_canonical),
		.pixel_valid(decoded_valid),
		.line_done(decoded_line_done),
		.underflow(decoder_underflow)
	);

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			CANONICAL_OUT  <= 14'd0;
			VGA_HS_OUT     <=  1'b1;
			VGA_VS_OUT     <=  1'b1;
			VGA_HBLANK_OUT <=  1'b1;
			VGA_VBLANK_OUT <=  1'b1;
		end else if (ce_pix) begin
			// Present the current decoded pixel before advancing the decoder.
			if (current_line_valid && !VGA_HBLANK_IN && !current_line_vblank && decoder_line_open) begin
				CANONICAL_OUT <= decoded_canonical;
			end else begin
				CANONICAL_OUT <= 14'd0;
			end
			VGA_HS_OUT     <= VGA_HS_IN;
			VGA_HBLANK_OUT <= VGA_HBLANK_IN;
			VGA_VS_OUT     <= current_line_vsync;
			VGA_VBLANK_OUT <= current_line_vblank;
		end
	end

	// Open-row SDRAM controller and read/write scheduler
	logic        mem_req_valid;
	logic        mem_req_write;
	logic [31:0] mem_req_addr;
	logic [31:0] mem_req_wdata;
	logic        mem_req_ready;
	logic        mem_rsp_valid;
	logic [31:0] mem_rsp_rdata;

	issue_packet_t issue;
	logic          issue_load;

	vfb_sdram_core #(
		.SDRAM_MHZ(SDRAM_MHZ)
	) sdram_controller (
		.clk_sys(clk_sys),
		.reset(reset),
		.req_valid(mem_req_valid),
		.req_write(mem_req_write),
		.req_addr(mem_req_addr),
		.req_wdata(mem_req_wdata),
		.req_be(4'hf),
		.req_ready(mem_req_ready),
		.rsp_valid(mem_rsp_valid),
		.rsp_rdata(mem_rsp_rdata),
		.init_done(init_done),
		.sdram_data_in(sdram_data_in),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(sdram_cke),
		.sdram_cs(sdram_cs),
		.sdram_ras(sdram_ras),
		.sdram_cas(sdram_cas),
		.sdram_we(sdram_we),
		.sdram_dqm(sdram_dqm),
		.sdram_addr(sdram_addr),
		.sdram_ba(sdram_ba)
	);

	wire [READ_FIFO_AW+1:0] read_reserved    = (READ_FIFO_AW + 2)'(read_fifo_used) +
	                                           (READ_FIFO_AW + 2)'(read_outstanding);
	wire                    read_available   = read_active &&
	                                           (read_issue_index < read_pair_count) &&
	                                           (read_reserved < READ_PAIR_FIFO_DEPTH - 2);
	wire                    write_available  = write_head.valid;
	wire                    read_more_after  = (read_issue_index + 1'b1 < read_pair_count) &&
	                                           (read_reserved + 1'b1 < READ_PAIR_FIFO_DEPTH - 2);
	wire                    write_more_after = write_head.valid || !write_fifo_empty;
	wire                    write_urgent     = (write_fifo_used >= WRITE_URGENT_LEVEL);
	wire                    read_urgent      = read_active && (read_reserved <= READ_URGENT_LEVEL);
	wire                    read_preferred   = read_available &&
	                                           (!write_available || read_urgent || !write_urgent);

	logic       arb_locked;
	logic       arb_read;
	logic [5:0] arb_remaining;
	logic       read_available_q;
	logic       write_available_q;
	logic       read_preferred_q;
	logic       read_more_after_q;
	logic       write_more_after_q;

	wire   arb_read_effective = (arb_locked && read_preferred_q) ? 1'b1 : arb_read;
	wire   selected_available = arb_read_effective ? read_available_q : write_available_q;
	assign mem_req_valid      = issue.valid;
	assign mem_req_write      = issue.write;
	assign mem_req_addr       = issue.addr;
	assign mem_req_wdata      = issue.wdata;

	assign issue_load = !issue.valid && init_done && arb_locked && selected_available;

	wire issue_accepted         = mem_req_ready && issue.valid;
	wire read_request_accepted  = issue_accepted && issue.read;
	wire write_request_accepted = issue_accepted && issue.write;
	// Queue another request of the same type while its quota remains, avoiding
	// an idle clock between accesses to the same row.
	wire            issue_chain_read   = read_request_accepted && (arb_remaining > 1) &&
	                                     read_more_after_q;
	wire            issue_chain_write  = write_request_accepted && (arb_remaining > 1) &&
	                                     write_head.valid;
	wire [PAIR_W:0] chained_read_index = read_issue_index + {{PAIR_W{1'b0}}, 1'b1};

	assign write_head_consume = (issue_load && !arb_read_effective) || issue_chain_write;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			read_available_q   <= 1'b0;
			write_available_q  <= 1'b0;
			read_preferred_q   <= 1'b0;
			read_more_after_q  <= 1'b0;
			write_more_after_q <= 1'b0;
		end else begin
			read_available_q   <= read_available;
			write_available_q  <= write_available;
			read_preferred_q   <= read_preferred;
			read_more_after_q  <= read_more_after;
			write_more_after_q <= write_more_after;
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			issue.valid      <=  1'b0;
			issue.read       <=  1'b0;
			issue.write      <=  1'b0;
			issue.addr       <= 32'd0;
			issue.wdata      <= 32'd0;
			issue.write_eol  <=  1'b0;
			issue.write_slot <=    '0;
		end else if (issue_chain_read) begin
			issue.valid <= 1'b1;
			issue.read  <= 1'b1;
			issue.write <= 1'b0;
			issue.addr  <= ({{(32-SLOT_W){1'b0}}, read_slot} << 13) +
			               ({{(32-PAIR_W){1'b0}}, chained_read_index[PAIR_W-1:0]} << 2);
		end else if (issue_chain_write) begin
			issue.valid      <= 1'b1;
			issue.read       <= 1'b0;
			issue.write      <= 1'b1;
			issue.write_eol  <= write_head.eol;
			issue.write_slot <= write_head.slot;
			issue.wdata      <= write_head.data;
			issue.addr       <= ({{(32-SLOT_W){1'b0}}, write_head.slot} << 13) +
			                    ({{(32-PAIR_W){1'b0}}, write_head.index} << 2);
		end else if (issue_accepted) begin
			issue.valid <= 1'b0;
		end else if (!issue.valid) begin
			issue.valid <= issue_load;
			issue.read  <= issue_load && arb_read_effective;
			issue.write <= issue_load && !arb_read_effective;
			if (issue_load) begin
				issue.write_eol  <= !arb_read_effective && write_head.eol;
				issue.write_slot <= write_head.slot;
				issue.wdata      <= write_head.data;
				if (arb_read_effective)
					issue.addr <= ({{(32-SLOT_W){1'b0}}, read_slot} << 13) +
					              ({{(32-PAIR_W){1'b0}}, read_issue_index[PAIR_W-1:0]} << 2);
				else
					issue.addr <= ({{(32-SLOT_W){1'b0}}, write_head.slot} << 13) +
					              ({{(32-PAIR_W){1'b0}}, write_head.index} << 2);
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			arb_locked    <= 1'b0;
			arb_read      <= 1'b0;
			arb_remaining <= ARB_QUOTA;
		end else if (!arb_locked) begin
			if (read_available_q || write_available_q) begin
				arb_locked    <= 1'b1;
				arb_read      <= read_preferred_q;
				arb_remaining <= ARB_QUOTA;
			end
		end else if (!selected_available) begin
			arb_locked <= 1'b0;
		end else if (issue_accepted) begin
			if (arb_remaining > 1 && (arb_read_effective ? read_more_after_q : write_more_after_q)) begin
				arb_remaining <= arb_remaining - 1'b1;
				arb_read      <= arb_read_effective;
			end else if (arb_read_effective && write_available_q && !read_preferred_q) begin
				arb_read      <= 1'b0;
				arb_remaining <= ARB_QUOTA;
			end else if (!arb_read_effective && read_available_q && read_preferred_q) begin
				arb_read      <= 1'b1;
				arb_remaining <= ARB_QUOTA;
			end else if (arb_read_effective ? read_more_after_q : write_more_after_q) begin
				arb_read      <= arb_read_effective;
				arb_remaining <= ARB_QUOTA;
			end else begin
				arb_locked <= 1'b0;
			end
		end
	end

	// Every requested pair contains a low word. Only the final high word can
	// be padding when a line contains an odd number of RLE words.
	wire read_response_last = (read_response_remaining == 1);
	wire read_high_real     = mem_rsp_valid && (!read_response_last || !read_words_odd);

	assign read_fifo_push       = mem_rsp_valid && !read_fifo_full;
	assign read_fifo_write_data = {read_response_last, read_high_real, mem_rsp_rdata};

	integer slot_i;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			line_had_pixels           <=  1'b0;
			line_vsync                <=  1'b1;
			line_vblank               <=  1'b1;
			line_sequence             <= 16'd0;
			delay_warmed_r            <=  1'b0;
			encode_slot               <=    '0;
			encode_word_index         <=    '0;
			pack_pending.valid        <=  1'b0;
			pack_pending.word         <= 16'd0;
			pack_pending.pair_index   <=    '0;
			pack_pending.slot         <=    '0;
			finalize.pending          <=  1'b0;
			finalize.slot             <=    '0;
			finalize.vsync            <=  1'b1;
			finalize.vblank           <=  1'b1;
			blank_finalize.pending    <=  1'b0;
			blank_finalize.slot       <=    '0;
			blank_finalize.vsync      <=  1'b1;
			blank_finalize.vblank     <=  1'b1;
			descriptor_lookup.pending <=  1'b0;
			descriptor_lookup.warmed  <=  1'b0;
			descriptor_lookup.slot    <=    '0;
			descriptor_apply.pending  <=  1'b0;
			descriptor_apply.warmed   <=  1'b0;
			descriptor_apply.slot     <=    '0;
			descriptor_apply.words    <=    '0;
			descriptor_apply.vsync    <=  1'b1;
			descriptor_apply.vblank   <=  1'b1;
			descriptor_apply.valid    <=  1'b0;
			descriptor_apply.written  <=  1'b0;
			prefetch_line             <= '{valid: 1'b0, vsync: 1'b1, vblank: 1'b1};
			pending_line              <= '{valid: 1'b0, vsync: 1'b1, vblank: 1'b1};
			output_line               <= '{valid: 1'b0, vsync: 1'b1, vblank: 1'b1};
			read_active               <= 1'b0;
			read_slot                 <=   '0;
			read_pair_count           <=   '0;
			read_issue_index          <=   '0;
			read_response_remaining   <=   '0;
			read_words_odd            <= 1'b0;
			read_outstanding          <=   '0;
			read_desc_wr_ptr          <=   '0;
			read_desc_rd_ptr          <=   '0;
			read_desc_used            <=   '0;
			overflow                  <= 1'b0;
			underflow                 <= 1'b0;
			for (slot_i = 0; slot_i < SLOT_COUNT; slot_i = slot_i + 1) begin
				descriptor_words[slot_i]   <=   '0;
				descriptor_vsync[slot_i]   <= 1'b1;
				descriptor_vblank[slot_i]  <= 1'b1;
				descriptor_valid[slot_i]   <= 1'b0;
				descriptor_written[slot_i] <= 1'b0;
			end
		end else begin
			// Register an empty-line descriptor one cycle after detection.
			if (blank_finalize.pending) begin
				descriptor_words[blank_finalize.slot]   <= '0;
				descriptor_vsync[blank_finalize.slot]   <= blank_finalize.vsync;
				descriptor_vblank[blank_finalize.slot]  <= blank_finalize.vblank;
				descriptor_valid[blank_finalize.slot]   <= 1'b1;
				descriptor_written[blank_finalize.slot] <= 1'b1;
				blank_finalize.pending                  <= 1'b0;
				encode_slot                             <= blank_finalize.slot + 1'b1;
				encode_word_index                       <=   '0;
				pack_pending.valid                      <= 1'b0;
			end

			if (line_start) begin
				line_had_pixels <= 1'b0;
				line_vsync      <= VGA_VS_IN;
				line_vblank     <= VGA_VBLANK_IN;
				output_line     <= pending_line;
				pending_line    <= prefetch_line;
				prefetch_line   <= '{valid: 1'b0, vsync: 1'b1, vblank: 1'b1};
			end

			if (active_pixel) line_had_pixels <= 1'b1;

			if (enc_packet_accept) begin
				if ((encoded_words_after_packet > MAX_WORDS) ||
				    ((encoded_words_after_packet == MAX_WORDS) &&
				     !enc_token_eol))
					overflow <= 1'b1;

				if (pack_pending.valid || enc_token_eol) begin
					pack_pending.valid <= 1'b0;
				end else begin
					pack_pending.valid      <= 1'b1;
					pack_pending.word       <= enc_token_data;
					pack_pending.pair_index <= encode_word_index[WORD_W-1:1];
					pack_pending.slot       <= encode_slot;
				end

				if (enc_token_eol) begin
					descriptor_words[finalize.slot]   <= encoded_words_after_packet;
					descriptor_vsync[finalize.slot]   <= finalize.vsync;
					descriptor_vblank[finalize.slot]  <= finalize.vblank;
					descriptor_valid[finalize.slot]   <= 1'b1;
					descriptor_written[finalize.slot] <= 1'b0;
					finalize.pending                  <= 1'b0;
					encode_slot                       <= encode_slot + 1'b1;
					encode_word_index                 <= '0;
				end else begin
					encode_word_index <= encoded_words_after_packet[WORD_W-1:0];
				end
			end

			if (write_request_accepted && issue.write_eol)
				descriptor_written[issue.write_slot] <= 1'b1;

			if (descriptor_lookup.pending) begin
				descriptor_lookup.pending <= 1'b0;
				descriptor_apply.pending  <= 1'b1;
				descriptor_apply.warmed   <= descriptor_lookup.warmed;
				descriptor_apply.slot     <= descriptor_lookup.slot;
				descriptor_apply.words    <= descriptor_words[descriptor_lookup.slot];
				descriptor_apply.vsync    <= descriptor_vsync[descriptor_lookup.slot];
				descriptor_apply.vblank   <= descriptor_vblank[descriptor_lookup.slot];
				descriptor_apply.valid    <= descriptor_valid[descriptor_lookup.slot];
				descriptor_apply.written  <= descriptor_written[descriptor_lookup.slot];
			end

			if (descriptor_apply.pending) begin
				descriptor_apply.pending <= 1'b0;
				if (descriptor_apply.warmed && descriptor_apply.valid && descriptor_apply.written) begin
					prefetch_line.valid  <= 1'b1;
					prefetch_line.vsync  <= descriptor_apply.vsync;
					prefetch_line.vblank <= descriptor_apply.vblank;
				end else if (descriptor_apply.warmed) begin
					prefetch_line <= '{valid: 1'b0, vsync: 1'b1, vblank: 1'b1};
					underflow     <= 1'b1;
				end
			end

			if (read_desc_push) begin
				read_desc_slot[read_desc_wr_ptr]  <= descriptor_apply.slot;
				read_desc_words[read_desc_wr_ptr] <= descriptor_apply.words;
				read_desc_wr_ptr                  <= read_desc_wr_ptr + 1'b1;
			end
			if (read_desc_pop) read_desc_rd_ptr <= read_desc_rd_ptr + 1'b1;
			case ({read_desc_push, read_desc_pop})
				2'b10:   read_desc_used <= read_desc_used + 1'b1;
				2'b01:   read_desc_used <= read_desc_used - 1'b1;
				default: read_desc_used <= read_desc_used;
			endcase
			if (read_desc_overflow) underflow <= 1'b1;

			if (read_start) begin
				read_slot               <= read_start_slot;
				read_pair_count         <= read_start_pairs;
				read_issue_index        <= '0;
				read_response_remaining <= read_start_pairs;
				read_words_odd          <= read_start_words[0];
				read_active             <= 1'b1;
			end

			if (line_end) begin
				line_sequence  <= line_sequence + 1'b1;
				delay_warmed_r <= delay_warmed;

				if (line_had_pixels) begin
					finalize.pending <= 1'b1;
					finalize.slot    <= encode_slot;
					finalize.vsync   <= line_vsync;
					finalize.vblank  <= line_vblank;
				end else begin
					blank_finalize.pending <= 1'b1;
					blank_finalize.slot    <= encode_slot;
					blank_finalize.vsync   <= line_vsync;
					blank_finalize.vblank  <= line_vblank;
				end

				descriptor_lookup.pending <= 1'b1;
				descriptor_lookup.warmed  <= delay_warmed;
				descriptor_lookup.slot    <= delayed_slot;
			end

			if (read_request_accepted) read_issue_index <= read_issue_index + 1'b1;

			case ({read_request_accepted, mem_rsp_valid})
				2'b10:   read_outstanding <= read_outstanding + 1'b1;
				2'b01:   read_outstanding <= read_outstanding - 1'b1;
				default: read_outstanding <= read_outstanding;
			endcase

			if (mem_rsp_valid) begin
				if (read_fifo_full) overflow <= 1'b1;
				read_response_remaining <= read_response_remaining - 1'b1;
				if (read_response_last) read_active <= 1'b0;
			end

			if (enc_overflow)                           overflow  <= 1'b1;
			if (decoder_underflow && output_line.valid) underflow <= 1'b1;
			if (finalize.pending && line_start)         overflow  <= 1'b1;
			if (blank_finalize.pending && line_end)     overflow  <= 1'b1;
		end
	end

endmodule

`default_nettype wire

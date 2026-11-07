// Aztarac Z80 / four AY-3-8910 sound board.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

module aztarac_audio (
	input  wire               clk,
	input  wire               reset,
	input  wire               pause,
	input  wire         [1:0] lowpass,
	input  wire               rom_wr,
	input  wire        [12:0] rom_addr,
	input  wire         [7:0] rom_data,
	input  wire         [7:0] command,
	input  wire               command_wr,
	output wire         [7:0] status,
	output wire signed [15:0] audio
);

	logic [4:0]  clock_div;
	logic [18:0] timer_count;
	wire         ce         = !pause && clock_div == 5'd24;
	wire         timer_tick = !pause && timer_count == 19'd499999;
	always_ff @(posedge clk) begin
		if (reset) begin
			clock_div   <=  5'd0;
			timer_count <= 19'd0;
		end else if (!pause) begin
			clock_div   <= ce ? 5'd0 : clock_div + 5'd1;
			timer_count <= timer_tick ? 19'd0 : timer_count + 19'd1;
		end
	end

	wire  [15:0] cpu_addr;
	wire  [7:0]  cpu_dout;
	logic [7:0]  cpu_din;
	wire         cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_m1_n;
	logic        irq_pending;
	T80s #(.Mode(0), .T2Write(1), .IOWait(1)) cpu (
		.CLK(clk), .CEN(ce), .RESET_n(~reset), .WAIT_n(1'b1),
		.INT_n(~irq_pending), .NMI_n(1'b1), .BUSRQ_n(1'b1),
		.A(cpu_addr), .DI(cpu_din), .DO(cpu_dout), .OUT0(1'b0),
		.MREQ_n(cpu_mreq_n), .IORQ_n(cpu_iorq_n),
		.RD_n(cpu_rd_n), .WR_n(cpu_wr_n), .M1_n(cpu_m1_n),
		.RFSH_n(), .HALT_n(), .BUSAK_n()
	);

	logic [7:0] rom [0:8191];
	logic [7:0] ram [0:2047];
	logic [7:0] rom_q, ram_q;
	wire        select_ram = cpu_addr[15:11] == 5'b10000;
	wire        select_psg = cpu_addr[15:3] == 13'h1180;
	wire        bus_active = !cpu_mreq_n && (!cpu_rd_n || !cpu_wr_n);
	logic       bus_seen;
	wire        bus_read  = !pause && bus_active && !bus_seen && !cpu_rd_n;
	wire        bus_write = !pause && bus_active && !bus_seen && !cpu_wr_n;
	always_ff @(posedge clk) begin
		if (rom_wr) rom[rom_addr] <= rom_data;
		rom_q <= rom[cpu_addr[12:0]];
		ram_q <= ram[cpu_addr[10:0]];
		if (!reset && bus_write && select_ram) ram[cpu_addr[10:0]] <= cpu_dout;
		if (reset) bus_seen <= 1'b0;
		else if (!bus_active) bus_seen <= 1'b0;
		else if (!pause) bus_seen <= 1'b1;
	end

	logic [7:0] command_latch;
	logic [7:0] sound_status, sound_status_d;
	logic       irq_pending_d;
	wire        command_read = bus_read && cpu_addr == 16'h8800;
	wire        timer_ack    = bus_write && cpu_addr == 16'h9000;
	wire        irq_ack      = !cpu_iorq_n && !cpu_m1_n && ce;

	// The 68000 sees only the command handshake bit. The Z80 sees the two
	// interrupt-source bits. New requests win over simultaneous acknowledgments.
	assign status = {7'd0, sound_status[0]};
	always_comb begin
		sound_status_d = sound_status;
		irq_pending_d  = irq_pending;
		if (irq_ack) irq_pending_d = 1'b0;
		if (command_read) begin
			sound_status_d[0] = 1'b1;
			sound_status_d[5] = 1'b0;
		end
		if (timer_ack) sound_status_d[4] = 1'b0;
		if (command_wr && !pause) begin
			sound_status_d = sound_status_d ^ 8'h21;
			if (sound_status_d[5]) irq_pending_d = 1'b1;
		end
		if (timer_tick) begin
			sound_status_d[4] = ~sound_status_d[4];
			if (sound_status_d[4]) irq_pending_d = 1'b1;
		end
	end
	always_ff @(posedge clk) begin
		if (reset) begin
			command_latch <= 8'd0;
			sound_status  <= 8'd0;
			irq_pending   <= 1'b0;
		end else begin
			sound_status <= sound_status_d;
			irq_pending  <= irq_pending_d;
			if (command_wr && !pause) command_latch <= command;
		end
	end

	wire   [7:0] psg_data [0:3];
	wire   [9:0] psg_sound [0:3];
	wire   [7:0] psg_c [0:3];
	genvar       chip;
	generate for (chip = 0; chip < 4; chip = chip + 1) begin : ay
		logic  [3:0] address;
		logic        address_valid;
		wire   [7:0] data_read;
		assign       psg_data[chip] = address_valid ? data_read : 8'hff;
		wire         selected       = select_psg && cpu_addr[2:1] == chip;
		wire         data_write     = bus_write && selected && !cpu_addr[0] && address_valid;
		always_ff @(posedge clk) begin
			if (reset) begin
				address       <= 4'd0;
				address_valid <= 1'b0;
			end else if (bus_write && selected && cpu_addr[0]) begin
				address       <= cpu_dout[3:0];
				address_valid <= cpu_dout[7:4] == 4'd0;
			end
		end
		jt49 psg (
			.clk(clk), .clk_en(ce), .rst_n(~reset), .sel(1'b1),
			.addr(address), .cs_n(~address_valid), .wr_n(~data_write), .din(cpu_dout),
			.dout(data_read), .sound(psg_sound[chip]), .A(), .B(), .C(psg_c[chip]), .sample(),
			.IOA_in(8'hff), .IOB_in(8'hff), .IOA_out(), .IOB_out(), .IOA_oe(), .IOB_oe()
		);
	end endgenerate

	always_comb begin
		cpu_din = 8'hff;
		if (cpu_addr[15:13] == 3'd0) cpu_din = rom_q;
		else if (select_ram) cpu_din = ram_q;
		else if (cpu_addr == 16'h8800) cpu_din = command_latch;
		else if (select_psg) cpu_din = psg_data[cpu_addr[2:1]];
		else if (cpu_addr == 16'h9000) cpu_din = sound_status & 8'hfe;
		if (!cpu_iorq_n) cpu_din = 8'hff;
	end

	// JT49 publishes C one enable before its combined sample. Delay C to
	// subtract the matching voice, leaving only A+B on the bass-filter path.
	logic [7:0] ay1_c;
	always_ff @(posedge clk) begin
		if (reset) ay1_c <= 8'd0;
		else if (ce) ay1_c <= psg_c[0];
	end
	wire        [9:0]  bass_voices  = psg_sound[0] - {2'd0, ay1_c};
	wire        [11:0] other_voices = {2'd0, psg_sound[1]} + {2'd0, psg_sound[2]} +
	                                  {2'd0, psg_sound[3]} + {4'd0, ay1_c};
	wire signed [15:0] audio_filtered;
	aztarac_audio_filter filter (
		.clk   (clk),
		.ce    (ce),
		.reset (reset),
		.ay1   (bass_voices),
		.others(other_voices),
		.audio (audio_filtered)
	);
	wire signed [15:0] audio_lowpass;
	aztarac_audio_lowpass cabinet_filter (
		.clk(clk), .ce(ce), .reset(reset), .mode(lowpass),
		.sample(audio_filtered), .audio(audio_lowpass)
	);
	assign audio = (reset || pause) ? 16'sd0 : audio_lowpass;

endmodule

// CPU/sound-board schematic 905-4902 sheet 7: AY1 A+B have a 16k/33nF
// Sallen-Key lowpass before the common summing amplifier. Node integration
// runs at 2 MHz; the 4.7k/1nF amplifier poles use matched-Z coefficients.
module aztarac_audio_filter (
	input  wire               clk,
	input  wire               ce,
	input  wire               reset,
	input  wire        [9:0]  ay1,
	input  wire        [11:0] others,
	output wire signed [15:0] audio
);
	wire  signed [31:0] ay1_q16    = $signed({3'd0, ay1, 19'd0});
	wire  signed [31:0] others_q16 = $signed({1'b0, others, 19'd0});
	logic signed [31:0] input_q16, node1_q16, node2_q16, output_q16, mix_q16, dc_q16;
	wire  signed [31:0] input_delta  = ay1_q16 - input_q16;
	wire  signed [31:0] node_delta   = node1_q16 - node2_q16;
	wire  signed [49:0] gain_product = node2_q16 * 18'sd102505;
	(* dont_retime *) logic signed [31:0] gain_q16, mix_delta;
	wire  signed [31:0] output_delta = gain_q16 - output_q16;
	wire  signed [49:0] input_step   = input_delta * 18'sd105822;
	wire  signed [49:0] node1_step   = input_q16 * 12'sd993 - node1_q16 * 12'sd433 -
	                                   node2_q16 * 12'sd560;
	wire  signed [43:0] node2_step   = node_delta * 12'sd993;
	wire  signed [49:0] output_step  = output_delta * 18'sd105822;
	wire  signed [49:0] mix_step     = mix_delta * 18'sd105822;
	wire  signed [31:0] ac_q16       = mix_q16 - dc_q16;
	// PSG outputs and filter state change only on ce, at least 25 clocks apart.
	// Prepare the gain and mix between those original state-update edges.
	always_ff @(posedge clk) begin
		if (reset) begin
			gain_q16  <= 0;
			mix_delta <= 0;
		end else begin
			gain_q16  <= 32'(gain_product >>> 16);
			mix_delta <= others_q16 + output_q16 - mix_q16;
		end
	end
	always_ff @(posedge clk) begin
		if (reset) begin
			input_q16  <= 0;
			node1_q16  <= 0;
			node2_q16  <= 0;
			output_q16 <= 0;
			mix_q16    <= 0;
			dc_q16     <= 0;
		end else if (ce) begin
			input_q16  <= 32'(input_q16 + (input_step >>> 20));
			node1_q16  <= 32'(node1_q16 + (node1_step >>> 20));
			node2_q16  <= 32'(node2_q16 + (node2_step >>> 20));
			output_q16 <= 32'(output_q16 + (output_step >>> 20));
			mix_q16    <= 32'(mix_q16 + (mix_step >>> 20));
			dc_q16     <= dc_q16 + (ac_q16 >>> 15);
		end
	end
	// Apply 2.5x gain after DC removal, retaining Q16 precision until conversion.
	// Widen before multiplying and saturate the signed PCM output without wrap.
	wire   signed [34:0] pcm_product = ac_q16 * 4'sd5;
	wire   signed [17:0] pcm_scaled  = pcm_product[34:17];
	assign               audio       = pcm_scaled > 18'sd32767 ? 16'sh7fff :
	                                   pcm_scaled < -18'sd32768 ? 16'sh8000 : pcm_scaled[15:0];
endmodule

// Optional single-pole cabinet low-pass after the complete, unchanged mix.
// At the 2 MHz enable, alpha = round((1-exp(-2*pi*fc/2000000))*2^20).
// Keep the state warm in bypass; pause holds it by stopping ce.
module aztarac_audio_lowpass (
	input  wire               clk,
	input  wire               ce,
	input  wire               reset,
	input  wire         [1:0] mode,
	input  wire signed [15:0] sample,
	output wire signed [15:0] audio
);
	logic signed [15:0] coefficient;
	always_comb begin
		case (mode)
			2'd1:    coefficient = 16'sd13094;  // 4 kHz
			2'd3:    coefficient = 16'sd26025;  // 8 kHz
			default: coefficient = 16'sd19580;  // 6 kHz, including bypass tracking
		endcase
	end

	logic signed [31:0] state_q16;
	(* dont_retime *) logic signed [32:0] delta_q16;
	(* dont_retime *) logic signed [48:0] step_product;
	wire signed [31:0] step_q16 = {{3{step_product[48]}}, step_product[48:20]};
	wire signed [32:0] rounded  = {state_q16[31], state_q16} + 33'sd32768;
	// Each input/state is stable between enables, at least 25 clocks apart.
	// Prepare the subtraction and product before the enabled feedback update.
	always_ff @(posedge clk) begin
		if (reset) begin
			state_q16    <= 32'sd0;
			delta_q16    <= 33'sd0;
			step_product <= 49'sd0;
		end else begin
			delta_q16    <= $signed({sample[15], sample, 16'd0}) -
			                $signed({state_q16[31], state_q16});
			step_product <= delta_q16 * coefficient;
			if (ce) state_q16 <= state_q16 + step_q16;
		end
	end
	assign audio = mode == 2'd0 ? sample : rounded[31:16];
endmodule

`default_nettype wire

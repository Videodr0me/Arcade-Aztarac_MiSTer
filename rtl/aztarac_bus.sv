// SPDX-License-Identifier: GPL-3.0-or-later
// Written 2026 by Videodr0me
// Separate bus boundary permits directed byte-lane and peripheral verification.
`default_nettype none

module aztarac_bus (
	input  wire                clk, reset, pause,
	input  wire         [23:1] cpu_addr,
	input  wire         [15:0] cpu_dout,
	output logic        [15:0] cpu_din,
	input  wire                cpu_as_n, cpu_rw, cpu_uds_n, cpu_lds_n,
	output logic               cpu_dtack_n,
	output logic               irq4, watchdog_reset,
	input  wire                rom_wr,
	input  wire         [15:0] rom_addr,
	input  wire         [7:0]  rom_data,
	input  wire         [7:0]  inputs,
	input  wire  signed [7:0]  joystick_x, joystick_y,
	input  wire         [7:0]  spinner,
	output logic        [7:0]  sound_command,
	output logic               sound_command_wr,
	input  wire         [7:0]  sound_status,
	input  wire         [7:0]  nvram_addr,
	input  wire         [3:0]  nvram_din,
	input  wire                nvram_wr,
	output logic        [3:0]  nvram_dout,
	output logic               nvram_store,
	input  wire         [10:0] vector_addr,
	output logic        [15:0] vector_c,
	output logic        [9:0]  vector_x, vector_y,
	output logic               vector_start,
	output logic        [7:0]  brightness
);
	(* ramstyle = "M10K" *) logic [7:0] rom_hi[0:24575], rom_lo[0:24575];
	(* ramstyle = "M10K" *) logic [7:0] ram_hi[0:4095], ram_lo[0:4095];
	(* ramstyle = "M10K" *) logic [7:0] c_hi[0:2047], c_lo[0:2047];
	(* ramstyle = "M10K" *) logic [7:0] x_hi[0:2047], x_lo[0:2047];
	(* ramstyle = "M10K" *) logic [7:0] y_hi[0:2047], y_lo[0:2047];
	// Functional UBR-time image: preserve a word before its first later write.
	(* ramstyle = "M10K" *) logic [15:0] c_saved[0:2047], x_saved[0:2047], y_saved[0:2047];
	logic        snapshot_active;
	wire         c_saved_cpu, x_saved_cpu, y_saved_cpu;
	wire  [2:0]  vector_saved_q;
	logic [2:0]  vector_forward_valid_q;
	logic [15:0] vector_forward_data_q;
	logic [15:0] vector_c_live_q, vector_c_saved_q;
	logic [9:0]  vector_x_live_q, vector_y_live_q, vector_x_saved_q, vector_y_saved_q;
	logic [3:0]  nvram[0:255], eeprom[0:255];
	initial begin
		for (integer i = 0; i < 256; i = i + 1) begin
			nvram[i]  = 4'hf;
			eeprom[i] = 4'hf;
		end
	end
	logic [15:0] rom_q, ram_q, c_q, x_q, y_q, read_data;
	logic        pending, serviced;
	wire         cycle          = !cpu_as_n && (!cpu_uds_n || !cpu_lds_n);
	wire         accept         = cycle && pending && !serviced && !reset && !pause;
	wire         write_cycle    = accept && !cpu_rw;
	wire         write_low      = write_cycle && !cpu_lds_n;
	wire         cs_rom         = cpu_addr[23:16] == 0 && cpu_addr[15:1] < 15'h6000;
	wire         cs_ram         = cpu_addr[23:13] == 11'h7ff;
	wire         cs_vector      = cpu_addr[23:14] == 10'h3fe && cpu_addr[13:12] != 2'b11;
	wire         cs_nvram       = cpu_addr[23:9] == 15'h0110;
	wire         cs_store       = cpu_addr == (24'h021000 >> 1);
	wire         cs_joystick    = cpu_addr == (24'h027000 >> 1);
	wire         cs_inputs      = cpu_addr == (24'h027004 >> 1);
	wire         cs_sound       = cpu_addr == (24'h027008 >> 1);
	wire         cs_spinner     = cpu_addr == (24'h02700c >> 1);
	wire         cs_watchdog    = cpu_addr == (24'h02700e >> 1);
	wire         cs_ubr         = cpu_addr == (24'hffb000 >> 1);
	wire         watchdog_clear = accept && cpu_rw && cs_watchdog;
	wire         start_list     = write_low && cs_ubr;
	wire         snapshot_clear = reset || (start_list && cpu_dout[7:0] != 0);
	wire         save_c         = snapshot_active && write_cycle && cs_vector &&
	                              cpu_addr[13:12] == 0 && !c_saved_cpu;
	wire         save_x         = snapshot_active && write_cycle && cs_vector &&
	                              cpu_addr[13:12] == 1 && !x_saved_cpu;
	wire         save_y         = snapshot_active && write_cycle && cs_vector &&
	                              cpu_addr[13:12] == 2 && !y_saved_cpu;
	aztarac_snapshot_valid valid_c (.clk(clk), .clear(snapshot_clear), .save(save_c),
		.cpu_addr(cpu_addr[11:1]), .vector_addr(vector_addr), .cpu_saved(c_saved_cpu), .vector_saved(vector_saved_q[0]));
	aztarac_snapshot_valid valid_x (.clk(clk), .clear(snapshot_clear), .save(save_x),
		.cpu_addr(cpu_addr[11:1]), .vector_addr(vector_addr), .cpu_saved(x_saved_cpu), .vector_saved(vector_saved_q[1]));
	aztarac_snapshot_valid valid_y (.clk(clk), .clear(snapshot_clear), .save(save_y),
		.cpu_addr(cpu_addr[11:1]), .vector_addr(vector_addr), .cpu_saved(y_saved_cpu), .vector_saved(vector_saved_q[2]));

	always_ff @(posedge clk) begin
		if (rom_wr && rom_addr < 16'hc000) begin
			if (rom_addr[0]) rom_lo[rom_addr[15:1]] <= rom_data;
			else rom_hi[rom_addr[15:1]] <= rom_data;
		end
		rom_q            <= {rom_hi[cpu_addr[15:1]],rom_lo[cpu_addr[15:1]]};
		ram_q            <= {ram_hi[cpu_addr[12:1]],ram_lo[cpu_addr[12:1]]};
		c_q              <= {c_hi[cpu_addr[11:1]],c_lo[cpu_addr[11:1]]};
		x_q              <= {x_hi[cpu_addr[11:1]],x_lo[cpu_addr[11:1]]};
		y_q              <= {y_hi[cpu_addr[11:1]],y_lo[cpu_addr[11:1]]};
		vector_c_live_q  <= {c_hi[vector_addr],c_lo[vector_addr]};
		vector_x_live_q  <= {x_hi[vector_addr][1:0],x_lo[vector_addr]};
		vector_y_live_q  <= {y_hi[vector_addr][1:0],y_lo[vector_addr]};
		vector_c_saved_q <= c_saved[vector_addr];
		vector_x_saved_q <= x_saved[vector_addr][9:0];
		vector_y_saved_q <= y_saved[vector_addr][9:0];
		// Do not depend on mixed-port RAM read-during-write behavior.
		vector_forward_valid_q <= cpu_addr[11:1] == vector_addr ? {save_y,save_x,save_c} : 3'b000;
		vector_forward_data_q  <= read_data;
		if (write_cycle && cs_ram) begin
			if (!cpu_uds_n) ram_hi[cpu_addr[12:1]] <= cpu_dout[15:8];
			if (!cpu_lds_n) ram_lo[cpu_addr[12:1]] <= cpu_dout[7:0];
		end
		if (write_cycle && cs_vector) begin
			case (cpu_addr[13:12])
				0:       begin
					if (!cpu_uds_n) c_hi[cpu_addr[11:1]] <= cpu_dout[15:8];
					if (!cpu_lds_n) c_lo[cpu_addr[11:1]] <= cpu_dout[7:0];
				end
				1:       begin
					if (!cpu_uds_n) x_hi[cpu_addr[11:1]] <= cpu_dout[15:8];
					if (!cpu_lds_n) x_lo[cpu_addr[11:1]] <= cpu_dout[7:0];
				end
				2:       begin
					if (!cpu_uds_n) y_hi[cpu_addr[11:1]] <= cpu_dout[15:8];
					if (!cpu_lds_n) y_lo[cpu_addr[11:1]] <= cpu_dout[7:0];
				end
				default: ;
			endcase
		end
	end
	assign vector_c = vector_saved_q[0] ? vector_c_saved_q :
	                  vector_forward_valid_q[0] ? vector_forward_data_q : vector_c_live_q;
	assign vector_x = vector_saved_q[1] ? vector_x_saved_q :
	                  vector_forward_valid_q[1] ? vector_forward_data_q[9:0] : vector_x_live_q;
	assign vector_y = vector_saved_q[2] ? vector_y_saved_q :
	                  vector_forward_valid_q[2] ? vector_forward_data_q[9:0] : vector_y_live_q;

	always_ff @(posedge clk) begin
		if (snapshot_clear) begin
			snapshot_active <= !reset;
		end else begin
			if (save_c) begin
				c_saved[cpu_addr[11:1]] <= c_q;
			end
			if (save_x) begin
				x_saved[cpu_addr[11:1]] <= x_q;
			end
			if (save_y) begin
				y_saved[cpu_addr[11:1]] <= y_q;
			end
		end
	end

	always @(posedge clk) begin
		nvram_dout  <= eeprom[nvram_addr];
		nvram_store <= 1'b0;
		if (reset) begin
			for (integer i = 0; i < 256; i = i + 1) nvram[i] <= eeprom[i];
		end else begin
			if (write_low && cs_nvram) nvram[cpu_addr[8:1]] <= cpu_dout[3:0];
			if (write_cycle && cs_store) begin
				for (integer i = 0; i < 256; i = i + 1) eeprom[i] <= nvram[i];
				nvram_store <= 1'b1;
			end
		end
		if (nvram_wr) begin
			eeprom[nvram_addr] <= nvram_din;
			nvram[nvram_addr]  <= nvram_din;
		end
	end

	always_comb begin
		read_data = 16'hffff;
		if (cs_rom) read_data = rom_q;
		else if (cs_ram) read_data = ram_q;
		else if (cs_vector) begin
			case (cpu_addr[13:12])
				0:       read_data = c_q;
				1:       read_data = x_q;
				2:       read_data = y_q;
				default: read_data = 16'hffff;
			endcase
		end else if (cs_nvram) read_data = {12'hfff,nvram[cpu_addr[8:1]]};
		else if (cs_joystick) read_data = {joystick_x,joystick_y};
		else if (cs_inputs) read_data = {8'd0,inputs};
		else if (cs_sound) read_data = {8'hff,7'd0,sound_status[0]};
		else if (cs_spinner) read_data = {8'd0,spinner};
	end

	always_ff @(posedge clk) begin
		sound_command_wr <= 1'b0;
		vector_start     <= 1'b0;
		if (reset) begin
			pending       <=     1'b0;
			serviced      <=     1'b0;
			cpu_dtack_n   <=     1'b1;
			cpu_din       <= 16'hffff;
			sound_command <=     8'd0;
			brightness    <=     8'd0;
		end else if (cpu_as_n) begin
			pending     <= 1'b0;
			serviced    <= 1'b0;
			cpu_dtack_n <= 1'b1;
		end else if (!pause) begin
			if (cycle) pending <= 1'b1;
			if (accept) begin
				serviced    <= 1'b1;
				cpu_dtack_n <= 1'b0;
				cpu_din     <= read_data;
				if (write_low && cs_sound) begin
					sound_command    <= cpu_dout[7:0];
					sound_command_wr <= 1'b1;
				end
				if (start_list) begin
					brightness   <= cpu_dout[7:0];
					vector_start <= 1'b1;
				end
			end
		end
	end

	logic [20:0] frame_counter;
	logic [7:0]  watchdog_frames;
	// 50 MHz / 1,111,111 = 45.0000045 Hz.
	wire         frame_tick = frame_counter == 21'd1111110;
	always_ff @(posedge clk) begin
		watchdog_reset <= 1'b0;
		if (reset) begin
			frame_counter   <= 21'd0;
			watchdog_frames <=  8'd0;
			irq4            <=  1'b0;
		end else if (!pause) begin
			if (frame_tick) begin
				frame_counter <= 21'd0;
				irq4          <=  1'b1;
				if (watchdog_frames == 8'd134) watchdog_reset <= 1'b1;
				else watchdog_frames <= watchdog_frames + 1'b1;
			end else frame_counter <= frame_counter + 1'b1;
			if (watchdog_clear) watchdog_frames <= 8'd0;
			if (start_list)     irq4            <= 1'b0;
		end
	end
endmodule

`default_nettype wire

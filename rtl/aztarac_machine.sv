// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Videodr0me
// Centuri Aztarac board. Functional address/IRQ reference: MAME (BSD-3-Clause).
`default_nettype none

module aztarac_machine (
	input  wire                clk,
	input  wire                reset,
	input  wire                pause,
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
	output logic               vector_valid,
	output logic signed [11:0] vector_x0, vector_y0, vector_x1, vector_y1,
	output logic        [5:0]  vector_color,
	output logic        [7:0]  vector_intensity,
	output logic               frame_done,
	output logic               vector_fault,
	output logic               cpu_halted,
	output logic               watchdog_reset
);
	logic [5:0] phase_acc;
	logic       phase;
	wire  [6:0] phase_sum = {1'b0,phase_acc} + 7'd16;
	wire        phase_ce  = !pause && phase_sum >= 7'd50;
	wire        phi1      = phase_ce && !phase;
	wire        phi2      = phase_ce && phase;
	logic [7:0] reset_count;
	wire        machine_reset = reset || (reset_count != 0);
	always_ff @(posedge clk) begin
		if (reset || watchdog_reset) reset_count <= 8'd128;
		else if (reset_count != 0) reset_count <= reset_count - 1'b1;
		if (reset) begin phase_acc <= 6'd0; phase <= 1'b0; end
		else if (!pause) begin
			phase_acc <= phase_ce ? 6'(phase_sum - 7'd50) : phase_sum[5:0];
			if (phase_ce) phase <= !phase;
		end
	end
	wire   [23:1] cpu_addr;
	wire   [15:0] cpu_dout, cpu_din;
	wire          cpu_as_n, cpu_rw, cpu_uds_n, cpu_lds_n, cpu_dtack_n;
	wire   [2:0]  cpu_fc;
	wire          irq4;
	wire          halted_n;
	assign        cpu_halted = !halted_n;
	fx68k cpu (
		.clk(clk), .extReset(machine_reset), .pwrUp(machine_reset),
		.enPhi1(phi1), .enPhi2(phi2), .HALTn(1'b1),
		.eab(cpu_addr), .oEdb(cpu_dout), .iEdb(cpu_din),
		.ASn(cpu_as_n), .eRWn(cpu_rw), .UDSn(cpu_uds_n), .LDSn(cpu_lds_n),
		.FC0(cpu_fc[0]), .FC1(cpu_fc[1]), .FC2(cpu_fc[2]),
		.DTACKn(cpu_dtack_n), .VPAn(1'b1), .BERRn(1'b1),
		.IPL0n(1'b1), .IPL1n(1'b1), .IPL2n(!irq4),
		.BRn(1'b1), .BGACKn(1'b1), .BGn(), .oRESETn(), .oHALTEDn(halted_n), .E(), .VMAn()
	);
	wire [10:0] vector_addr;
	wire [15:0] vector_c;
	wire [9:0]  vector_x, vector_y;
	wire        vector_start;
	wire [7:0]  brightness;
	aztarac_bus bus (
		.clk(clk), .reset(machine_reset), .pause(pause),
		.cpu_addr(cpu_addr), .cpu_dout(cpu_dout), .cpu_din(cpu_din),
		.cpu_as_n(cpu_as_n), .cpu_rw(cpu_rw), .cpu_uds_n(cpu_uds_n), .cpu_lds_n(cpu_lds_n),
		.cpu_dtack_n(cpu_dtack_n), .irq4(irq4), .watchdog_reset(watchdog_reset),
		.rom_wr(rom_wr), .rom_addr(rom_addr), .rom_data(rom_data),
		.inputs(inputs), .joystick_x(joystick_x), .joystick_y(joystick_y), .spinner(spinner),
		.sound_command(sound_command), .sound_command_wr(sound_command_wr), .sound_status(sound_status),
		.nvram_addr(nvram_addr), .nvram_din(nvram_din), .nvram_wr(nvram_wr),
		.nvram_dout(nvram_dout), .nvram_store(nvram_store),
		.vector_addr(vector_addr), .vector_c(vector_c), .vector_x(vector_x), .vector_y(vector_y),
		.vector_start(vector_start), .brightness(brightness)
	);
	aztarac_vector display_list (
		.clk(clk), .reset(machine_reset), .pause(pause), .ce(phi1),
		.start(vector_start), .brightness(brightness),
		.ram_addr(vector_addr), .ram_c(vector_c), .ram_x(vector_x), .ram_y(vector_y),
		.busy(), .fault(vector_fault), .vector_valid(vector_valid),
		.vector_x0(vector_x0), .vector_y0(vector_y0), .vector_x1(vector_x1), .vector_y1(vector_y1),
		.vector_color(vector_color), .vector_intensity(vector_intensity), .frame_done(frame_done)
	);
endmodule

`default_nettype wire

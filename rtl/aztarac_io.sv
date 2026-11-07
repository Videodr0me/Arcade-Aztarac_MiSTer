// Aztarac cabinet inputs and exact MiSTer program download.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

module aztarac_io #(
	parameter integer CLK_HZ = 50_000_000
)(
	input  wire                clk, reset, pause,
	input  wire         [31:0] joystick_0, joystick_1,
	input  wire         [15:0] analog_0, analog_1,
	input  wire         [15:0] right_analog_0, right_analog_1,
	input  wire         [1:0]  turret_mode,
	input  wire         [2:0]  sensitivity,
	input  wire                turret_reverse,
	input  wire         [8:0]  spinner_0, spinner_1,
	input  wire         [24:0] mouse,
	input  wire                diagnostic_button, slam_button, cabinet_reset,
	input  wire                ioctl_download, ioctl_wr,
	input  wire         [15:0] ioctl_index,
	input  wire         [26:0] ioctl_addr,
	input  wire         [7:0]  ioctl_data,
	output logic               rom_wr, sound_rom_wr,
	output logic               rom_loaded = 0, rom_error = 0,
	output logic        [7:0]  inputs,
	output logic signed [7:0]  joystick_x, joystick_y,
	output logic        [7:0]  spinner = 0,
	output logic               pause_button
);
	wire   [31:0] joy           = joystick_0 | joystick_1;
	wire          downloading   = ioctl_download && ioctl_index == 16'd0;
	logic         downloading_q = 0;
	logic  [16:0] count         = 0;
	wire   [16:0] expected_addr = downloading_q ? count : 17'd0;
	wire          byte_valid    = downloading && ioctl_wr && (!downloading_q || !rom_error) &&
	                              ioctl_addr == {10'd0, expected_addr} && expected_addr < 17'he000;
	assign        rom_wr        = byte_valid && ioctl_addr < 27'hc000;
	assign        sound_rom_wr  = byte_valid && ioctl_addr >= 27'hc000;
	always_ff @(posedge clk) begin
		if (reset) begin
			downloading_q <= 0;
			count         <= 0;
			rom_loaded    <= 0;
			rom_error     <= 0;
		end else begin
			downloading_q <= downloading;
			if (downloading && !downloading_q) begin
				rom_loaded <= 0;
				rom_error  <= 0;
				count      <= 0;
			end
			if (downloading && ioctl_wr) begin
				if (byte_valid) count <= expected_addr + 1'd1;
				else rom_error <= 1;
			end
			if (!downloading && downloading_q) begin
				rom_loaded <= !rom_error && count == 17'he000;
				if (count != 17'he000) rom_error <= 1;
			end
		end
	end

	function automatic signed [7:0] axis(input logic signed [7:0] value);
		logic signed [7:0] divided;
		begin
			divided = value / 8'sd8;
			axis    = divided < -8'sd15 ? -8'sd15 : divided;
		end
	endfunction
	function automatic [7:0] magnitude(input logic signed [7:0] value);
		magnitude = value < 0 ? $unsigned(-value) : $unsigned(value);
	endfunction
	localparam integer          CABINET_CYCLES  = CLK_HZ / 10;
	localparam integer          CABINET_TIMER_W = $clog2(CABINET_CYCLES);
	wire  [1:0]                 cabinet_request = {slam_button, diagnostic_button};
	logic [1:0]                 cabinet_request_q = 0, cabinet_pending = 0, cabinet_active = 0;
	logic [CABINET_TIMER_W-1:0] cabinet_timer [0:1] = '{default: '0};

	// TATE changes presentation, while cabinet movement remains in game coordinates.
	wire signed [7:0] left_x = magnitude($signed(analog_1[7:0])) >
	                           magnitude($signed(analog_0[7:0])) ?
	                           $signed(analog_1[7:0]) :
	                           $signed(analog_0[7:0]);
	wire signed [7:0] left_y = magnitude($signed(analog_1[15:8])) >
	                           magnitude($signed(analog_0[15:8])) ?
	                           $signed(analog_1[15:8]) :
	                           $signed(analog_0[15:8]);

	wire             left_active  = magnitude(left_x) >= 8'd8 || magnitude(left_y) >= 8'd8;
	logic      [3:0] move_blocked = 0;
	wire       [3:0] move_buttons = joy[3:0] & ~move_blocked & {4{!left_active}};

	// Analog axes and their digital bindings arrive separately. Keep a suppressed
	// press blocked until release, including after the stick returns to center.
	always_ff @(posedge clk) begin
		if (reset) move_blocked <= 0;
		else move_blocked <= joy[3:0] & (move_blocked | {4{left_active}});
	end
	logic signed [7:0] ax, ay;
	always_comb begin
		ax = left_x;
		ay = left_y;
		if (move_buttons[1:0] != 0)
			ax = move_buttons[1] == move_buttons[0] ? 8'sd0 : (move_buttons[0] ? 8'sd120 : -8'sd120);
		if (move_buttons[3:2] != 0)
			ay = move_buttons[3] == move_buttons[2] ? 8'sd0 : (move_buttons[3] ? -8'sd120 : 8'sd120);
		joystick_x   = axis(ax);
		joystick_y   = -axis(ay);
		inputs       = {~cabinet_active[0], ~cabinet_active[1], 1'b1, ~joy[10],
		                ~joy[9], ~joy[8], ~(joy[4] | mouse[0]), ~(joy[5] | mouse[1])};
		pause_button = joy[11];
	end

	// The host sends short actions. Hold each cabinet contact for 100 ms of
	// running CPU time, with a release interval before another queued press.
	always_ff @(posedge clk) begin
		cabinet_request_q <= cabinet_request;
		for (int i = 0; i < 2; i++) begin
			if (reset || cabinet_reset || downloading || !rom_loaded) begin
				cabinet_pending[i] <= 0;
				cabinet_active[i]  <= 0;
				cabinet_timer[i]   <= 0;
			end else begin
				if (cabinet_request[i] && !cabinet_request_q[i]) cabinet_pending[i] <= 1;
				if (!pause) begin
					if (cabinet_timer[i] != 0) cabinet_timer[i] <= cabinet_timer[i] - 1'd1;
					else if (cabinet_active[i]) begin
						cabinet_active[i] <= 0;
						cabinet_timer[i]  <= CABINET_TIMER_W'(CABINET_CYCLES - 1);
					end else if (cabinet_pending[i] || (cabinet_request[i] && !cabinet_request_q[i])) begin
						cabinet_active[i]  <= 1;
						cabinet_pending[i] <= 0;
						cabinet_timer[i]   <= CABINET_TIMER_W'(CABINET_CYCLES - 1);
					end
				end
			end
		end
	end

	localparam integer        RATE_CYCLES = CLK_HZ / 200;
	localparam integer        RATE_W      = $clog2(RATE_CYCLES);
	localparam [RATE_W-1:0]   RATE_LAST   = RATE_W'(RATE_CYCLES - 1);
	logic        [2:0]        toggles     =  0;
	logic        [1:0]        arm         =  0;
	logic        [RATE_W-1:0] rate        = '0;
	wire                      sample = rate == RATE_LAST;
	logic        [2:0]        last_control = 0;
	wire                      switching = last_control != {turret_mode,turret_reverse};
	wire                      aim_valid;
	wire         [6:0]        aim;
	wire  signed [7:0]        turn;
	wire                      turret_active;
	logic        [1:0]        turn_blocked   = 0;
	wire         [1:0]        turn_buttons   = joy[7:6] & ~turn_blocked & {2{!turret_active}};
	wire         [7:0]        button_turn    = !sample || turn_buttons[0] == turn_buttons[1] ? 8'd0 :
	                                           turn_buttons[0] ? 8'd1 : 8'hff;
	wire         [6:0]        aim_difference = aim - spinner[6:0];
	// Both wheels and mouse X can arrive together (-512..509). Consume all
	// three toggles even while paused or using the stick so nothing replays.
	logic signed [9:0] wheel_delta;
	always_comb begin
		wheel_delta = 0;
		if (spinner_0[8] != toggles[0]) wheel_delta = 10'($signed(spinner_0[7:0]));
		if (spinner_1[8] != toggles[1]) wheel_delta = wheel_delta + 10'($signed(spinner_1[7:0]));
		if (mouse[24] != toggles[2])    wheel_delta = wheel_delta + 10'($signed({mouse[4],mouse[15:8]}));
	end
	aztarac_turret turret (
		.clk(clk), .restart(reset || pause || switching), .sample(sample),
		.stick_0(right_analog_0), .stick_1(right_analog_1),
		.mode(turret_mode), .wheel_delta(wheel_delta), .sensitivity(sensitivity), .reverse(turret_reverse),
		.active(turret_active), .aim_valid(aim_valid), .aim(aim), .turn(turn)
	);
	always_ff @(posedge clk) begin
		last_control <= {turret_mode,turret_reverse};
		if (reset) turn_blocked <= 0;
		else turn_blocked <= joy[7:6] & (turn_blocked | {2{turret_active || switching || pause}});
		toggles <= {mouse[24], spinner_1[8], spinner_0[8]};
		if (reset) begin
			spinner <=  0;
			rate    <= '0;
			arm     <=  0;
		end else begin
			if (arm != 3) arm <= arm + 1'd1;
			if (pause) rate <= '0;
			else begin
				rate <= rate == RATE_LAST ? '0 : rate + 1'd1;
				if (arm == 3 && !switching)
					spinner <= spinner + turn[7:0] + button_turn +
					           (aim_valid ? {aim_difference[6],aim_difference} : 8'd0);
			end
		end
	end
endmodule

`default_nettype wire

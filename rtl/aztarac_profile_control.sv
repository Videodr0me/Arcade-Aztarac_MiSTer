// Aztarac profile shortcuts and persistent custom controls.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later

`default_nettype none

module aztarac_profile_control (
	input  wire           clk_sys,
	input  wire           reset,
	input  wire           commit, echo, clear_settings,
	input  wire  [127:0]  stored, incoming,
	input  wire           settings_ready,
	input  wire  [1:0]    video_resolution,
	input  wire           video_freeze, video_is_15khz, direct_video,
	input  wire           osd_open,
	input  wire  [10:0]   ps2_key,

	output vfb_control_pkg::vfb_profile_settings_t custom_1_settings,
	output vfb_control_pkg::vfb_profile_settings_t custom_2_settings,
	output vfb_control_pkg::vfb_profile_settings_t resolved_settings =
	    vfb_control_pkg::fixed_profile(vfb_control_pkg::PROFILE_TYPICAL, 2'd1),

	output wire  [2:0]    profile,
	output logic [127:0]  status,
	output wire           reply_pending, custom_editable,
	output logic          info_req = 1'b0,
	output logic [7:0]    info = 8'd0
);
	import vfb_control_pkg::*;

	localparam integer CUSTOM_INIT_BIT = 127;
	localparam integer AUDIO_INIT_BIT  = 54;
	localparam integer GAIN_INIT_BIT   = 37;
	localparam integer PROFILE_BITS    = $bits(vfb_profile_settings_t);

	// Keep the existing saved bit layout, including the noncontiguous Custom fields.
	function automatic vfb_profile_settings_t read_custom(input logic [127:0] cfg, input logic slot);
		if (slot)
			read_custom = {cfg[19], cfg[50:48], cfg[62:60], cfg[94:92], cfg[96:95],
			               cfg[99:97], cfg[102:100], cfg[105:103], cfg[107:106], cfg[109:108],
			               cfg[111:110], cfg[126], cfg[114:112], cfg[124]};
		else
			read_custom = {cfg[18], cfg[47:45], cfg[59:57], cfg[71:69], cfg[73:72],
			               cfg[76:74], cfg[79:77], cfg[82:80], cfg[84:83], cfg[86:85],
			               cfg[88:87], cfg[125], cfg[91:89], cfg[122]};
	endfunction

	function automatic logic [127:0] write_custom(
		input logic [127:0] cfg, input logic slot, input vfb_profile_settings_t value);
		write_custom = cfg;
		if (slot)
			{write_custom[19], write_custom[50:48], write_custom[62:60],
			 write_custom[94:92], write_custom[96:95], write_custom[99:97],
			 write_custom[102:100], write_custom[105:103], write_custom[107:106],
			 write_custom[109:108], write_custom[111:110], write_custom[126],
			 write_custom[114:112], write_custom[124]} = value;
		else
			{write_custom[18], write_custom[47:45], write_custom[59:57],
			 write_custom[71:69], write_custom[73:72], write_custom[76:74],
			 write_custom[79:77], write_custom[82:80], write_custom[84:83],
			 write_custom[86:85], write_custom[88:87], write_custom[125],
			 write_custom[91:89], write_custom[122]} = value;
	endfunction

	// The frozen flag and committed CRT mode cross as one stable control bus.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [3:0] mode_meta = {2'b01, 2'd1}, mode_sync = {2'b01, 2'd1};
	logic [3:0] mode_sync_d = {2'b01, 2'd1};
	always_ff @(posedge clk_sys) begin
		mode_meta   <= {video_is_15khz, video_freeze, video_resolution};
		mode_sync   <= mode_meta;
		mode_sync_d <= mode_sync;
	end

	wire can_reply = settings_ready && !reset;
	wire [1:0] crt_table = stored[118] && !(direct_video && stored[115]) ? 2'd0 : 2'd1;
	wire table_ready = !(direct_video || mode_sync[3]) || mode_sync[1:0] == crt_table;
	wire seed_ready = can_reply && !commit && !mode_sync[2] &&
	                  mode_sync == mode_sync_d && table_ready;

	vfb_profile_settings_t custom1_status, custom2_status, custom1_default, custom2_default;
	vfb_profile_settings_t selected_settings;
	wire [1:0] slot_valid;
	wire initialized = &slot_valid;
	wire [2:0] selected_profile;
	wire custom_selected = profile == PROFILE_CUSTOM1 || profile == PROFILE_CUSTOM2;
	wire [4:0] pending;
	wire [3:0] gain;
	wire [2:0] audio;
	assign profile = selected_profile == 3'd7 ? PROFILE_TYPICAL : selected_profile;
	assign custom1_default = fixed_profile(PROFILE_TYPICAL, mode_sync[1:0]);
	assign custom2_default = fixed_profile(PROFILE_OVERDRIVEN, mode_sync[1:0]);

	always_comb begin
		custom_1_settings = custom1_status;
		custom_2_settings = custom2_status;
		// Preview empty slots while their initial values are being returned to Main.
		if (!slot_valid[0] && !(|custom1_status)) custom_1_settings = custom1_default;
		if (!slot_valid[1] && !(|custom2_status)) custom_2_settings = custom2_default;
		case (profile)
			PROFILE_CUSTOM1: selected_settings = custom_1_settings;
			PROFILE_CUSTOM2: selected_settings = custom_2_settings;
			default:         selected_settings = fixed_profile(profile, mode_sync[1:0]);
		endcase
	end

	// Resolve in clk_sys before the renderer's packed control crossing. Keep the
	// unbypassed selection above for copying presets into the custom slots.
	always_ff @(posedge clk_sys) begin
		if (reset) resolved_settings <= fixed_profile(PROFILE_TYPICAL, 2'd1);
		else if (mode_sync == mode_sync_d) begin
			// Resolution may settle while output is frozen; waiting for unfreeze
			// here would prevent the requested halo grid from completing its switch.
			if (stored[123])
				resolved_settings <= pack_settings(DOT_1X, TONE_OFF, BLOOM_OFF,
				                                   CURVE_MINIMAL, HALO_OFF, CURVE_MINIMAL,
				                                   SPREAD_ORIGINAL, KNEE_16, INTER_OFF,
				                                   INTRA_OFF, COLORSPACE_OFF,
				                                   CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
			else resolved_settings <= selected_settings;
		end
	end

	// The seven menu entries and shortcuts use the same ring.
	function automatic logic [2:0] cycle_profile(input logic [2:0] current, input logic next);
		if (next) cycle_profile = current == PROFILE_TOUCH ? PROFILE_TYPICAL : current + 3'd1;
		else      cycle_profile = current == PROFILE_TYPICAL ? PROFILE_TOUCH : current - 3'd1;
	endfunction

	logic key_toggle_q = 1'b0;
	logic [1:0] profile_keys_down = 0, control_keys_down = 0, shift_keys_down = 0;
	logic [3:0] copy_keys_down = 0;
	wire key_event = ps2_key[10] != key_toggle_q;
	wire profile_prev_key = ps2_key[7:0] == 8'h4e;
	wire profile_next_key = ps2_key[7:0] == 8'h55;
	wire key_press = key_event && ps2_key[9] && !ps2_key[8] && !osd_open && can_reply;
	wire profile_press = key_press &&
	                     ((profile_prev_key && !profile_keys_down[0]) ||
	                      (profile_next_key && !profile_keys_down[1]));
	wire copy_first_key = ps2_key[7:0] == 8'h16;
	wire copy_second_key = ps2_key[7:0] == 8'h1e;
	wire copy_f6_key = ps2_key[7:0] == 8'h0b;
	wire copy_f7_key = ps2_key[7:0] == 8'h83;
	wire copy_chord = (|control_keys_down) && (|shift_keys_down);
	// Consume premature presses, including repeats; do not copy a provisional preset later.
	wire copy_ready = seed_ready || (can_reply && initialized && custom_selected);
	wire [1:0] copy_to = {2{key_press && copy_ready}} &
	                     ({copy_f7_key && !copy_keys_down[3],
	                       copy_f6_key && !copy_keys_down[2]} |
	                      ({2{copy_chord}} & {copy_second_key && !copy_keys_down[1],
	                                         copy_first_key && !copy_keys_down[0]})) &
	                     {profile != PROFILE_CUSTOM2, profile != PROFILE_CUSTOM1};
	wire copy_press = |copy_to;

	always_ff @(posedge clk_sys) begin
		key_toggle_q <= ps2_key[10];
		// Main may consume releases while the menu is open.
		if (osd_open) begin
			profile_keys_down <= 0;
			control_keys_down <= 0;
			shift_keys_down   <= 0;
			copy_keys_down    <= 0;
		end else if (key_event) begin
			if (ps2_key[7:0] == 8'h14) control_keys_down[ps2_key[8]] <= ps2_key[9];
			if (!ps2_key[8]) begin
				if (profile_prev_key)      profile_keys_down[0] <= ps2_key[9];
				if (profile_next_key)      profile_keys_down[1] <= ps2_key[9];
				if (ps2_key[7:0] == 8'h12) shift_keys_down[0]   <= ps2_key[9];
				if (ps2_key[7:0] == 8'h59) shift_keys_down[1]   <= ps2_key[9];
				if (copy_first_key)        copy_keys_down[0]    <= ps2_key[9];
				if (copy_second_key)       copy_keys_down[1]    <= ps2_key[9];
				if (copy_f6_key)           copy_keys_down[2]    <= ps2_key[9];
				if (copy_f7_key)           copy_keys_down[3]    <= ps2_key[9];
			end
		end
	end

	wire seed = seed_ready && !initialized;
	aztarac_settings_field #(3) profile_edit (
		.*, .set(profile_press), .target(cycle_profile(profile, profile_next_key)),
		.old_value(stored[68:66]), .new_value(incoming[68:66]),
		.value(selected_profile), .pending(pending[0])
	);
	aztarac_settings_field #(1 + PROFILE_BITS) custom1_edit (
		.*, .set(seed || copy_to[0]),
		.target({1'b1, copy_to[0] ? selected_settings :
		          (|custom1_status) ? custom1_status : custom1_default}),
		.old_value({stored[CUSTOM_INIT_BIT], read_custom(stored, 1'b0)}),
		.new_value({incoming[CUSTOM_INIT_BIT], read_custom(incoming, 1'b0)}),
		.value({slot_valid[0], custom1_status}), .pending(pending[1])
	);
	aztarac_settings_field #(1 + PROFILE_BITS) custom2_edit (
		.*, .set(seed || copy_to[1]),
		.target({1'b1, copy_to[1] ? selected_settings :
		          (|custom2_status) ? custom2_status : custom2_default}),
		.old_value({stored[CUSTOM_INIT_BIT], read_custom(stored, 1'b1)}),
		.new_value({incoming[CUSTOM_INIT_BIT], read_custom(incoming, 1'b1)}),
		.value({slot_valid[1], custom2_status}), .pending(pending[2])
	);
	// Initialization markers preserve deliberately saved 0.25x gain and Audio Off.
	aztarac_settings_field #(4) gain_edit (
		.*, .set(can_reply && !commit && !gain[3]), .target(4'b1011),
		.old_value({stored[GAIN_INIT_BIT], stored[34:32]}),
		.new_value({incoming[GAIN_INIT_BIT], incoming[34:32]}),
		.value(gain), .pending(pending[3])
	);
	aztarac_settings_field #(3) audio_edit (
		.*, .set(can_reply && !commit && !audio[2]), .target(3'b110),
		.old_value({stored[AUDIO_INIT_BIT], stored[53:52]}),
		.new_value({incoming[AUDIO_INIT_BIT], incoming[53:52]}),
		.value(audio), .pending(pending[4])
	);

	// The active controls and Main's next reply use the same complete settings.
	always_comb begin
		status = write_custom(write_custom(stored, 1'b0, custom1_status), 1'b1, custom2_status);
		status[68:66] = profile;
		status[CUSTOM_INIT_BIT] = initialized;
		{status[GAIN_INIT_BIT], status[34:32]} = gain;
		{status[AUDIO_INIT_BIT], status[53:52]} = audio;
	end
	assign reply_pending = can_reply && (|pending);
	assign custom_editable = can_reply && stored[CUSTOM_INIT_BIT];

	logic info_pending = 0, info_is_copy = 0, info_copy_target = 0;
	always_ff @(posedge clk_sys) begin
		info_req <= 0;
		if (reset || osd_open || clear_settings) info_pending <= 0;
		else if (copy_press || profile_press) begin
			info_pending <= 1;
			info_is_copy <= copy_press;
			info_copy_target <= copy_to[1];
		end else if (info_pending && !(|pending) && !seed) begin
			info_pending <= 0;
			info_req <= 1;
			info <= info_is_copy ? (info_copy_target ? 8'd9 : 8'd8) : 8'd1 + {5'd0, profile};
		end
	end
endmodule

// Independent host edits replace a pending field; an older echo preserves newer local work.
module aztarac_settings_field #(parameter WIDTH = 1) (
	input  wire              clk_sys, commit, echo, clear_settings, set,
	input  wire  [WIDTH-1:0] target, old_value, new_value,
	output wire  [WIDTH-1:0] value,
	output logic             pending = 0
);
	logic [WIDTH-1:0] wanted;
	assign value = pending ? wanted : old_value;
	always_ff @(posedge clk_sys) begin
		if (clear_settings) pending <= 0;
		else if (set) begin
			wanted <= target;
			pending <= pending || target != (commit ? new_value : old_value);
		end else if (commit && ((new_value == wanted) || (!echo && new_value != old_value)))
			pending <= 0;
	end
endmodule

`default_nettype wire

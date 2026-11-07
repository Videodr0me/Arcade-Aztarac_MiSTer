// Centuri Aztarac for MiSTer. Written by Videodr0me.
// SPDX-License-Identifier: GPL-3.0-or-later
module emu (
	`include "sys/emu_ports.vh"
);
`include "build_id.v"
localparam CONF_STR = {
	"AZTARAC;;",
	"-;",
	"P1,Video Profiles & Effects;",
	"P1O[68:66],Profile,80s Cruise Control,80s Overdrive,Plasmarac,Negative Shield,Custom 1,Custom 2,A Touch of CRT;",
	"h3P1-;",
	"h3P1-,Clear vectors gather under;",
	"h3P1-,the dome with a gentle;",
	"h3P1-,phosphor glow. Bright stars;",
	"h3P1-,and clean lines give shape;",
	"h3P1-,to Stryker's universe.;",
	"h3P1-,Soft reflections in the;",
	"h3P1-,black surround frame the;",
	"h3P1-,familiar warmth of an;",
	"h3P1-,80s colour vector display.;",
	"h4P1-;",
	"h4P1-,The phosphor runs a little;",
	"h4P1-,hotter. Sparks flare and;",
	"h4P1-,fuller halos fill the dark.;",
	"h4P1-,Longer trails follow the;",
	"h4P1-,battle across the glass.;",
	"h4P1-,Against the reflective black;",
	"h4P1-,surround the colours burn;",
	"h4P1-,with familiar arcade heat.;",
	"h4P1-,A brighter pulse from 1983.;",
	"h5P1-;",
	"h5P1-,You have crossed into the;",
	"h5P1-,anti-verse. The stars are;",
	"h5P1-,familiar. Their colours are;",
	"h5P1-,wrong. Your ship casts a;",
	"h5P1-,trail of impossible light;",
	"h5P1-,as enemy formations emerge;",
	"h5P1-,from the far side of space.;",
	"h5P1-,Same base. Same battle.;",
	"h5P1-,A very different universe.;",
	"h6P1-;",
	"h6P1-,Beyond the zodiac a thousand;",
	"h6P1-,suns feed the ionized gas.;",
	"h6P1-,Your ship scatters into a;",
	"h6P1-,cloud of sparks. Enemy;",
	"h6P1-,formations break apart and;",
	"h6P1-,ignite the plasma in their;",
	"h6P1-,wake. Generous glow and;",
	"h6P1-,lingering trails charge and;",
	"h6P1-,discharge in currents of;",
	"h6P1-,colour across the dome.;",
	"h7P1-;",
	"h7P1-,Fine vectors;",
	"h7P1-,wear just enough phosphor;",
	"h7P1-,to take the edge off space.;",
	"h7P1-,Subtle bloom and a soft halo;",
	"h7P1-,settle around the bright;",
	"h7P1-,lines. Stars stay crisp;",
	"h7P1-,under the dome with a little;",
	"h7P1-,of that familiar CRT warmth.;",
	"HBHCP1-;",
	"HBHCP1-,For advanced settings;",
	"HBHCP1-,select Custom Profiles 1/2;",
	"hBd8P1O[71:69],> Dot Scale,2x,2.5x,3x,1x;",
	"hBd8P1O[73:72],> Tone Mapping,Off,Standard,Bright,Boost;",
	"hBd8P1O[76:74],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
	"hBH9d8P1O[79:77],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
	"hBd8P1O[82:80],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
	"hBHAd8P1O[59:57],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
	"hBHAd8P1O[84:83],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
	"hBHAd8P1O[18],> Halo Grid,16x16,8x8;",
	"hBHAd8P1O[47:45],> Halo Compression,Off,2,4,6,8,16,24,32;",
	"hBd8P1O[86:85],> Inter-Frame Decay,Off,Short,Medium,Long;",
	"hBd8P1O[88:87],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
	"hBd8P1O[125],> Color Space,Native,G08 to Rec.709;",
	"hBd8P1O[91:89],> Color Effect,Original,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
	"hBd8P1O[122],> Slot Mask,Off,On;",
	"hCd8P1O[94:92],> Dot Scale,2x,2.5x,3x,1x;",
	"hCd8P1O[96:95],> Tone Mapping,Off,Standard,Bright,Boost;",
	"hCd8P1O[99:97],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
	"hCH9d8P1O[102:100],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
	"hCd8P1O[105:103],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
	"hCHAd8P1O[62:60],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
	"hCHAd8P1O[107:106],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
	"hCHAd8P1O[19],> Halo Grid,16x16,8x8;",
	"hCHAd8P1O[50:48],> Halo Compression,Off,2,4,6,8,16,24,32;",
	"hCd8P1O[109:108],> Inter-Frame Decay,Off,Short,Medium,Long;",
	"hCd8P1O[111:110],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
	"hCd8P1O[126],> Color Space,Native,G08 to Rec.709;",
	"hCd8P1O[114:112],> Color Effect,Original,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
	"hCd8P1O[124],> Slot Mask,Off,On;",
	"P2,Video Overlay & Geometry;",
	"P2-;",
	"P2O[24:23],Overlay,On,Labels Only,Off;",
	"HDP2O[12:10],Artwork Brightness,100%,10%,20%,30%,40%,50%,60%,80%;",
	"P2-;",
	"P2O[21:20],Orientation,Normal,90 CCW,90 CW;",
	"P2-;",
	"D2d0P2O[25],120Hz (720p only),Off,On;",
	"h1P2O[115],Direct Video Scan Rate,15 kHz,31 kHz;",
	"h2h0P2O[118],15 kHz Format,480i,240p;",
	"h2P2O[65:63],CRT Vertical Offset,0,+1,+2,+3,-1,-2,-3;",
	"h2P2O[43:41],CRT Horizontal Offset,0,+1,+2,+3,-1,-2,-3;",
	"-;",
	"P3,System;",
	"P3-;",
	"P3O[53:52],Audio Low-Pass,Off,4 kHz,6 kHz,8 kHz;",
	"P3-;",
	"P3O[116],Pause when OSD open,Off,On;",
	"P3O[117],Dim video after 60s,On,Off;",
	"P3-;",
	"P3O[27],Autosave Game Settings,On,Off;",
	"P3T4,Save Game Settings;",
	"P3-;",
	"P3R3,Cabinet Service Switch;",
	"P3R5,Slam/Tilt;",
	"P3-;",
	"P3-,Service in attract -> Setup;",
	"-;",
	"P6,Diagnostics;",
	"P6-;",
	"P6O[123],Effects Bypass,Off,On;",
	"P6-;",
	"P6O[29:28],Halo Interpolation,B=2.00,Normal,B=1.50,B=1.75;",
	"P6-;",
	"P6O[40:39],Buffer Mode,EOF + VBL,VBL,EOF;",
	"P6O[15:14],Aspect Ratio,Original,Stretched,Pixel Perfect;",
	"-;",
	"P4,Controls;",
	"P4-,Turret;",
	"P4O[1],Aim with,Right Stick,Spinner / Mouse;",
	// E/F encode the four aim modes. Each pair of alternatives draws one row.
	"HEP4O[36:35],Stick Mode,Directional Aim,Horizontal Pos,Rotation Speed;",
	"hEDFP4O[36:35],Stick Mode,Directional Aim,Horizontal Pos,Rotation Speed;",
	"dEP4O[34:32],Sensitivity,0.25x,0.5x,0.75x,1x,1.25x,1.5x,2x,3x;",
	"HEdFP4O[13],Direction,Normal,Reversed;",
	"hEHFP4O[13],Direction,Normal,Reversed;",
	"hEhFP4O[2],Direction,Normal,Reversed;",
	"P4-,CCW/CW Buttons:   always on;",
	"P4-;",
	"P4-,Move Ship (always active);",
	"P4-,Left Stick:          Analog;",
	"P4-,D-Pad:              Digital;",
	"-;",
	"P5,Core Info;",
	"P5-;",
	"P5-,Aztarac for MiSTer;",
	"P5-,     by Videodr0me 2026;",
	"P5-;",
	"P5-,If you enjoy reliving the;",
	"P5-,golden age of arcade games,;",
	"P5-,please support my work and;",
	"P5-,future updates:;",
	"P5-;",
	"P5-,buymeacoffee.com/videodr0me;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Radar,Turret CCW (button),Turret CW (button),Start 1,Start 2,Coin,Pause;",
	"jn,A,B,X,Y,Start,Select,R,L;",
	"I,",
	"Profile: 80s Cruise Control,",
	"Profile: 80s Overdrive,",
	"Profile: Plasmarac,",
	"Profile: Negative Shield,",
	"Profile: Custom 1,",
	"Profile: Custom 2,",
	"Profile: A Touch of CRT,",
	"Copied to Custom 1,",
	"Copied to Custom 2;",
	"v,1;",
	"V,v0.1.", `BUILD_DATE
};
wire clk_sys = CLK_50M;
wire clk_125, pll_locked;
pll_vfb pll_vfb (.refclk(CLK_50M), .rst(1'b0), .outclk_0(clk_125), .locked(pll_locked));

wire [127:0] status, host_status, stored_status;
wire [10:0]  ps2_key;
wire [7:0]   profile_info;
wire         profile_info_req, reply_pending, capture_reply, custom_editable;
wire         settings_commit, settings_echo, settings_clear;
wire [31:0]  joystick_0, joystick_1;
wire [15:0]  analog_0, analog_1;
wire [15:0]  right_analog_0, right_analog_1;
wire [1:0]   active_orientation;
wire [8:0]   spinner_0, spinner_1;
wire [24:0]  ps2_mouse;
wire [1:0]   buttons;
wire         direct_video, ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd, ioctl_wait, artwork_wait;
wire [26:0]  ioctl_addr;
wire [15:0]  ioctl_index;
wire [7:0]   ioctl_data;
wire [21:0]  gamma_bus;
wire [35:0]  extension_bus;

assign gamma_bus[21]       =  1'b0;

wire [2:0]                              profile;
wire                                    video_supports_120hz, video_is_15khz, video_is_crt;
wire                                    video_mode_toggle, video_freeze;
wire [1:0]                              profile_resolution;
wire [15:0]                             menu_mask;
vfb_control_pkg::vfb_profile_settings_t custom_1;
vfb_control_pkg::vfb_profile_settings_t custom_2;
vfb_control_pkg::vfb_profile_settings_t resolved_settings;

// Main displays the first stick option for an out-of-range stored index.
wire [1:0] aim_mode = status[1] ? 2'd3 : status[36:35] == 2'd3 ? 2'd0 : status[36:35];

// In CRT modes bit 0 enables the 15 kHz format row. In HD it enables 120 Hz.
assign        menu_mask[0]  = video_is_crt ? video_is_15khz : video_supports_120hz;
assign        menu_mask[1]  = direct_video;
assign        menu_mask[2]  = video_is_crt;
assign        menu_mask[3]  = profile == vfb_control_pkg::PROFILE_TYPICAL;
assign        menu_mask[4]  = profile == vfb_control_pkg::PROFILE_OVERDRIVEN;
assign        menu_mask[5]  = profile == vfb_control_pkg::PROFILE_S_NEGATIVE;
assign        menu_mask[6]  = profile == vfb_control_pkg::PROFILE_PLASMA;
assign        menu_mask[7]  = profile == vfb_control_pkg::PROFILE_TOUCH;
assign        menu_mask[8]  = custom_editable; // Redraw and enable Custom rows after Main receives them.
assign        menu_mask[9]  = (menu_mask[12] ? custom_2.bloom_width : custom_1.bloom_width) == 0;
assign        menu_mask[10] = (menu_mask[12] ? custom_2.halo_filter : custom_1.halo_filter) == 0;
assign        menu_mask[11] = profile == vfb_control_pkg::PROFILE_CUSTOM1;
assign        menu_mask[12] = profile == vfb_control_pkg::PROFILE_CUSTOM2;
assign        menu_mask[13] = status[24];
assign        menu_mask[14] = aim_mode[1]; // Rotation Speed or Spinner / Mouse
assign        menu_mask[15] = aim_mode[0]; // Horizontal Pos or Spinner / Mouse


wire         nvram_request, nvram_busy, nvram_error, nvram_write, nvram_store;
wire   [7:0] nvram_addr;
wire   [3:0] nvram_din, nvram_dout;
assign       ioctl_wait = artwork_wait || nvram_write;
hps_io #(.CONF_STR(CONF_STR)) hps_io (
	.clk_sys(clk_sys), .HPS_BUS(HPS_BUS), .gamma_bus(gamma_bus), .EXT_BUS(extension_bus),
	.buttons(buttons), .status(host_status), .status_in(status),
	.status_set(capture_reply), .status_menumask(menu_mask),
	.direct_video(direct_video), .new_vmode(video_mode_toggle),
	.ioctl_download(ioctl_download),
	.ioctl_upload  (ioctl_upload),
	.ioctl_wr      (ioctl_wr),
	.ioctl_rd      (ioctl_rd),
	.ioctl_addr (ioctl_addr),
	.ioctl_dout (ioctl_data),
	.ioctl_index(ioctl_index),
	.ioctl_wait (ioctl_wait),
	.ioctl_upload_req(nvram_request), .ioctl_upload_index(8'd4), .ioctl_din({4'hf,nvram_dout}),
	.joystick_0(joystick_0), .joystick_1(joystick_1),
	.joystick_l_analog_0(analog_0), .joystick_l_analog_1(analog_1),
	.joystick_r_analog_0(right_analog_0), .joystick_r_analog_1(right_analog_1),
	.spinner_0(spinner_0), .spinner_1(spinner_1), .ps2_mouse(ps2_mouse),
	.video_rotated(active_orientation != 0),
	.ps2_key      (ps2_key),
	.info_req     (profile_info_req),
	.info         (profile_info),
	.sd_lba('{32'd0}), .sd_blk_cnt('{6'd0}), .sd_rd(1'b0), .sd_wr(1'b0), .sd_buff_din('{8'd0}),
	.joystick_0_rumble(16'd0), .joystick_1_rumble(16'd0), .joystick_2_rumble(16'd0),
	.joystick_3_rumble(16'd0), .joystick_4_rumble(16'd0), .joystick_5_rumble(16'd0),
	.ps2_kbd_clk_in    (1'b1),
	.ps2_kbd_data_in   (1'b1),
	.ps2_kbd_led_status(3'd0),
	.ps2_kbd_led_use   (3'd0),
	.ps2_mouse_clk_in(1'b1), .ps2_mouse_data_in(1'b1)
);
aztarac_nvram_io persistent_settings (
	.clk(clk_sys), .reset(RESET), .ioctl_download(ioctl_download), .ioctl_upload(ioctl_upload),
	.ioctl_wr   (ioctl_wr),
	.ioctl_rd   (ioctl_rd),
	.ioctl_index(ioctl_index),
	.ioctl_addr (ioctl_addr),
	.ioctl_data (ioctl_data),
	.store(nvram_store), .autosave(!status[27]), .save_request(status[4]),
	.address(nvram_addr), .data(nvram_din), .write(nvram_write), .busy(nvram_busy),
	.request(nvram_request), .dirty(), .load_error(nvram_error)
);
wire              rom_wr, sound_rom_wr, rom_loaded, rom_error, pause_button, pause_cpu;
wire        [7:0] inputs, spinner;
wire signed [7:0] joystick_x, joystick_y;
// Apply the source, its direction and the shared gain from one complete HPS packet.
wire        settings_valid;
wire [1:0] turret_mode = settings_valid ? aim_mode : 2'd0;
wire [2:0] sensitivity = settings_valid && status[37] ? status[34:32] : 3'd3;
wire       turret_reverse = settings_valid &&
                            (aim_mode == 2'd3 ? status[2] : aim_mode != 2'd0 && status[13]);

aztarac_io arcade_io (
	.clk       (clk_sys),
	.reset     (RESET),
	.pause     (pause_cpu),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.analog_0 (analog_0),
	.analog_1 (analog_1),
	.spinner_0(spinner_0),
	.spinner_1(spinner_1),
	.mouse    (ps2_mouse),
	.right_analog_0(right_analog_0), .right_analog_1(right_analog_1),
	.turret_mode(turret_mode), .sensitivity(sensitivity), .turret_reverse(turret_reverse),
	.diagnostic_button(status[3]), .slam_button(status[5]), .cabinet_reset(status[0] || buttons[1]),
	.ioctl_download(ioctl_download),
	.ioctl_wr      (ioctl_wr),
	.ioctl_index   (ioctl_index),
	.ioctl_addr    (ioctl_addr),
	.ioctl_data    (ioctl_data),
	.rom_wr(rom_wr), .sound_rom_wr(sound_rom_wr), .rom_loaded(rom_loaded), .rom_error(rom_error),
	.inputs      (inputs),
	.joystick_x  (joystick_x),
	.joystick_y  (joystick_y),
	.spinner     (spinner),
	.pause_button(pause_button)
);
wire        reset_request = RESET || status[0] || buttons[1] || !rom_loaded ||
                            (ioctl_download && ioctl_index == 0);
logic [1:0] reset_pipe    = 2'b11;
always_ff @(posedge clk_sys or posedge reset_request)
	if (reset_request) reset_pipe <= 2'b11;
	else reset_pipe <= {reset_pipe[0],1'b0};
wire machine_reset = reset_pipe[1];

aztarac_status_guard status_guard (
	.clk_sys(clk_sys), .ext_bus(extension_bus), .incoming(host_status),
	.reply_pending(reply_pending), .reply_zero(status == 128'd0),
	.stored(stored_status), .commit(settings_commit), .echo(settings_echo),
	.clear_settings(settings_clear), .capture(capture_reply), .settings_valid(settings_valid)
);

aztarac_profile_control profile_control (
	.clk_sys(clk_sys), .reset(RESET),
	.commit(settings_commit), .echo(settings_echo), .clear_settings(settings_clear),
	.stored(stored_status), .incoming(host_status),
	.settings_ready(settings_valid && rom_loaded && !machine_reset && !ioctl_download),
	.video_resolution(profile_resolution), .video_freeze(video_freeze),
	.video_is_15khz(video_is_15khz), .direct_video(direct_video),
	.osd_open(OSD_STATUS), .ps2_key(ps2_key),
	.custom_1_settings(custom_1), .custom_2_settings(custom_2),
	.profile(profile),
	.resolved_settings(resolved_settings),
	.status(status), .reply_pending(reply_pending), .custom_editable(custom_editable),
	.info_req(profile_info_req), .info(profile_info)
);

wire [7:0]  video_r, video_g, video_b;
wire        pause_dim;
// Only the slow dimming flag crosses domains; RGB stays in the video domain.
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
logic [1:0] pause_dim_sync = 2'b00;
always_ff @(posedge clk_125) pause_dim_sync <= {pause_dim_sync[0], pause_dim};
wire [23:0] paused_rgb = pause_dim_sync[1] ?
                         {1'b0, video_r[7:1], 1'b0, video_g[7:1], 1'b0, video_b[7:1]} :
                         {video_r, video_g, video_b};
pause #(.RW(8), .GW(8), .BW(8), .CLK_HZ(50_000_000)) pause_inst (
	.clk_sys      (clk_sys),
	.reset        (machine_reset),
	.user_button  (pause_button),
	.pause_request(nvram_busy),
	.options({~status[117],status[116]}), .OSD_STATUS(OSD_STATUS),
	.r(8'd0), .g(8'd0), .b(8'd0), .pause_cpu(pause_cpu), .dim_video(pause_dim), .rgb_out()
);
wire signed [11:0] vector_x0, vector_y0, vector_x1, vector_y1;
wire        [5:0]  vector_color;
wire        [7:0]  vector_intensity, sound_command, sound_status;
wire               vector_valid, frame_done, vector_fault, cpu_halted, watchdog_reset, sound_command_wr;
aztarac_machine machine (
	.clk(clk_sys), .reset(machine_reset), .pause(pause_cpu || nvram_busy),
	.rom_wr(rom_wr), .rom_addr(ioctl_addr[15:0]), .rom_data(ioctl_data),
	.inputs(inputs), .joystick_x(joystick_x), .joystick_y(joystick_y), .spinner(spinner),
	.sound_command(sound_command), .sound_command_wr(sound_command_wr), .sound_status(sound_status),
	.nvram_addr (nvram_addr),
	.nvram_din  (nvram_din),
	.nvram_wr   (nvram_write),
	.nvram_dout (nvram_dout),
	.nvram_store(nvram_store),
	.vector_valid(vector_valid),
	.vector_x0   (vector_x0),
	.vector_y0   (vector_y0),
	.vector_x1   (vector_x1),
	.vector_y1   (vector_y1),
	.vector_color(vector_color), .vector_intensity(vector_intensity), .frame_done(frame_done),
	.vector_fault(vector_fault), .cpu_halted(cpu_halted), .watchdog_reset(watchdog_reset)
);
wire signed [15:0] audio;
aztarac_audio sound (
	.lowpass(status[54] ? status[53:52] : 2'd2),
	.clk(clk_sys), .reset(machine_reset || watchdog_reset), .pause(pause_cpu || nvram_busy),
	.rom_wr(sound_rom_wr), .rom_addr(ioctl_addr[12:0]), .rom_data(ioctl_data),
	.command(sound_command), .command_wr(sound_command_wr), .status(sound_status), .audio(audio)
);
wire        hblank, vblank, fifo_full, vector_overflow;
wire [15:0] sdram_out;
wire        sdram_oe;
wire [1:0]  sdram_dqm;
// status_guard commits the complete packet, including vertical offset bits 65:63.
wire [2:0] crt_vertical_position = settings_valid ? status[65:63] : 3'd0;
wire [2:0] crt_horizontal_position = settings_valid ? status[43:41] : 3'd0;

aztarac_video video (
	.clk_sys(clk_sys), .clk_125(clk_125), .reset(RESET), .upload_reset(!pll_locked),
	.reset_source      (machine_reset || watchdog_reset),
	.direct_video      (direct_video),
	.direct_video_31khz(status[115]),
	.crt_15khz_480i(!status[118]), .hdmi_width(HDMI_WIDTH), .hdmi_height(HDMI_HEIGHT),
	.crt_vertical_position(crt_vertical_position),
	.crt_horizontal_position(crt_horizontal_position),
	.aspect_ratio(status[15:14]),
	.orientation(status[21:20]), .active_orientation(active_orientation),
	.vector_x0(vector_x0), .vector_y0(vector_y0), .vector_x1(vector_x1), .vector_y1(vector_y1),
	.vector_color    (vector_color),
	.vector_intensity(vector_intensity),
	.vector_valid    (vector_valid),
	.frame_done      (frame_done),
	.vector_ready(), .vector_overflow(vector_overflow),
	.osd_120hz(status[25]), .osd_buffer_mode(status[40:39]),
	.osd_halo_shape(status[29:28] + 2'd3), // Menu zero selects B=2; retain renderer coefficient IDs.
	.effects_bypass(status[123]), .resolved_settings(resolved_settings),
	.artwork_enable(!status[24]), .artwork_labels_only(status[23]),
	.artwork_blend(3'd0), .artwork_available(),
	.artwork_brightness(status[12:10] + 3'd2), // Menu zero selects 100%; retain renderer gain IDs.
	.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index),
	.ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data), .ioctl_wait(artwork_wait),
	.video_arx(VIDEO_ARX),
	.video_ary(VIDEO_ARY),
	.ce_pixel (CE_PIXEL),
	.hblank   (hblank),
	.vblank   (vblank),
	.video_r(video_r),
	.video_g(video_g),
	.video_b(video_b),
	.hsync  (VGA_HS),
	.vsync  (VGA_VS),
	.field  (VGA_F1),
	.mode_supports_120hz(video_supports_120hz), .mode_is_15khz(video_is_15khz), .mode_is_crt(video_is_crt),
	.video_mode_toggle(video_mode_toggle), .video_freeze(video_freeze), .fifo_full(fifo_full),
	.profile_resolution(profile_resolution),
	.ddram_clk        (DDRAM_CLK),
	.ddram_busy       (DDRAM_BUSY),
	.ddram_burst_count(DDRAM_BURSTCNT),
	.ddram_address    (DDRAM_ADDR),
	.ddram_data_out(DDRAM_DOUT), .ddram_data_ready(DDRAM_DOUT_READY), .ddram_read(DDRAM_RD),
	.ddram_data_in(DDRAM_DIN), .ddram_byte_enable(DDRAM_BE), .ddram_write(DDRAM_WE),
	.sdram_data_in (SDRAM_DQ),
	.sdram_data_out(sdram_out),
	.sdram_data_oe (sdram_oe),
	.sdram_cke     (SDRAM_CKE),
	.sdram_ncs(SDRAM_nCS), .sdram_nras(SDRAM_nRAS), .sdram_ncas(SDRAM_nCAS), .sdram_nwe(SDRAM_nWE),
	.sdram_dqm(sdram_dqm), .sdram_address(SDRAM_A), .sdram_bank(SDRAM_BA)
);
assign SDRAM_DQ = sdram_oe ? sdram_out : 16'hzzzz;
assign {SDRAM_DQMH,SDRAM_DQML} = sdram_dqm;
// SDRAM samples halfway between the controller's rising-edge register updates.
assign SDRAM_CLK = ~clk_125;
assign CLK_VIDEO = clk_125;
assign {VGA_R,VGA_G,VGA_B} = paused_rgb;
assign VGA_DE         = !(hblank || vblank);
assign VGA_SL         = 0;
assign VGA_SCALER     = 0;
assign VGA_DISABLE    = 0;
assign HDMI_FREEZE    = video_freeze;
assign HDMI_BLACKOUT  = 0;
assign HDMI_BOB_DEINT = 0;
assign AUDIO_L        = audio;
assign AUDIO_R        = audio;
assign AUDIO_S        = 1;
assign AUDIO_MIX      = 0;
assign LED_USER       = ioctl_download || rom_error || nvram_error || fifo_full ||
                        vector_overflow || vector_fault || cpu_halted;
assign LED_DISK       =  0;
assign LED_POWER      =  0;
assign BUTTONS        =  0;
assign ADC_BUS        = 'z;
assign USER_OUT       = '1;
assign {UART_RTS,UART_TXD,UART_DTR} =   3'd0;
assign {SD_SCK,SD_MOSI,SD_CS}       = 3'bzzz;
`ifdef MISTER_DUAL_SDRAM
assign SDRAM2_DQ = 'z;
assign {SDRAM2_CLK,SDRAM2_A,SDRAM2_BA,SDRAM2_nCS,SDRAM2_nCAS,SDRAM2_nRAS,SDRAM2_nWE} = 'z;
`endif
endmodule

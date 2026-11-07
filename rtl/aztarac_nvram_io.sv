// Atomic host loading and upload completion for the 256x4 X2212 backing store.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

module aztarac_nvram_io (
	input  wire         clk, reset,
	input  wire         ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd,
	input  wire  [15:0] ioctl_index,
	input  wire  [26:0] ioctl_addr,
	input  wire  [7:0]  ioctl_data,
	input  wire         store, autosave, save_request,
	output logic [7:0]  address,
	output logic [3:0]  data,
	output logic        write,
	output logic        busy, request,
	output logic        dirty = 0,
	output logic        load_error = 0
);
	logic  [3:0] staging [0:255];
	logic        downloading_q = 0, uploading_q = 0;
	logic  [8:0] count           = 0;
	logic        committing      = 0;
	logic  [7:0] commit_address  = 0;
	logic        uploaded        = 0;
	logic        upload_error    = 0;
	logic  [8:0] upload_expected = 0;
	wire         downloading     = ioctl_download && ioctl_index == 16'd4;
	wire         uploading       = ioctl_upload && ioctl_index == 16'd4;
	wire   [8:0] expected_addr   = downloading_q ? count : 9'd0;
	assign       busy            = downloading || uploading || committing;
	assign       address         = committing ? commit_address : ioctl_addr[7:0];
	assign       data            = staging[commit_address];
	assign       write           = committing;
	assign       request         = ((autosave && dirty) || save_request) && !busy;
	always_ff @(posedge clk) begin
		if (reset) begin
			downloading_q <= 0;
			uploading_q   <= 0;
			count         <= 0;
			// Finish an accepted snapshot even if reset arrives during commit.
			if (committing) begin
				commit_address <= commit_address + 1'd1;
				if (commit_address == 255) begin
					committing <= 0;
					dirty      <= 0;
				end
			end else commit_address <= 0;
			uploaded                <= 0;
			upload_error            <= 0;
			upload_expected         <= 0;
			load_error              <= 0;
		end else begin
			downloading_q <= downloading;
			uploading_q   <= uploading;
			if (downloading && !downloading_q) begin
				count      <= 0;
				load_error <= committing;
			end
			if (downloading && ioctl_wr) begin
				if (!committing && (!downloading_q || !load_error) &&
					ioctl_addr == {18'd0,expected_addr} && expected_addr < 256) begin
					staging[ioctl_addr[7:0]] <= ioctl_data[3:0];
					count                    <= expected_addr + 1'd1;
				end else load_error <= 1;
			end
			if (!downloading && downloading_q) begin
				if (!load_error && count == 256) begin
					committing     <= 1;
					commit_address <= 0;
				end else load_error <= 1;
			end
			if (committing) begin
				commit_address <= commit_address + 1'd1;
				if (commit_address == 255) begin
					committing <= 0;
					dirty      <= 0;
				end
			end
			if (uploading && !uploading_q) begin
				uploaded        <= 0;
				upload_error    <= 0;
				upload_expected <= 0;
			end
			// hps_io requests address 256 after transmitting the final byte.
			if (uploading && ioctl_rd) begin
				if ((!uploading_q || !upload_error) &&
					ioctl_addr == (uploading_q ? {18'd0,upload_expected} : 27'd0) &&
					ioctl_addr <= 256) begin
					upload_expected <= (uploading_q ? upload_expected : 9'd0) + 1'd1;
					if (ioctl_addr == 256) uploaded <= 1;
				end else upload_error <= 1;
			end
			if (!uploading && uploading_q && uploaded && !upload_error) dirty <= 0;
			if (store)                                                  dirty <= 1;
		end
	end
endmodule

`default_nettype wire

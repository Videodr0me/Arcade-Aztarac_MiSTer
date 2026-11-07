// ============================================================================
// VART upload, descriptor validation, plane selection, and palette storage.
// Written 2026 by Videodr0me
// ============================================================================

`default_nettype none

module vfb_artwork_loader #(
	parameter logic [28:0] ARTWORK_BASE = vfb_layout_pkg::VFB_ARTWORK_BASE,
	parameter logic [28:0] ARTWORK_LAST = vfb_layout_pkg::VFB_ARTWORK_LAST,
	parameter integer      MAX_PLANES   = vfb_layout_pkg::VFB_ARTWORK_PLANES
) (
	input  wire                                clk_sys,
	input  wire                                clk_io,
	input  wire                                reset,
	input  wire                                upload_reset,
	input  wire                                arbiter_ready,
	input  wire                                video_timing_reset,
	input  wire  [11:0]                        render_width,
	input  wire  [11:0]                        render_height,
	input  wire  [1:0]                         artwork_orientation,
	input  wire                                artwork_labels_only,
	input  wire  [11:0]                        layout_width, layout_height,
	input  wire  [1:0]                         layout_orientation,
	output logic                               layout_valid = 0,
	output vfb_layout_pkg::vfb_viewport_t      layout_viewport,
	output vfb_layout_pkg::vfb_artwork_plane_t active_plane,

	input  wire         ioctl_download,
	input  wire         ioctl_wr,
	input  wire  [15:0] ioctl_index,
	input  wire  [26:0] ioctl_addr,
	input  wire  [7:0]  ioctl_data,
	output logic        ioctl_wait,

	input  wire         ce_pix,
	input  wire  [11:0] palette_read_addr,
	output logic [31:0] palette_data,

	output logic        upload_write_ready,
	input  wire         upload_write_done,
	output logic [28:0] upload_write_addr,
	output logic [7:0]  upload_write_burstcnt,
	output logic [63:0] upload_write_data,
	output logic [7:0]  upload_write_be,
	input  wire         upload_write_advance
);

	import vfb_layout_pkg::*;

	initial begin
		if ((MAX_PLANES < 1) || (MAX_PLANES > 24))
			$error("vfb_artwork_loader supports one to twenty-four VART planes");
		if (ARTWORK_LAST < ARTWORK_BASE)
			$error("vfb_artwork_loader requires an ordered artwork address range");
	end

	localparam integer      UPLOAD_EVENT_W         =    38;
	localparam integer      PALETTE_BYTES          = 16384;
	localparam integer      PALETTE_WORDS          = PALETTE_BYTES / 4;
	localparam integer      PLANE_INDEX_W          = (MAX_PLANES <= 1) ? 1 : $clog2(MAX_PLANES);
	localparam integer      LAYOUT_PLANES          = (MAX_PLANES < 12) ? MAX_PLANES : 12;
	localparam integer      LAYOUT_INDEX_W         = (LAYOUT_PLANES <= 1) ? 1 : $clog2(LAYOUT_PLANES);
	localparam logic [7:0]  MAX_PLANES_COUNT       = MAX_PLANES[7:0];
	localparam logic [26:0] DESCRIPTOR_STORAGE_END = 27'(64 + MAX_PLANES * 48);

	function automatic [31:0] crc32_byte(
		input logic [31:0] crc_in,
		input logic  [7:0] data
	);
		logic   [31:0] crc;
		integer        bit_index;
		begin
			crc = crc_in ^ {24'd0, data};
			for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
				crc = crc[0] ? ((crc >> 1) ^ 32'hedb88320) : (crc >> 1);
			crc32_byte = crc;
		end
	endfunction

	function automatic logic valid_dimensions(
		input logic [11:0] width,
		input logic [11:0] height
	);
		begin
			valid_dimensions = ((width == 12'd1440) && (height == 12'd1080)) ||
			                   ((width == 12'd1360) && (height == 12'd1080)) ||
			                   ((width == 12'd960)  && (height == 12'd720))  ||
			                   ((width == 12'd916)  && (height == 12'd720))  ||
			                   ((width == 12'd720)  && (height == 12'd480))  ||
			                   ((width == 12'd720)  && (height == 12'd240))  ||
			                   ((width == 12'd640)  && (height == 12'd480))  ||
			                   ((width == 12'd640)  && (height == 12'd240));
		end
	endfunction

	function automatic [31:0] expected_pixels(
		input logic [11:0] width,
		input logic [11:0] height
	);
		begin
			case ({width, height})
				{12'd1440, 12'd1080}: expected_pixels = 32'd1555200;
				{12'd1360, 12'd1080}: expected_pixels = 32'd1468800;
				{12'd960,  12'd720}:  expected_pixels =  32'd691200;
				{12'd916,  12'd720}:  expected_pixels =  32'd659520;
				{12'd720,  12'd480}:  expected_pixels =  32'd345600;
				{12'd720,  12'd240}:  expected_pixels =  32'd172800;
				{12'd640,  12'd480}:  expected_pixels =  32'd307200;
				{12'd640,  12'd240}:  expected_pixels =  32'd153600;
				default:              expected_pixels =       32'd0;
			endcase
		end
	endfunction

	wire                       upload_active        = ioctl_download && (ioctl_index == 16'd2);
	logic                      upload_active_q      = 1'b0;
	logic                      upload_start_pending = 1'b0;
	logic                      upload_end_pending   = 1'b0;
	logic                      upload_fifo_wr;
	logic [UPLOAD_EVENT_W-1:0] upload_fifo_wdata;
	wire                       upload_fifo_full;
	wire                       upload_fifo_almost_full;
	wire                       upload_rise           = upload_active && !upload_active_q;
	wire                       upload_fall           = !upload_active && upload_active_q;
	logic                      arbiter_ready_io_meta = 1'b0;
	logic                      arbiter_ready_io      = 1'b0;

	assign ioctl_wait = upload_active && (!arbiter_ready_io || upload_fifo_almost_full);

	always_ff @(posedge clk_io) begin
		if (upload_reset) begin
			arbiter_ready_io_meta <= 1'b0;
			arbiter_ready_io      <= 1'b0;
		end else begin
			arbiter_ready_io_meta <= arbiter_ready;
			arbiter_ready_io      <= arbiter_ready_io_meta;
		end
	end

	always_comb begin
		upload_fifo_wr    = 1'b0;
		upload_fifo_wdata =   '0;

		if (upload_active && ioctl_wr) begin
			upload_fifo_wr    = 1'b1;
			upload_fifo_wdata = {upload_start_pending || upload_rise, 1'b0,
			                     1'b1, ioctl_addr, ioctl_data};
		end else if (upload_start_pending || upload_rise) begin
			upload_fifo_wr    = 1'b1;
			upload_fifo_wdata = {1'b1, 1'b0, 1'b0, 27'd0, 8'd0};
		end else if (upload_end_pending || upload_fall) begin
			upload_fifo_wr    = 1'b1;
			upload_fifo_wdata = {1'b0, 1'b1, 1'b0, 27'd0, 8'd0};
		end
	end

	always_ff @(posedge clk_io) begin
		if (upload_reset) begin
			upload_active_q      <= 1'b0;
			upload_start_pending <= 1'b0;
			upload_end_pending   <= 1'b0;
		end else begin
			upload_active_q <= upload_active;

			if (upload_rise) upload_start_pending <= 1'b1;
			if (upload_fall) upload_end_pending   <= 1'b1;

			if (upload_fifo_wr && !upload_fifo_full) begin
				if (upload_active && ioctl_wr) begin
					upload_start_pending <= 1'b0;
				end else if (upload_start_pending || upload_rise) begin
					upload_start_pending <= 1'b0;
				end else if (upload_end_pending || upload_fall) begin
					upload_end_pending <= 1'b0;
				end
			end
		end
	end

	logic                      upload_fifo_rd = 1'b0;
	wire  [UPLOAD_EVENT_W-1:0] upload_fifo_rdata;
	wire                       upload_fifo_rd_valid;
	wire                       upload_fifo_empty;
	logic [UPLOAD_EVENT_W-1:0] upload_event_q     =   '0;
	logic                      upload_event_valid = 1'b0;

	vfb_async_fifo #(
		.WIDTH(UPLOAD_EVENT_W),
		.DEPTH(64),
		.ALMOST_FULL_MARGIN(2)
	) upload_fifo (
		.wr_clk(clk_io),
		.wr_reset(upload_reset),
		.wr_en(upload_fifo_wr),
		.wr_data(upload_fifo_wdata),
		.wr_full(upload_fifo_full),
		.wr_almost_full(upload_fifo_almost_full),
		.rd_clk(clk_sys),
		.rd_reset(upload_reset),
		.rd_en(upload_fifo_rd),
		.rd_data(upload_fifo_rdata),
		.rd_valid(upload_fifo_rd_valid),
		.rd_empty(upload_fifo_empty)
	);

	always_ff @(posedge clk_sys) begin
		if (upload_reset) begin
			upload_event_q     <=   '0;
			upload_event_valid <= 1'b0;
		end else if (upload_fifo_rd_valid) begin
			upload_event_q     <= upload_fifo_rdata;
			upload_event_valid <= 1'b1;
		end else if (upload_event_valid) begin
			upload_event_valid <= 1'b0;
		end
	end

	wire        upload_event_start    = upload_event_q[37];
	wire        upload_event_end      = upload_event_q[36];
	wire        upload_event_has_data = upload_event_q[35];
	wire [26:0] upload_event_addr     = upload_event_q[34:8];
	wire [7:0]  upload_event_data     = upload_event_q[7:0];

	// ------------------------------------------------------------------------
	// VART upload, metadata, and palette capture
	// ------------------------------------------------------------------------

	logic        package_valid         =         1'b0;
	logic        upload_in_progress    =         1'b0;
	logic        upload_event_pending  =         1'b0;
	logic        upload_finalize       =         1'b0;
	logic        upload_validate       =         1'b0;
	logic        upload_final_write    =         1'b0;
	logic        upload_error          =         1'b0;
	logic [26:0] upload_expected_addr  =        27'd0;
	logic [31:0] upload_received_bytes =        32'd0;
	logic [31:0] upload_crc            = 32'hffffffff;
	logic [63:0] upload_pack_data      =        64'd0;
	logic [7:0]  upload_pack_be        =         8'd0;
	logic        upload_qword_pending  =         1'b0;
	logic [28:0] upload_qword_addr     = ARTWORK_BASE;
	logic [63:0] upload_qword_data     = 64'd0;
	logic [7:0]  upload_qword_be       =  8'd0;

	logic [7:0]               vart_layer_count        =   8'd0;
	logic [7:0]               vart_version            =      0;
	logic [7:0]               vart_plane_count        =   8'd0;
	logic [31:0]              vart_total_size         =  32'd0;
	logic [31:0]              vart_expected_crc       =  32'd0;
	logic [31:0]              vart_descriptor_offset  =  32'd0;
	logic [15:0]              vart_descriptor_size    =  16'd0;
	logic [26:0]              descriptor_region_end   = 27'd64;
	logic [PLANE_INDEX_W-1:0] descriptor_slot         =     '0;
	logic [5:0]               descriptor_byte         =   6'd0;
	logic                     descriptor_write_q      =   1'b0;
	logic [PLANE_INDEX_W-1:0] descriptor_write_slot_q =     '0;
	logic [5:0]               descriptor_write_byte_q =   6'd0;
	logic [7:0]               descriptor_write_data_q =   8'd0;

	// One upload scratch record holds fields until their full-width checks finish.
	typedef struct packed {
		logic [11:0]   width, height;
		logic [7:0]    layer, role, index_bits, flags;
		logic [15:0]   palette_entries;
		logic [31:0]   palette_offset, palette_size, payload_offset, payload_size;
		logic [31:0]   pixel_count, row_count, layout;
		vfb_viewport_t viewport;
	} descriptor_t;
	descriptor_t descriptor = '0;

	// Validated offsets are eight-byte aligned and bounded by the package window.
	typedef struct packed {
		logic                    foreground;
		vfb_artwork_index_mode_t index_mode;
		logic [10:0]             palette_word;
		logic [18:0]             payload_word;
		logic [19:0]             payload_words;
	} plane_record_t;
	typedef struct packed {
		logic [11:0]   width, height;
		logic [1:0]    orientation;
		vfb_viewport_t viewport;
	} plane_geometry_t;
	plane_record_t   plane_record [0:MAX_PLANES-1];
	plane_geometry_t plane_geometry [0:LAYOUT_PLANES-1];
	plane_geometry_t pair_geometry_q;

	logic [2:0]  descriptor_check    = '0;
	logic [3:0]  descriptor_checks_q = '0;
	logic [7:0]  descriptors_done    =  0;
	logic [32:0] palette_end_q, payload_end_q;
	logic [12:0] viewport_right_q, viewport_bottom_q;

	(* ramstyle = "M10K, no_rw_check" *)
	logic [31:0] palette_memory [0:PALETTE_WORDS-1];
	logic [31:0] palette_read_data  = 32'd0;
	logic [23:0] palette_upload_rgb = 24'd0;

	always_ff @(posedge clk_sys) begin
		if (upload_reset || (upload_event_valid && upload_event_start)) begin
			palette_upload_rgb <= 24'd0;
		end else if (upload_event_valid && upload_event_has_data &&
		    upload_in_progress && (upload_event_addr[26:14] == 13'd0)) begin
			case (upload_event_addr[1:0])
				2'd0: palette_upload_rgb[7:0]   <= upload_event_data;
				2'd1: palette_upload_rgb[15:8]  <= upload_event_data;
				2'd2: palette_upload_rgb[23:16] <= upload_event_data;
				default:
					palette_memory[upload_event_addr[13:2]] <= {upload_event_data,
					                                            palette_upload_rgb};
			endcase
		end
		if (ce_pix) palette_read_data <= palette_memory[palette_read_addr];
	end

	logic metadata_global_valid_q = 1'b0;
	wire  metadata_valid          = metadata_global_valid_q && !upload_error &&
	                                (descriptors_done == vart_plane_count);
	always_ff @(posedge clk_sys) begin
		if (upload_reset || (upload_event_valid && upload_event_start))
			metadata_global_valid_q <= 1'b0;
		else if (upload_finalize)
			metadata_global_valid_q <= (vart_layer_count >= 1) &&
			                           (vart_layer_count <= 2) &&
			                           (vart_plane_count >= 1) &&
			                           (vart_plane_count <= MAX_PLANES_COUNT) &&
			                           (vart_version == 4 ? vart_plane_count == 24
			                                              : vart_plane_count <= 12) &&
			                           (vart_descriptor_offset == 32'd64) &&
			                           (vart_descriptor_size == 16'd48) &&
			                           (vart_total_size >=
			                            (32'd64 + ({24'd0, vart_plane_count} * 32'd48))) &&
			                           (vart_total_size <= 32'd4194304) &&
			                           ((({3'd0, vart_total_size} + 35'd7) >> 3) <=
			                            ({6'd0, ARTWORK_LAST} - {6'd0, ARTWORK_BASE} + 1'b1)) &&
			                           (upload_received_bytes == vart_total_size) &&
			                           ((~upload_crc) == vart_expected_crc);
	end

	assign upload_write_ready    = upload_qword_pending;
	assign upload_write_addr     = upload_qword_addr;
	assign upload_write_burstcnt = 8'd1;
	assign upload_write_data     = upload_qword_data;
	assign upload_write_be       = upload_qword_be;

	always_ff @(posedge clk_sys) begin
		upload_fifo_rd     <= 1'b0;
		descriptor_write_q <= 1'b0;
		descriptor_check   <= {descriptor_check[1:0], 1'b0};

		if (upload_reset) begin
			package_valid         <=   1'b0;
			descriptor            <=     '0;
			descriptor_check      <=     '0;
			descriptors_done      <=      0;
			upload_in_progress    <=   1'b0;
			upload_event_pending  <=   1'b0;
			upload_finalize       <=   1'b0;
			upload_validate       <=   1'b0;
			upload_final_write    <=   1'b0;
			upload_qword_pending  <=   1'b0;
			upload_pack_be        <=   8'd0;
			descriptor_region_end <= 27'd64;
			descriptor_slot       <=     '0;
			descriptor_byte       <=   6'd0;
			descriptor_write_q    <=   1'b0;
		end else begin
			if (descriptor_write_q) begin
				if (descriptor_write_byte_q == 6'd47) descriptor_check <= 3'b001;
				if (vart_version == 1 && descriptor_write_byte_q >= 6'd40) begin
					// Legacy reserved bytes must be zero; store the full-plane viewport.
					if (descriptor_write_data_q != 0)     upload_error        <= 1'b1;
					if (descriptor_write_byte_q == 6'd47)
						descriptor.viewport <= {12'd0, 12'd0, descriptor.width, descriptor.height};
				end else case (descriptor_write_byte_q)
					0:              descriptor.width[7:0] <= descriptor_write_data_q;
					1:              begin
						descriptor.width[11:8] <= descriptor_write_data_q[3:0];
						if (descriptor_write_data_q[7:4] != 4'd0) upload_error <= 1'b1;
					end
					2:              descriptor.height[7:0] <= descriptor_write_data_q;
					3:              begin
						descriptor.height[11:8] <= descriptor_write_data_q[3:0];
						if (descriptor_write_data_q[7:4] != 4'd0) upload_error <= 1'b1;
					end
					4:              descriptor.layer                 <= descriptor_write_data_q;
					5:              descriptor.role                  <= descriptor_write_data_q;
					6:              descriptor.index_bits            <= descriptor_write_data_q;
					7:              descriptor.flags                 <= descriptor_write_data_q;
					8:              descriptor.palette_entries[7:0]  <= descriptor_write_data_q;
					9:              descriptor.palette_entries[15:8] <= descriptor_write_data_q;
					12:             descriptor.palette_offset[7:0]   <= descriptor_write_data_q;
					13:             descriptor.palette_offset[15:8]  <= descriptor_write_data_q;
					14:             descriptor.palette_offset[23:16] <= descriptor_write_data_q;
					15:             descriptor.palette_offset[31:24] <= descriptor_write_data_q;
					16:             descriptor.palette_size[7:0]     <= descriptor_write_data_q;
					17:             descriptor.palette_size[15:8]    <= descriptor_write_data_q;
					18:             descriptor.palette_size[23:16]   <= descriptor_write_data_q;
					19:             descriptor.palette_size[31:24]   <= descriptor_write_data_q;
					20:             descriptor.payload_offset[7:0]   <= descriptor_write_data_q;
					21:             descriptor.payload_offset[15:8]  <= descriptor_write_data_q;
					22:             descriptor.payload_offset[23:16] <= descriptor_write_data_q;
					23:             descriptor.payload_offset[31:24] <= descriptor_write_data_q;
					24:             descriptor.payload_size[7:0]     <= descriptor_write_data_q;
					25:             descriptor.payload_size[15:8]    <= descriptor_write_data_q;
					26:             descriptor.payload_size[23:16]   <= descriptor_write_data_q;
					27:             descriptor.payload_size[31:24]   <= descriptor_write_data_q;
					28:             descriptor.pixel_count[7:0]      <= descriptor_write_data_q;
					29:             descriptor.pixel_count[15:8]     <= descriptor_write_data_q;
					30:             descriptor.pixel_count[23:16]    <= descriptor_write_data_q;
					31:             descriptor.pixel_count[31:24]    <= descriptor_write_data_q;
					32:             descriptor.row_count[7:0]        <= descriptor_write_data_q;
					33:             descriptor.row_count[15:8]       <= descriptor_write_data_q;
					34:             descriptor.row_count[23:16]      <= descriptor_write_data_q;
					35:             descriptor.row_count[31:24]      <= descriptor_write_data_q;
					36:             descriptor.layout[7:0]           <= descriptor_write_data_q;
					37:             descriptor.layout[15:8]          <= descriptor_write_data_q;
					38:             descriptor.layout[23:16]         <= descriptor_write_data_q;
					39:             descriptor.layout[31:24]         <= descriptor_write_data_q;
					40:             descriptor.viewport.x[7:0]       <= descriptor_write_data_q;
					42:             descriptor.viewport.y[7:0]       <= descriptor_write_data_q;
					44:             descriptor.viewport.width[7:0]   <= descriptor_write_data_q;
					46:             descriptor.viewport.height[7:0]  <= descriptor_write_data_q;
					41, 43, 45, 47: begin
						if(descriptor_write_data_q[7:4] != 0) upload_error <= 1;
						case(descriptor_write_byte_q)
							41:      descriptor.viewport.x[11:8]      <= descriptor_write_data_q[3:0];
							43:      descriptor.viewport.y[11:8]      <= descriptor_write_data_q[3:0];
							45:      descriptor.viewport.width[11:8]  <= descriptor_write_data_q[3:0];
							default: descriptor.viewport.height[11:8] <= descriptor_write_data_q[3:0];
						endcase
					end
					10, 11:
						if (descriptor_write_data_q != 8'd0) upload_error <= 1'b1;
					default: ;
				endcase
			end

			// Check one complete descriptor; the FIFO pauses until its record is stored.
			if (descriptor_check[0]) begin
				palette_end_q     <= {1'b0, descriptor.palette_offset} +
				                     {1'b0, descriptor.palette_size};
				payload_end_q     <= {1'b0, descriptor.payload_offset} +
				                     {1'b0, descriptor.payload_size};
				viewport_right_q  <= {1'b0, descriptor.viewport.x} +
				                     {1'b0, descriptor.viewport.width};
				viewport_bottom_q <= {1'b0, descriptor.viewport.y} +
				                     {1'b0, descriptor.viewport.height};
				if (vart_version == 4 && int'(descriptor_write_slot_q) >= 12)
					pair_geometry_q <=
					    plane_geometry[LAYOUT_INDEX_W'(descriptor_write_slot_q - PLANE_INDEX_W'(12))];
			end
			if (descriptor_check[1]) begin
				descriptor_checks_q[0] <=
				    valid_dimensions(descriptor.width, descriptor.height)
				    && (descriptor.pixel_count ==
				        expected_pixels(descriptor.width, descriptor.height))
				    && (descriptor.row_count == {20'd0, descriptor.height})
				    && ((vart_version == 1 &&
				         descriptor.layout == 0 &&
				         descriptor.viewport ==
				         {12'd0, 12'd0, descriptor.width, descriptor.height}) ||
				        ((vart_version == 3 || vart_version == 4) &&
				         descriptor.layout[31:3] == 0 &&
				         descriptor.layout[1:0] <= 2 &&
				         descriptor.layout[2] ==
				         (vart_version == 4 && descriptor_write_slot_q >= 12) &&
				         descriptor.viewport.width > 1 &&
				         descriptor.viewport.height > 1 &&
				         viewport_right_q <= {1'b0, descriptor.width} &&
				         viewport_bottom_q <= {1'b0, descriptor.height}))
				    && (vart_version != 4 ||
				        descriptor_write_slot_q < 12 ||
				        (descriptor.width == pair_geometry_q.width &&
				         descriptor.height == pair_geometry_q.height &&
				         descriptor.layout[1:0] == pair_geometry_q.orientation &&
				         descriptor.viewport == pair_geometry_q.viewport));
				descriptor_checks_q[1] <=
				    (descriptor.layer < vart_layer_count)
				    && (descriptor.role <= 8'd1)
				    && ((descriptor.index_bits == 8'd4) ||
				        (descriptor.index_bits == 8'd6) ||
				        (descriptor.index_bits == 8'd8))
				    && ((descriptor.flags & 8'hfc) == 8'd0)
				    && descriptor.flags[0]
				    && (descriptor.palette_entries == (16'd1 << descriptor.index_bits));
				descriptor_checks_q[2] <= (descriptor.palette_size ==
				                           ({16'd0, descriptor.palette_entries} << 2)) &&
				                          (descriptor.palette_offset[2:0] == 3'd0) &&
				                          (palette_end_q <= 33'd16384) &&
				                          (palette_end_q <= {1'b0, vart_total_size});
				descriptor_checks_q[3] <= (descriptor.payload_offset[2:0] == 3'd0) &&
				                          (descriptor.payload_size[2:0] == 3'd0) &&
				                          (descriptor.payload_size != 32'd0) &&
				                          (payload_end_q <= {1'b0, vart_total_size});
			end
			if (descriptor_check[2]) begin
				descriptors_done <= descriptors_done + 1'b1;
				if (&descriptor_checks_q) begin
					plane_record[descriptor_write_slot_q] <= '{
						foreground:descriptor.role == 8'd1,
						index_mode:descriptor.index_bits == 8'd4 ? INDEX_MODE_4 :
						           descriptor.index_bits == 8'd6 ? INDEX_MODE_6 : INDEX_MODE_8,
						palette_word:descriptor.palette_offset[13:3],
						payload_word:descriptor.payload_offset[21:3],
						payload_words:descriptor.payload_size[22:3]};
					if (int'(descriptor_write_slot_q) < LAYOUT_PLANES)
						plane_geometry[LAYOUT_INDEX_W'(descriptor_write_slot_q)] <= '{
							width:       descriptor.width,       height:   descriptor.height,
							orientation: descriptor.layout[1:0], viewport: descriptor.viewport};
				end else upload_error <= 1'b1;
			end

			if (upload_write_advance) upload_qword_pending <= 1'b0;

			if (arbiter_ready && !upload_event_pending &&
			    !upload_fifo_empty && !upload_qword_pending &&
			    !upload_finalize && !upload_validate && !(|descriptor_check) &&
			    !(descriptor_write_q && descriptor_write_byte_q == 6'd47)) begin
				upload_fifo_rd       <= 1'b1;
				upload_event_pending <= 1'b1;
			end

			if (upload_event_valid) begin
				logic [63:0] next_pack_data;
				logic [7:0]  next_pack_be;
				logic [31:0] crc_base;

				upload_event_pending <= 1'b0;

				if (upload_event_start) begin
					descriptor             <=           '0;
					descriptor_check       <=           '0;
					descriptors_done       <=            0;
					package_valid          <=         1'b0;
					upload_in_progress     <=         1'b1;
					upload_finalize        <=         1'b0;
					upload_validate        <=         1'b0;
					upload_final_write     <=         1'b0;
					upload_error           <=         1'b0;
					upload_expected_addr   <=        27'd0;
					upload_received_bytes  <=        32'd0;
					upload_crc             <= 32'hffffffff;
					upload_pack_be         <=         8'd0;
					vart_layer_count       <=         8'd0;
					vart_version           <=         8'd0;
					vart_plane_count       <=         8'd0;
					vart_total_size        <=        32'd0;
					vart_expected_crc      <=        32'd0;
					vart_descriptor_offset <=        32'd0;
					vart_descriptor_size   <=        16'd0;
					descriptor_region_end  <=       27'd64;
					descriptor_slot        <=           '0;
					descriptor_byte        <=         6'd0;
				end

				if (upload_event_has_data && (upload_in_progress || upload_event_start)) begin
					next_pack_data = upload_pack_data;
					next_pack_be   = upload_event_start ? 8'd0 : upload_pack_be;
					crc_base       = upload_event_start ? 32'hffffffff : upload_crc;

					if (upload_event_addr != (upload_event_start ? 27'd0 : upload_expected_addr))
						upload_error <= 1'b1;
					upload_expected_addr  <= upload_event_addr + 1'b1;
					upload_received_bytes <= (upload_event_start ? 32'd0 : upload_received_bytes) +
					                         1'b1;

					next_pack_data[upload_event_addr[2:0] * 8 +: 8] = upload_event_data;
					next_pack_be[upload_event_addr[2:0]]            = 1'b1;
					if (upload_event_addr[2:0] == 3'd7) begin
						upload_qword_pending <= 1'b1;
						upload_qword_addr    <= ARTWORK_BASE + {5'd0, upload_event_addr[26:3]};
						upload_qword_data    <= next_pack_data;
						upload_qword_be      <= next_pack_be;
						upload_pack_be       <= 8'd0;
					end else begin
						upload_pack_data <= next_pack_data;
						upload_pack_be   <= next_pack_be;
					end

					if (upload_event_addr >= 27'd64)
						upload_crc <= crc32_byte(crc_base, upload_event_data);

					case (upload_event_addr)
						27'd0:  if (upload_event_data != 8'h56) upload_error <= 1'b1;
						27'd1:  if (upload_event_data != 8'h41) upload_error <= 1'b1;
						27'd2:  if (upload_event_data != 8'h52) upload_error <= 1'b1;
						27'd3:  if (upload_event_data != 8'h54) upload_error <= 1'b1;
						27'd4:  begin
							vart_version <= upload_event_data;
							if(upload_event_data != 1 && upload_event_data != 3 && upload_event_data != 4)
								upload_error <= 1;
						end
						27'd5:  if (upload_event_data != 8'd0) upload_error <= 1'b1;
						27'd6:  vart_layer_count <= upload_event_data;
						27'd7:  begin
							vart_plane_count      <= upload_event_data;
							descriptor_region_end <= 27'd64 +
							                         ({19'd0, upload_event_data} << 5) +
							                         ({19'd0, upload_event_data} << 4);
						end
						27'd8:  vart_total_size[7:0]          <= upload_event_data;
						27'd9:  vart_total_size[15:8]         <= upload_event_data;
						27'd10: vart_total_size[23:16]        <= upload_event_data;
						27'd11: vart_total_size[31:24]        <= upload_event_data;
						27'd12: vart_expected_crc[7:0]        <= upload_event_data;
						27'd13: vart_expected_crc[15:8]       <= upload_event_data;
						27'd14: vart_expected_crc[23:16]      <= upload_event_data;
						27'd15: vart_expected_crc[31:24]      <= upload_event_data;
						27'd16: vart_descriptor_offset[7:0]   <= upload_event_data;
						27'd17: vart_descriptor_offset[15:8]  <= upload_event_data;
						27'd18: vart_descriptor_offset[23:16] <= upload_event_data;
						27'd19: vart_descriptor_offset[31:24] <= upload_event_data;
						27'd20: vart_descriptor_size[7:0]     <= upload_event_data;
						27'd21: vart_descriptor_size[15:8]    <= upload_event_data;
						default:
							if ((upload_event_addr >= 27'd22) &&
							    (upload_event_addr < 27'd64) &&
							    (upload_event_data != 8'd0))
								upload_error <= 1'b1;
					endcase

					if ((upload_event_addr >= 27'd64) &&
					    (upload_event_addr < descriptor_region_end) &&
					    (upload_event_addr < DESCRIPTOR_STORAGE_END)) begin
						descriptor_write_q      <= 1'b1;
						descriptor_write_slot_q <= descriptor_slot;
						descriptor_write_byte_q <= descriptor_byte;
						descriptor_write_data_q <= upload_event_data;
						if (descriptor_byte == 6'd47) begin
							descriptor_byte <= 6'd0;
							descriptor_slot <= descriptor_slot + 1'b1;
						end else begin
							descriptor_byte <= descriptor_byte + 1'b1;
						end
					end
				end

				if (upload_event_end && upload_in_progress) begin
					upload_finalize    <= 1'b1;
					upload_final_write <= (upload_pack_be != 8'd0);
					if (upload_pack_be != 8'd0) begin
						upload_qword_pending <= 1'b1;
						upload_qword_addr    <= ARTWORK_BASE + {5'd0, upload_expected_addr[26:3]};
						upload_qword_data    <= upload_pack_data;
						upload_qword_be      <= upload_pack_be;
						upload_pack_be       <= 8'd0;
					end
				end
			end

			if (upload_finalize && (!upload_final_write || upload_write_done)) begin
				upload_finalize    <= 1'b0;
				upload_validate    <= 1'b1;
				upload_final_write <= 1'b0;
			end

			if (upload_validate) begin
				package_valid      <= metadata_valid;
				upload_in_progress <= 1'b0;
				upload_validate    <= 1'b0;
			end
		end
	end

	// Register descriptor matches, priority selection, and the active plane.
	logic   [LAYOUT_PLANES-1:0] plane_match_q = '0;
	logic                       selected_plane_valid_d;
	logic   [PLANE_INDEX_W-1:0] selected_plane_index_d;
	logic                       selected_plane_valid_q = 1'b0;
	logic   [PLANE_INDEX_W-1:0] selected_plane_index_q =   '0;
	integer                     match_index;
	integer                     priority_index;
	logic                       priority_found;

	// Register each descriptor match before selecting the first one.
	always_ff @(posedge clk_sys) begin
		if (reset || video_timing_reset || !package_valid) begin
			plane_match_q <= '0;
		end else begin
			for (match_index = 0; match_index < LAYOUT_PLANES; match_index = match_index + 1) begin
				plane_match_q[match_index] <= (match_index < vart_plane_count) &&
				                              (plane_geometry[match_index].width == render_width) &&
				                              (plane_geometry[match_index].height ==
				                               render_height) &&
				                              (vart_version == 1 ||
				                               plane_geometry[match_index].orientation ==
				                               artwork_orientation);
			end
		end
	end

	// Query the upcoming layout independently of renderer reset. The wrapper
	// commits its viewport and orientation together at a frozen frame boundary.
	logic [LAYOUT_PLANES-1:0]  layout_match = '0;
	logic                      layout_found;
	logic [LAYOUT_INDEX_W-1:0] layout_index;
	logic [LAYOUT_INDEX_W-1:0] layout_index_q =   '0;
	logic                      layout_found_q = 1'b0;
	logic [11:0]               layout_width_q = 12'd0, layout_height_q = 12'd0;
	logic [1:0]                layout_orientation_q = 2'd0;
	always_ff @(posedge clk_sys) begin
		layout_width_q       <= layout_width;
		layout_height_q      <= layout_height;
		layout_orientation_q <= layout_orientation;
		for(integer index=0;index<LAYOUT_PLANES;index++)
			layout_match[index] <=
			    package_valid
			    && index < vart_plane_count
			    && plane_geometry[index].width == layout_width_q
			    && plane_geometry[index].height == layout_height_q
			    && (vart_version == 1 || plane_geometry[index].orientation == layout_orientation_q);
		layout_index_q  <= layout_index;
		layout_found_q  <= package_valid && layout_found;
		layout_valid    <= package_valid && layout_found_q;
		layout_viewport <= layout_found_q ? plane_geometry[layout_index_q].viewport : '0;
	end
	always_comb begin
		layout_found =  0;
		layout_index = '0;
		for(integer index=0;index<LAYOUT_PLANES;index++) begin
			if(layout_match[index] && !layout_found) begin
				layout_found = 1;
				layout_index = LAYOUT_INDEX_W'(index);
			end
		end
	end

	always_comb begin
		selected_plane_valid_d = 1'b0;
		selected_plane_index_d =   '0;
		priority_found         = 1'b0;

		for (priority_index = 0; priority_index < LAYOUT_PLANES; priority_index = priority_index + 1) begin
			if (!priority_found && plane_match_q[priority_index]) begin
				selected_plane_valid_d = 1'b1;
				selected_plane_index_d = artwork_labels_only ? PLANE_INDEX_W'(priority_index + 12)
				                                             : PLANE_INDEX_W'(priority_index);
				priority_found         = 1'b1;
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset || video_timing_reset || !package_valid) begin
			selected_plane_valid_q <= 1'b0;
			selected_plane_index_q <=   '0;
		end else begin
			selected_plane_valid_q <= selected_plane_valid_d &&
			                          (!artwork_labels_only || vart_version == 4);
			selected_plane_index_q <= selected_plane_index_d;
		end
	end

	// Read one compact descriptor, then expand it into the active video registers.
	plane_record_t      selected_record_q =   '0;
	logic               record_valid_q    = 1'b0;
	vfb_artwork_plane_t active_plane_q    =   '0;
	always_ff @(posedge clk_sys) begin
		if (reset || video_timing_reset || !package_valid) begin
			record_valid_q    <= 1'b0;
			selected_record_q <=   '0;
			active_plane_q    <=   '0;
		end else begin
			record_valid_q <= selected_plane_valid_q;
			if (selected_plane_valid_q) selected_record_q <= plane_record[selected_plane_index_q];
			active_plane_q <= '{
				ready:record_valid_q,
				foreground:selected_record_q.foreground,
				index_mode:selected_record_q.index_mode,
				index_bits:selected_record_q.index_mode == INDEX_MODE_4 ? 7'd4 :
				           selected_record_q.index_mode == INDEX_MODE_6 ? 7'd6 : 7'd8,
				palette_offset:{18'd0, selected_record_q.palette_word, 3'd0},
				payload_offset:{10'd0, selected_record_q.payload_word, 3'd0},
				payload_size:{9'd0, selected_record_q.payload_words, 3'd0}};
		end
	end

	assign palette_data = palette_read_data;
	assign active_plane = {active_plane_q.ready && package_valid,
	                       active_plane_q.foreground, active_plane_q.index_mode,
	                       active_plane_q.index_bits, active_plane_q.palette_offset,
	                       active_plane_q.payload_offset, active_plane_q.payload_size};

endmodule

`default_nettype wire

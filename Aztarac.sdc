derive_pll_clocks
derive_clock_uncertainty

# CPU, sound and host transfers use enables in the 50 MHz source domain.
# Pixel and EOF payloads cross through the renderer's asynchronous FIFO.
set vfb_clk [get_clocks {emu|pll_vfb|pll_vfb_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set_clock_groups -asynchronous -group $vfb_clk \
	-group [get_clocks {FPGA_CLK1_50}] \
	-group [get_clocks {*|h2f_user0_clk}] \
	-group [get_clocks {pll_audio|*divclk}] \
	-group [get_clocks {pll_hdmi|*output_counter|divclk}] \
	-group [get_clocks {FPGA_CLK2_50}] \
	-group [get_clocks {FPGA_CLK3_50}]

# Bound Gray routes to 80% of their source period (50 MHz / 125 MHz).
set_net_delay -max 16.000 \
	-from [get_registers {*|rasterizer_inst|wr_ptr_g[*]}] \
	-to [get_registers {*|rasterizer_inst|wr_ptr_g_sync1[*]}]
set_net_delay -max 6.400 \
	-from [get_registers {*|rasterizer_inst|rd_ptr_g[*]}] \
	-to [get_registers {*|rasterizer_inst|rd_ptr_g_sync1[*]}]
set_net_delay -max 16.000 \
	-from [get_registers {*|artwork_overlay|loader|upload_fifo|wr_gray[*]}] \
	-to [get_registers {*|artwork_overlay|loader|upload_fifo|wr_gray_meta[*]}]
set_net_delay -max 6.400 \
	-from [get_registers {*|artwork_overlay|loader|upload_fifo|rd_gray[*]}] \
	-to [get_registers {*|artwork_overlay|loader|upload_fifo|rd_gray_meta[*]}]

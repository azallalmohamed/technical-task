create_clock -name clk -period 10.000 [get_ports clk_i]
set_false_path -from [get_ports btn_rst_i]
set_false_path -to [get_ports {led_o[*]}]

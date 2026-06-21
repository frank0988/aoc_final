# Course lab6-compatible timing and I/O constraints.
set clk_period 1.2
set input_max   [expr {double(round(1000*$clk_period * 0.6))/1000}]
set input_min   [expr {double(round(1000*$clk_period * 0.0))/1000}]
set output_max  [expr {double(round(1000*$clk_period * 0.1))/1000}]
set output_min  [expr {double(round(1000*$clk_period * 0.0))/1000}]

create_clock -name clk -period $clk_period [get_ports clk]
set_dont_touch_network [all_clocks]
set_fix_hold [get_clocks clk]
set_clock_uncertainty 0.02 [get_clocks clk]
set_clock_latency 0.2 [get_clocks clk]
set_clock_latency -source 0 [get_clocks clk]
set_ideal_network [get_clocks clk]
set_input_transition 0.2 [all_inputs]
set_clock_transition 0.1 [get_clocks clk]

set_operating_conditions -min_library N16ADFP_StdCellff0p88v125c -min ff0p88v125c \
                         -max_library N16ADFP_StdCellss0p72vm40c -max ss0p72vm40c
set_driving_cell -library N16ADFP_StdCellss0p72vm40c -lib_cell BUFFD4BWP16P90LVT -pin {Z} [get_ports clk]
set_driving_cell -library N16ADFP_StdCellss0p72vm40c -lib_cell DFQD1BWP16P90LVT -pin {Q} [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -clock clk -max $input_max [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -clock clk -min $input_min [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock clk -max $output_max [all_outputs]
set_output_delay -clock clk -min $output_min [all_outputs]
set_wire_load_model -name ZeroWireload -library N16ADFP_StdCellss0p72vm40c
set_max_area 0
set_max_fanout 10 [all_inputs]
set_max_transition 0.1 [all_inputs]
set_max_capacitance 0.1 [all_inputs]

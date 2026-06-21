set root [file normalize [file join [pwd] ..]]
set_app_var search_path [concat $search_path [list $root $root/src $root/hw $root/SRAM]]
set rtl [list \
    $root/src/encode.sv $root/src/decode.sv $root/src/weight.sv \
    $root/hw/input_RLC_decoder.v $root/hw/sram_macro_wrapper.sv \
    $root/hw/input_sram_wrapper.sv $root/hw/weight_sram_wrapper.sv \
    $root/hw/weight_pingpong_wrapper.sv $root/hw/Controller.sv \
    $root/hw/pe_block_7x3.v $root/hw/boundart_sram_wrapper.sv \
    $root/hw/accumulator.sv $root/hw/PostQuant.sv $root/hw/ReLU_Qint8.sv \
    $root/hw/Maxpool_Qint8.sv $root/hw/PPU.sv $root/hw/PPU_to_RLC_Packer.sv \
    $root/hw/output_RLC_encoder.v $root/top.sv]

analyze -format sverilog $rtl
elaborate top
current_design top
link
uniquify
set_host_options -max_core 16
source $root/script/DC.sdc
compile -exact_map -map_effort high
remove_unconnected_ports -blast_buses [get_cells * -hier]

set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed "A-Z a-z 0-9 _" -max_length 255 -type cell
define_name_rules name_rule -allowed "A-Z a-z 0-9 _[]" -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

file mkdir $root/syn
write_file -format verilog -hier -output $root/syn/top_syn.v
write_sdf -version 2.1 -context verilog -load_delay net $root/syn/top_syn.sdf
report_timing > $root/syn/timing.log
report_area > $root/syn/area.log
report_power > $root/syn/power.log
report_timing -path full -delay max -nworst 1 -max_paths 1 -significant_digits 2 -sort_by group > $root/syn/timing_max_rpt.txt
report_timing -path full -delay min -nworst 1 -max_paths 1 -significant_digits 2 -sort_by group > $root/syn/timing_min_rpt.txt
exit

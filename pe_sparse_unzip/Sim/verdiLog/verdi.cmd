verdiSetActWin -dock widgetDock_<Message>
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
verdiWindowResize -win $_Verdi_1 "830" "349" "900" "700"
srcSetSearchPath \
           "/home/bigthousand1021/Desktop/AOC/aoc_final/pe_block_v1/pe-block-32bits/pe_sparse_unzip/Sim"
srcShowFile -file \
           /home/bigthousand1021/Desktop/AOC/aoc_final/pe_block_v1/pe-block-32bits/pe_sparse_unzip/Sim/pe_block_7x3_tb.sv
wvCreateWindow
verdiSetActWin -win $_nWave2
verdiDockWidgetMaximize -dock windowDock_nWave_2
wvSetPosition -win $_nWave2 {("G1" 0)}
wvOpenFile -win $_nWave2 \
           {/home/bigthousand1021/Desktop/AOC/aoc_final/pe_block_v1/pe-block-32bits/pe_sparse_unzip/Sim/pe_block_7x3.fsdb}
verdiWindowResize -win $_Verdi_1 "1921" "31" "1278" "1360"
wvGetSignalOpen -win $_nWave2
wvGetSignalSetScope -win $_nWave2 "/pe_block_7x3_tb"
wvGetSignalSetScope -win $_nWave2 "/pe_block_7x3_tb/dut"
wvGetSignalSetScope -win $_nWave2 "/pe_block_7x3_tb/dut/g_row\[0\]"
wvGetSignalSetScope -win $_nWave2 "/pe_block_7x3_tb/dut/g_row\[0\]/u_row"
wvGetSignalSetScope -win $_nWave2 "/pe_block_7x3_tb/dut"
wvGetSignalSetScope -win $_nWave2 "/pe_block_7x3_tb"
wvGetSignalSetScope -win $_nWave2 "/pe_block_7x3_tb/dut"
wvSetPosition -win $_nWave2 {("G1" 18)}
wvSetPosition -win $_nWave2 {("G1" 18)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/pe_block_7x3_tb/dut/clk} \
{/pe_block_7x3_tb/dut/rst_n} \
{/pe_block_7x3_tb/dut/mode_1x1} \
{/pe_block_7x3_tb/dut/ifmap_data\[55:0\]} \
{/pe_block_7x3_tb/dut/g_row\[0\]/u_row/w0\[7:0\]} \
{/pe_block_7x3_tb/dut/g_row\[0\]/u_row/w1\[7:0\]} \
{/pe_block_7x3_tb/dut/g_row\[0\]/u_row/w2\[7:0\]} \
{/pe_block_7x3_tb/all_zero_ifmap} \
{/pe_block_7x3_tb/all_zero_weight} \
{/pe_block_7x3_tb/dut/o0\[31:0\]} \
{/pe_block_7x3_tb/dut/o1\[31:0\]} \
{/pe_block_7x3_tb/dut/o2\[31:0\]} \
{/pe_block_7x3_tb/dut/o3\[31:0\]} \
{/pe_block_7x3_tb/dut/o4\[31:0\]} \
{/pe_block_7x3_tb/dut/o5\[31:0\]} \
{/pe_block_7x3_tb/dut/o6\[31:0\]} \
{/pe_block_7x3_tb/dut/o7\[31:0\]} \
{/pe_block_7x3_tb/dut/o8\[31:0\]} \
}
wvAddSignal -win $_nWave2 -group {"G2" \
}
wvSelectSignal -win $_nWave2 {( "G1" 10 11 12 13 14 15 16 17 18 )} 
wvSetPosition -win $_nWave2 {("G1" 18)}
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
wvSelectSignal -win $_nWave2 {( "G1" 5 )} 
wvSelectSignal -win $_nWave2 {( "G1" 5 6 7 8 9 10 11 12 13 14 15 16 17 18 )} 
wvSelectSignal -win $_nWave2 {( "G1" 5 6 7 8 10 11 12 13 14 15 16 17 18 )} 
wvSelectSignal -win $_nWave2 {( "G1" 5 6 7 10 11 12 13 14 15 16 17 18 )} 
wvSelectSignal -win $_nWave2 {( "G1" 5 6 7 10 11 12 13 14 15 16 17 18 )} 
wvSetRadix -win $_nWave2 -format UDec
wvSetRadix -win $_nWave2 -2Com
wvSetCursor -win $_nWave2 41301.941267 -snap {("G2" 0)}
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2

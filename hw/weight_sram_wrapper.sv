module weight_sram_wrapper (
    input logic clk, input logic rst, input logic wen_i,
    input logic [19:0] waddr_i, input logic [23:0] wdata_i,
    output logic ready_o, input logic [19:0] raddr_i, output logic [23:0] rdata_o
);
    logic [63:0][31:0] sram_q;
    logic [5:0] active_bank;
    assign ready_o = 1'b1;
    assign active_bank = wen_i ? waddr_i[19:14] : raddr_i[19:14];
    assign rdata_o = sram_q[raddr_i[19:14]][23:0];
    genvar bank;
    generate
        for (bank = 0; bank < 64; bank = bank + 1) begin : GEN_BANK
            SRAM_rtl u_sram (
                .CLK(clk), .RST(rst), .CEB(active_bank != bank), .WEB(~wen_i),
                .BWEB(wen_i ? 32'h0 : 32'hffff_ffff),
                .A(wen_i ? waddr_i[13:0] : raddr_i[13:0]),
                .DI({8'd0, wdata_i}), .DO(sram_q[bank])
            );
        end
    endgenerate
endmodule

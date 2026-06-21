module weight_pingpong_wrapper #(
    parameter int LOCAL_ADDR_W = 11
)(
    input logic clk, input logic rst,
    input logic compute_sram_sel, input logic [LOCAL_ADDR_W-1:0] compute_addr,
    output logic [23:0] compute_rdata,
    input logic preload_sram_sel, input logic preload_wen,
    input logic [LOCAL_ADDR_W-1:0] preload_addr, input logic [23:0] preload_wdata,
    output logic preload_ready
);
    logic [1:0][31:0] q;
    genvar i;
    generate
      for (i=0;i<2;i=i+1) begin: GEN_WEIGHT_BUFFER
        SRAM_rtl u_sram (
          .CLK(clk), .RST(rst),
          .CEB((preload_wen && preload_sram_sel == i) || compute_sram_sel == i ? 1'b0 : 1'b1),
          .WEB((preload_wen && preload_sram_sel == i) ? 1'b0 : 1'b1),
          .BWEB((preload_wen && preload_sram_sel == i) ? 32'h0 : 32'hffff_ffff),
          .A((preload_wen && preload_sram_sel == i) ? {3'd0,preload_addr} : {3'd0,compute_addr}),
          .DI({8'd0,preload_wdata}), .DO(q[i])
        );
      end
    endgenerate
    assign compute_rdata = q[compute_sram_sel][23:0];
    assign preload_ready = 1'b1;
endmodule

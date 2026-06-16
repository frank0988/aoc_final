`timescale 1ns/1ps

module weight_sram_reg (
    input clk,
    input rst,

    input wen_i,
    input [15:0] waddr_i,
    input [23:0] wdata_i,
    output ready_o,

    input [15:0] raddr_i,
    output [23:0] rdata_o
);

reg [23:0] mem [0:255];
integer i;

assign ready_o = 1'b1;
assign rdata_o = (raddr_i < 16'd256) ? mem[raddr_i[7:0]] : 24'd0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] <= 24'd0;
        end
    end else if (wen_i && waddr_i < 16'd256) begin
        mem[waddr_i[7:0]] <= wdata_i;
    end
end

endmodule

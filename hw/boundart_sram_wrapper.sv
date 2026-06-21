module boundary_sram_wrapper #(
    parameter int DATA_W = 32, parameter int ADDR_W = 10, parameter int DEPTH = 1 << ADDR_W
)(
    input logic clk, input logic rst, input logic rd_en, input logic [ADDR_W-1:0] rd_addr,
    output logic rd_rsp_valid, output logic rd_entry_valid, output logic signed [DATA_W-1:0] rd_data,
    input logic wr_en, input logic [ADDR_W-1:0] wr_addr, input logic signed [DATA_W-1:0] wr_data,
    input logic clear_en, input logic [ADDR_W-1:0] clear_addr
);
    logic [31:0] sram_q;
    logic [DEPTH-1:0] valid_mem;
    logic read_pending;
    logic [ADDR_W-1:0] read_addr_q;
    SRAM_rtl u_sram (
        .CLK(clk), .RST(rst), .CEB(!(wr_en || rd_en)), .WEB(~wr_en),
        .BWEB(wr_en ? 32'h0 : 32'hffff_ffff), .A({{(14-ADDR_W){1'b0}}, wr_en ? wr_addr : rd_addr}),
        .DI(wr_data), .DO(sram_q)
    );
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_mem <= '0; read_pending <= 1'b0; read_addr_q <= '0;
            rd_rsp_valid <= 1'b0; rd_entry_valid <= 1'b0; rd_data <= '0;
        end else begin
            rd_rsp_valid <= read_pending;
            if (read_pending) begin
                rd_data <= sram_q;
                rd_entry_valid <= valid_mem[read_addr_q];
            end else rd_entry_valid <= 1'b0;
            read_pending <= rd_en;
            if (rd_en) read_addr_q <= rd_addr;
            if (clear_en && !(wr_en && wr_addr == clear_addr)) valid_mem[clear_addr] <= 1'b0;
            if (wr_en) valid_mem[wr_addr] <= 1'b1;
        end
    end
endmodule

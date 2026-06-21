module input_sram_wrapper (
    input logic clk, input logic rst,
    input logic mode_1x1_i,
    input logic wen_i,
    input logic [15:0] waddr_i, input logic [55:0] wdata_i,
    output logic ready_o, input logic [15:0] raddr_i,
    input logic [55:0] default_rdata_i, output logic [55:0] rdata_o,
    output logic [55:0] rdata_1x1_0_o,
    output logic [55:0] rdata_1x1_1_o,
    output logic [55:0] rdata_1x1_2_o
);
    logic [1:0] wr_count3;
    logic [13:0] wr_group_addr;
    logic [13:0] rd_group_addr;
    logic [2:0] wr_bank_en;
    logic [2:0][1:0][31:0] sram_q;
    logic [2:0][63:0] bank_rdata64;
    logic [63:0] wdata64;

    assign ready_o = 1'b1;
    assign rd_group_addr = raddr_i[13:0];
    assign wdata64 = {8'd0, wdata_i};

    always_comb begin
        wr_bank_en = 3'b000;
        if (wen_i) begin
            unique case (wr_count3)
                2'd0: wr_bank_en = 3'b001;
                2'd1: wr_bank_en = 3'b010;
                2'd2: wr_bank_en = 3'b100;
                default: wr_bank_en = 3'b000;
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_count3 <= 2'd0;
            wr_group_addr <= 14'd0;
        end else if (wen_i) begin
            if (wr_count3 == 2'd2) begin
                wr_count3 <= 2'd0;
                wr_group_addr <= wr_group_addr + 14'd1;
            end else begin
                wr_count3 <= wr_count3 + 2'd1;
            end
        end
    end

    genvar bank, word;
    generate
        for (bank = 0; bank < 3; bank = bank + 1) begin : GEN_BANK
            for (word = 0; word < 2; word = word + 1) begin : GEN_WORD
                SRAM_rtl u_sram (
                    .CLK(clk),
                    .RST(rst),
                    .CEB(wen_i ? !wr_bank_en[bank] : 1'b0),
                    .WEB(wen_i ? !wr_bank_en[bank] : 1'b1),
                    .BWEB(wen_i && wr_bank_en[bank] ? 32'h0000_0000 : 32'hffff_ffff),
                    .A(wen_i && wr_bank_en[bank] ? wr_group_addr : rd_group_addr),
                    .DI(word == 0 ? wdata64[31:0] : wdata64[63:32]),
                    .DO(sram_q[bank][word])
                );
            end
        end
    endgenerate

    always_comb begin
        for (int b = 0; b < 3; b++) begin
            bank_rdata64[b] = {sram_q[b][1], sram_q[b][0]};
        end
        rdata_1x1_0_o = bank_rdata64[0][55:0];
        rdata_1x1_1_o = bank_rdata64[1][55:0];
        rdata_1x1_2_o = bank_rdata64[2][55:0];
        rdata_o = bank_rdata64[0][55:0];
    end
endmodule

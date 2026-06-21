module SRAM_rtl (
    input logic CLK, input logic RST, input logic CEB, input logic WEB,
    input logic [31:0] BWEB, input logic [13:0] A,
    input logic [31:0] DI, output logic [31:0] DO
);
    TS1N16ADFPCLLLVTA512X45M4SWSHOD u_macro (
        .SLP(1'b0), .DSLP(1'b0), .SD(1'b0), .PUDELAY(),
        .CLK(CLK), .CEB(CEB), .WEB(WEB), .A(A), .D(DI), .BWEB(BWEB),
        .RTSEL(2'b01), .WTSEL(2'b01), .Q(DO)
    );
endmodule

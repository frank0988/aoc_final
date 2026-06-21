module PPU #(
    parameter int DATA_BITS = 32
)(
    input  logic                        clk,
    input  logic                        rst,

    // Accumulator -> PPU scalar stream
    input  logic                        in_valid,
    output logic                        in_ready,
    input  logic signed [DATA_BITS-1:0] data_in,
    input  logic                        in_last,

    // PPU configuration
    input  logic signed [DATA_BITS-1:0] bias_i,
    input  logic [5:0]                  scaling_factor,
    input  logic                        maxpool_en,
    input  logic                        maxpool_init,
    input  logic                        maxpool_emit,
    input  logic                        relu_en,

    // PPU -> packer scalar stream
    output logic                        out_valid,
    input  logic                        out_ready,
    output logic [7:0]                  data_out,
    output logic                        out_last
);

    logic [7:0] post_quant_out;

    logic       pool_valid;
    logic       pool_ready;
    logic [7:0] pool_data;
    logic       pool_last;

    // PostQuant and ReLU are combinational. Backpressure is handled by the
    // stateful Maxpool_Qint8 stream stage between them.
    PostQuant u_post_quant (
        .data_in        (data_in),
        .bias_i         (bias_i),
        .scaling_factor (scaling_factor),
        .data_out       (post_quant_out)
    );

    Maxpool_Qint8 u_maxpool (
        .clk       (clk),
        .rst       (rst),

        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .data_in   (post_quant_out),
        .in_last   (in_last),

        .en        (maxpool_en),
        .init      (maxpool_init),
        .emit      (maxpool_emit),

        .out_valid (pool_valid),
        .out_ready (pool_ready),
        .data_out  (pool_data),
        .out_last  (pool_last)
    );

    // ReLU is combinational, so the maxpool output register itself holds
    // both the input and the ReLU result stable during backpressure.
    ReLU_Qint8 u_relu (
        .en       (relu_en),
        .data_in  (pool_data),
        .data_out (data_out)
    );

    assign out_valid  = pool_valid;
    assign pool_ready = out_ready;
    assign out_last   = pool_last;

endmodule

module Maxpool_Qint8 (
    input  logic       clk,
    input  logic       rst,

    // Scalar input stream
    input  logic       in_valid,
    output logic       in_ready,
    input  logic [7:0] data_in,
    input  logic       in_last,

    // Pool control, sampled only when in_valid && in_ready
    input  logic       en,
    input  logic       init,   // first scalar of the current pooling window
    input  logic       emit,   // last scalar of the current pooling window

    // Scalar output stream
    output logic       out_valid,
    input  logic       out_ready,
    output logic [7:0] data_out,
    output logic       out_last
);

    logic [7:0] max_reg;
    logic [7:0] out_data_reg;
    logic       out_valid_reg;
    logic       out_last_reg;

    logic [7:0] pool_value;
    logic       in_fire;
    logic       out_fire;

    assign in_fire  = in_valid && in_ready;
    assign out_fire = out_valid && out_ready;

    // One-entry output register. If its current value is accepted in this
    // cycle, a new input may also be accepted in the same cycle.
    assign in_ready = !out_valid_reg || out_ready;

    assign out_valid = out_valid_reg;
    assign data_out  = out_data_reg;
    assign out_last  = out_last_reg;

    always_comb begin
        if (init) begin
            pool_value = data_in;
        end else begin
            pool_value = (data_in > max_reg) ? data_in : max_reg;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            max_reg      <= 8'd0;
            out_data_reg <= 8'd0;
            out_valid_reg <= 1'b0;
            out_last_reg  <= 1'b0;
        end else begin
            // Remove an output only when the downstream module accepts it.
            if (out_fire) begin
                out_valid_reg <= 1'b0;
                out_last_reg  <= 1'b0;
            end

            // Internal state changes only after a real ready/valid transfer.
            if (in_fire) begin
                if (!en) begin
                    // Maxpool bypass: one input scalar becomes one output scalar.
                    out_data_reg  <= data_in;
                    out_valid_reg <= 1'b1;
                    out_last_reg  <= in_last;
                end else begin
                    // Maxpool enabled: accumulate the current pooling window.
                    max_reg <= pool_value;

                    // Emit exactly one scalar at the end of the window.
                    if (emit) begin
                        out_data_reg  <= pool_value;
                        out_valid_reg <= 1'b1;
                        out_last_reg  <= in_last;
                    end
                end
            end
        end
    end

endmodule

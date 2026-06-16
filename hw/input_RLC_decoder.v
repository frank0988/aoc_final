`timescale 1ns/1ps

module input_RLC_decoder (
    input clk,  // Clock for all decoder registers.
    input rst,  // Active-high reset. Clears pending state and controller outputs.

    // Input RLC token stream.
    // token = {RUN[6:0], vector[55:0], term}
    input [63:0] token_data_i,  // Encoded token from the upstream token source.
    input token_valid_i,  // Upstream asserts when token_data_i is valid.
    output token_ready_o,  // Decoder asserts when it can accept one token.

    // Controller event stream.
    // ctrl_dense_index_o is the original dense vector position.
    output ctrl_valid_o,  // Decoder asserts when ctrl_* outputs hold one event.
    input ctrl_ready_i,  // Controller asserts when it accepts the current event.
    output reg [15:0] ctrl_run_o,  // Number of zero vectors before this event.
    output reg [15:0] ctrl_dense_index_o,  // Dense vector index for this event.
    output reg ctrl_vec_nonzero_o,  // 1 when this event carries a non-zero vector.
    output reg ctrl_last_o,  // 1 when this is the final decoded event.
    output reg ctrl_done_o,  // One-cycle pulse when the final event is accepted.

    // Input SRAM write port. The SRAM itself is modeled in the testbench.
    output input_sram_wen_o,  // Write enable for decoded non-zero input vectors.
    output [15:0] input_sram_waddr_o,  // Write address, same as dense vector index.
    output [55:0] input_sram_wdata_o,  // Decoded 7-lane vector to write.
    input input_sram_ready_i  // SRAM/register file can accept the write this cycle.
);

// decode state
reg [15:0] pending_run;
reg [15:0] stream_index;
reg [55:0] event_vec;
reg event_valid;

// handshake and token decode helpers
wire event_ready;
wire event_fire;
wire token_fire;
wire token_is_continuation;
wire token_creates_event;
wire [15:0] token_run_ext;
wire [15:0] next_event_run;
wire [15:0] next_event_index;
wire [55:0] token_vec;
wire token_term;

assign ctrl_valid_o = event_valid && (!ctrl_vec_nonzero_o || input_sram_ready_i);

assign event_ready = ctrl_ready_i;
assign event_fire = ctrl_valid_o && event_ready;

// The decoder accepts a new RLC token only when no event is waiting.
assign token_ready_o = !event_valid;

assign token_fire = token_valid_i && token_ready_o;
assign token_vec = token_data_i[56:1];
assign token_term = token_data_i[0];
assign token_run_ext = {9'd0, token_data_i[63:57]};
assign token_is_continuation = (token_vec == 56'd0) && token_term;
assign token_creates_event = token_fire && !token_is_continuation;
assign next_event_run = pending_run + token_run_ext;
assign next_event_index = stream_index + pending_run + token_run_ext;

// SRAM writes only happen for non-zero vectors.
assign input_sram_wen_o = event_fire && ctrl_vec_nonzero_o;
assign input_sram_waddr_o = ctrl_dense_index_o;
assign input_sram_wdata_o = event_vec;

// Accumulate zero-run continuation tokens.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        pending_run <= 16'd0;
    end else if (token_fire && token_is_continuation) begin
        pending_run <= pending_run + token_run_ext;
    end else if (token_creates_event) begin
        pending_run <= 16'd0;
    end
end

// Track the dense vector position after each controller event is consumed.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        stream_index <= 16'd0;
    end else if (event_fire) begin
        if (ctrl_last_o) begin
            stream_index <= 16'd0;
        end else if (ctrl_vec_nonzero_o) begin
            stream_index <= ctrl_dense_index_o + 16'd1;
        end else begin
            stream_index <= ctrl_dense_index_o;
        end
    end
end

// Hold the payload vector that will be written to SRAM for non-zero events.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        event_vec <= 56'd0;
    end else if (token_creates_event) begin
        event_vec <= token_vec;
    end
end

// Controller event outputs.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        event_valid <= 1'b0;
        ctrl_run_o <= 16'd0;
        ctrl_dense_index_o <= 16'd0;
        ctrl_vec_nonzero_o <= 1'b0;
        ctrl_last_o <= 1'b0;
    end else if (event_fire) begin
        event_valid <= 1'b0;
    end else if (token_creates_event) begin
        // A real event is either a non-zero vector or the terminal tail-zero event.
        event_valid <= 1'b1;
        ctrl_run_o <= next_event_run;
        ctrl_dense_index_o <= next_event_index;
        ctrl_vec_nonzero_o <= (token_vec != 56'd0);
        ctrl_last_o <= !token_term;
    end
end

always @(*) begin
    ctrl_done_o = event_fire && ctrl_last_o;
end

endmodule

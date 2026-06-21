`timescale 1ns/1ps

module input_RLC_decoder (
    input clk,
    input rst,

    input [63:0] token_data_i,
    input token_valid_i,
    output token_ready_o,

    output ctrl_valid_o,
    input ctrl_ready_i,
    output reg [15:0] ctrl_run_o,
    output reg [15:0] ctrl_dense_index_o,
    output reg ctrl_vec_nonzero_o,
    output reg ctrl_last_o,
    output ctrl_done_o,

    // Every dense vector, including vectors represented by an RLC run, is
    // materialized in input SRAM.  This lets the SRAM data path use no reset
    // or validity memory while preserving sparse-RLC semantics.
    output input_sram_wen_o,
    output [15:0] input_sram_waddr_o,
    output [55:0] input_sram_wdata_o,
    input input_sram_ready_i,
    input [55:0] zero_vec_i
);

reg [15:0] pending_run;
reg [15:0] stream_index;
reg [55:0] event_vec;
reg event_valid;
reg write_busy;
reg [15:0] fill_addr;
reg [15:0] zeros_remaining;
reg payload_pending;

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
wire token_is_tail_zero_event;
wire next_event_nonzero;
wire input_sram_fire;

// Do not expose an input-control event until all zero-run entries and its
// payload have been committed to SRAM.  A consumer that reacts to ctrl_done
// can therefore start compute immediately after the final event.
assign ctrl_valid_o = event_valid && !write_busy;
assign event_ready = ctrl_ready_i;
assign event_fire = ctrl_valid_o && event_ready;
assign token_ready_o = !event_valid && !write_busy;
assign token_fire = token_valid_i && token_ready_o;
assign token_vec = token_data_i[56:1];
assign token_term = token_data_i[0];
assign token_run_ext = {9'd0, token_data_i[63:57]};
assign token_is_continuation = (token_vec == 56'd0) && !token_term;
assign token_creates_event = token_fire && !token_is_continuation;
assign next_event_run = pending_run + token_run_ext;
assign next_event_index = stream_index + pending_run + token_run_ext;
assign token_is_tail_zero_event = (token_vec == 56'd0) && token_term &&
                                  (next_event_run != 16'd0);
assign next_event_nonzero = (token_vec != zero_vec_i) && !token_is_tail_zero_event;

assign input_sram_wen_o = write_busy && input_sram_ready_i;
assign input_sram_fire = input_sram_wen_o;
assign input_sram_waddr_o = (zeros_remaining != 16'd0) ? fill_addr : ctrl_dense_index_o;
assign input_sram_wdata_o = (zeros_remaining != 16'd0) ? zero_vec_i : event_vec;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pending_run <= 16'd0;
    end else if (token_fire && token_is_continuation) begin
        pending_run <= pending_run + token_run_ext;
    end else if (token_creates_event) begin
        pending_run <= 16'd0;
    end
end

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

always @(posedge clk or posedge rst) begin
    if (rst) begin
        event_vec <= 56'd0;
    end else if (token_creates_event) begin
        event_vec <= token_vec;
    end
end

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
        event_valid <= 1'b1;
        ctrl_run_o <= next_event_run;
        ctrl_dense_index_o <= next_event_index;
        ctrl_vec_nonzero_o <= next_event_nonzero;
        ctrl_last_o <= token_term;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        write_busy <= 1'b0;
        fill_addr <= 16'd0;
        zeros_remaining <= 16'd0;
        payload_pending <= 1'b0;
    end else if (token_creates_event) begin
        fill_addr <= stream_index;
        zeros_remaining <= next_event_run;
        payload_pending <= next_event_nonzero;
        write_busy <= (next_event_run != 16'd0) || next_event_nonzero;
    end else if (input_sram_fire) begin
        if (zeros_remaining != 16'd0) begin
            zeros_remaining <= zeros_remaining - 16'd1;
            fill_addr <= fill_addr + 16'd1;
            if ((zeros_remaining == 16'd1) && !payload_pending) begin
                write_busy <= 1'b0;
            end
        end else begin
            payload_pending <= 1'b0;
            write_busy <= 1'b0;
        end
    end
end

assign ctrl_done_o = event_fire && ctrl_last_o;

endmodule

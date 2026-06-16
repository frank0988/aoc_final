`timescale 1ns/1ps

module output_RLC_encoder (
    input clk,  // Clock for all encoder registers.
    input rst,  // Active-high reset. Clears pending token and RUN state.

    // PPU output vector stream.
    // One vector has seven 8-bit lanes: {v0, v1, v2, v3, v4, v5, v6}.
    input [55:0] ppu_data_i,  // Dense output vector from PPU or output datapath.
    input ppu_valid_i,  // Upstream asserts when ppu_data_i is valid.
    input ppu_last_i,  // Marks the final vector in the output stream.
    output ppu_ready_o,  // Encoder asserts when it can accept one PPU vector.

    // Output RLC token stream.
    // token = {RUN[6:0], vector[55:0], term}
    output reg [63:0] token_data_o,  // Encoded RLC token to downstream module.
    output reg token_valid_o,  // Encoder asserts when token_data_o is valid.
    input token_ready_i,  // Downstream asserts when it accepts the current token.

    // Controller helper signals.
    output ctrl_busy_o,  // 1 while encoder has pending RUN/token work.
    output ctrl_token_fire_o,  // One-cycle pulse when one output token transfers.
    output ctrl_done_o  // One-cycle pulse when the terminal token transfers.
);

reg [6:0] run_count;
reg [6:0] tail_run;
reg tail_pending;

wire vec_is_zero;
wire token_fire;
wire token_slot_ready;
wire ppu_fire;
wire ppu_emits_token;
wire emit_tail_token;
wire emit_ppu_token;
wire split_last_zero_run;

assign vec_is_zero = (ppu_data_i == 56'd0);
assign token_fire = token_valid_o && token_ready_i;
assign token_slot_ready = !token_valid_o || token_ready_i;

// The encoder can accept a PPU vector only when no token is waiting.
assign ppu_ready_o = !token_valid_o && !tail_pending;
assign ppu_fire = ppu_valid_i && ppu_ready_o;
assign ppu_emits_token = !vec_is_zero || ppu_last_i || run_count == 7'd127;
assign emit_tail_token = token_slot_ready && tail_pending;
assign emit_ppu_token = token_slot_ready && !tail_pending && ppu_fire && ppu_emits_token;
assign split_last_zero_run = ppu_fire && vec_is_zero && ppu_last_i && run_count == 7'd127;

// Controller status.
assign ctrl_busy_o = token_valid_o || tail_pending || (run_count != 7'd0);
assign ctrl_token_fire_o = token_fire;
assign ctrl_done_o = token_fire && !token_data_o[0];

// output token valid control
always @(posedge clk or posedge rst) begin
    if (rst) begin
        token_valid_o <= 1'b0;
    end else if (emit_tail_token || emit_ppu_token) begin
        token_valid_o <= 1'b1;
    end else if (token_fire) begin
        token_valid_o <= 1'b0;
    end
end

// output token data generation
always @(posedge clk or posedge rst) begin
    if (rst) begin
        token_data_o <= 64'd0;
    end else if (emit_tail_token) begin
        // Emit the terminal tail-zero token after a full RUN continuation.
        token_data_o <= {tail_run, 56'd0, 1'b0};
    end else if (emit_ppu_token) begin
        if (vec_is_zero) begin
            if (ppu_last_i) begin
                if (run_count == 7'd127) begin
                    // The last vector still overflows RUN, so split it into two tokens.
                    token_data_o <= {7'd127, 56'd0, 1'b1};
                end else begin
                    // Stream ends with zero vectors.
                    token_data_o <= {run_count + 7'd1, 56'd0, 1'b0};
                end
            end else begin
                // A long zero run uses a continuation token.
                token_data_o <= {7'd127, 56'd0, 1'b1};
            end
        end else begin
            // Non-zero vector: emit the accumulated RUN and this vector.
            token_data_o <= {run_count, ppu_data_i, !ppu_last_i};
        end
    end
end

// RUN count update
always @(posedge clk or posedge rst) begin
    if (rst) begin
        run_count <= 7'd0;
    end else if (emit_tail_token) begin
        run_count <= 7'd0;
    end else if (token_slot_ready && !tail_pending && ppu_fire) begin
        if (vec_is_zero) begin
            if (ppu_last_i) begin
                run_count <= 7'd0;
            end else if (run_count == 7'd127) begin
                run_count <= 7'd1;
            end else begin
                run_count <= run_count + 7'd1;
            end
        end else begin
            run_count <= 7'd0;
        end
    end
end

// Tail-zero token state for a final zero run that exceeds one token.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        tail_pending <= 1'b0;
        tail_run <= 7'd0;
    end else if (emit_tail_token) begin
        tail_pending <= 1'b0;
        tail_run <= 7'd0;
    end else if (token_slot_ready && !tail_pending && split_last_zero_run) begin
        tail_pending <= 1'b1;
        tail_run <= 7'd1;
    end
end

endmodule

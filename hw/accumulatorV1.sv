module accumulator #(
    parameter int NUM_LANES = 9,
    parameter int DATA_W    = 32,
    parameter int IDX_W     = 10,
    parameter int ACC_DEPTH = 1 << IDX_W
)(
    input  logic clk,
    input  logic rst, // active-high asynchronous reset

    // Input from PE block / controller
    input  logic                                      in_valid,
    output logic                                      in_ready,
    input  logic signed [NUM_LANES-1:0][DATA_W-1:0]   pe_data,
    input  logic        [NUM_LANES-1:0]               pe_valid, // 9 bits valid mask
    input  logic        [NUM_LANES-1:0][IDX_W-1:0]    pe_idx,
    input  logic        [NUM_LANES-1:0]               pe_last, // one-hot/bit mask; asserted only on the final scalar that will reach PPU

    // Per-lane column accumulation control for sparse 3x3 mode.
    // first_col[i] = 1: pe_data[i] is the first valid filter-column
    //                   contribution for pe_idx[i] in this accumulation round.
    // last_col[i]  = 1: pe_data[i] is the last valid filter-column
    //                   contribution for pe_idx[i] in this accumulation round.
    input  logic        [NUM_LANES-1:0]               first_col,
    input  logic        [NUM_LANES-1:0]               last_col,

    input  logic        [1:0]                         mode,          // 00: 3x3 conv, 01: 1x1 conv, 10: FC
    input  logic                                      first_channel,
    input  logic                                      last_channel,

    // Per-lane boundary information from controller.
    // is_boundary[i] / boundary_final[i] belong to pe_data[i].
    input  logic        [NUM_LANES-1:0]               is_boundary,
    input  logic                                      boundary_valid,
    input  logic signed [DATA_W-1:0]                  boundary_rdata,
    input  logic        [NUM_LANES-1:0]               boundary_final,

    // boundary_rdata/boundary_valid are scalar because Stage2 processes
    // one selected lane per cycle. The controller must present the read data
    // matching idx_stage2 when a final boundary lane reaches Stage2.

    // Boundary result back to controller / Boundary SRAM
    output logic                                      boundary_out_valid,
    output logic signed [DATA_W-1:0]                  boundary_wdata,
    output logic        [IDX_W-1:0]                   boundary_idx,

    // Output to PPU
    output logic                                      ppu_valid,
    input  logic                                      ppu_ready,
    output logic signed [DATA_W-1:0]                  ppu_data,
    output logic        [IDX_W-1:0]                   ppu_idx,
    output logic                                      ppu_last
);

    // ============================================================
    // Type definitions
    // ============================================================
    typedef logic signed [DATA_W-1:0] data_type;
    typedef logic        [IDX_W-1:0]  idx_type;

    // ============================================================
    // Mode definition
    // ============================================================
    localparam logic [1:0] MODE_3X3 = 2'b00;
    localparam logic [1:0] MODE_1X1 = 2'b01;
    localparam logic [1:0] MODE_FC  = 2'b10;

    // ============================================================
    // Stage 0: input packet latch
    // ============================================================
    data_type data_stage0      [0:NUM_LANES-1];
    logic     valid_stage0     [0:NUM_LANES-1];
    idx_type  idx_stage0       [0:NUM_LANES-1];
    logic     last_stage0      [0:NUM_LANES-1];
    logic     first_col_stage0 [0:NUM_LANES-1];
    logic     last_col_stage0  [0:NUM_LANES-1];

    logic [1:0] mode_stage0;
    logic       first_channel_stage0;
    logic       last_channel_stage0;
    logic       is_boundary_stage0    [0:NUM_LANES-1];
    logic       boundary_final_stage0 [0:NUM_LANES-1];

    // ============================================================
    // Stage 1: selected scalar lane from Stage 0
    // ============================================================
    data_type data_stage1;
    logic     valid_stage1;
    idx_type  idx_stage1;
    logic     last_stage1;
    logic     first_col_stage1;
    logic     last_col_stage1;

    logic [1:0] mode_stage1;
    logic       first_channel_stage1;
    logic       last_channel_stage1;
    logic       is_boundary_stage1;
    logic       boundary_final_stage1;

    // For 3x3 mode: accumulate valid filter-column contributions.
    data_type col_acc_buffer [0:ACC_DEPTH-1];

    // ============================================================
    // Stage 2: channel accumulation input
    // ============================================================
    data_type data_stage2;
    logic     valid_stage2;
    idx_type  idx_stage2;
    logic     last_stage2;

    logic [1:0] mode_stage2;
    logic       first_channel_stage2;
    logic       last_channel_stage2;
    logic       is_boundary_stage2;
    logic       boundary_final_stage2;

    // Accumulate across input channels.
    data_type ch_acc_buffer [0:ACC_DEPTH-1];

    // ============================================================
    // PPU output holding registers
    // ============================================================
    data_type data_ppu_hold;
    logic     valid_ppu_hold;
    idx_type  idx_ppu_hold;
    logic     last_ppu_hold;

    // ============================================================
    // FSM and lane control
    // ============================================================
    typedef enum logic [1:0] {
        S_IDLE,
        S_PROC
    } state_t;

    state_t state;

    localparam int LANE_PTR_W = $clog2(NUM_LANES+1);    // 4
    localparam logic [LANE_PTR_W-1:0] NUM_LANES_LP = LANE_PTR_W'(NUM_LANES);
    localparam logic [LANE_PTR_W-1:0] LAST_LANE_LP = LANE_PTR_W'(NUM_LANES-1);

    logic [LANE_PTR_W-1:0] lane_ptr;

    logic pipeline_stall;
    logic output_can_accept;

    assign output_can_accept = (!valid_ppu_hold) || ppu_ready;
    assign pipeline_stall    = valid_ppu_hold && !ppu_ready;

    integer i;

    // ============================================================
    // FSM 
    // ============================================================
    assign in_ready = (state == S_IDLE) && !pipeline_stall;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            lane_ptr <= '0;
        end else if (!pipeline_stall) begin
            case (state)
                S_IDLE: begin
                    lane_ptr <= '0;
                    if (in_valid && in_ready) begin
                        state <= S_PROC;
                    end
                end

                S_PROC: begin
                    if (lane_ptr == LAST_LANE_LP) begin
                        state    <= S_IDLE;
                        lane_ptr <= '0;
                    end else begin
                        lane_ptr <= lane_ptr + 1'b1;
                    end
                end

                default: begin
                    state    <= S_IDLE;
                    lane_ptr <= '0;
                end
            endcase
        end
    end

    // =============================================================
    // Stage0: input packet latch 把 PE 、 ctrl 送來訊號全存到 stage0
    // =============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mode_stage0          <= MODE_3X3;
            first_channel_stage0 <= 1'b0;
            last_channel_stage0  <= 1'b0;

            for (i = 0; i < NUM_LANES; i = i + 1) begin
                data_stage0[i]           <= '0;
                valid_stage0[i]          <= 1'b0;
                idx_stage0[i]            <= '0;
                last_stage0[i]           <= 1'b0;
                first_col_stage0[i]      <= 1'b0;
                last_col_stage0[i]       <= 1'b0;
                is_boundary_stage0[i]    <= 1'b0;
                boundary_final_stage0[i] <= 1'b0;
            end
        end else if (!pipeline_stall) begin
            if (state == S_IDLE && in_valid && in_ready) begin
                for (i = 0; i < NUM_LANES; i = i + 1) begin
                    data_stage0[i]           <= pe_data[i];
                    valid_stage0[i]          <= pe_valid[i];
                    idx_stage0[i]            <= pe_idx[i];
                    last_stage0[i]           <= pe_last[i];
                    first_col_stage0[i]      <= first_col[i];
                    last_col_stage0[i]       <= last_col[i];
                    is_boundary_stage0[i]    <= is_boundary[i];
                    boundary_final_stage0[i] <= boundary_final[i];
                end

                mode_stage0          <= mode;
                first_channel_stage0 <= first_channel;
                last_channel_stage0  <= last_channel;
            end
        end
    end

    // =================================================================
    // Stage0 -> Stage1: lane selection 把 stage0 訊號分 lane 存到 stage1
    // =================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_stage1     <= 1'b0;
            data_stage1      <= '0;
            idx_stage1       <= '0;
            last_stage1      <= 1'b0;
            first_col_stage1 <= 1'b0;
            last_col_stage1  <= 1'b0;

            mode_stage1           <= MODE_3X3;
            first_channel_stage1  <= 1'b0;
            last_channel_stage1   <= 1'b0;
            is_boundary_stage1    <= 1'b0;
            boundary_final_stage1 <= 1'b0;
        end else if (!pipeline_stall) begin
            valid_stage1 <= 1'b0;

            if (state == S_PROC && lane_ptr < NUM_LANES_LP) begin
                data_stage1      <= data_stage0[lane_ptr];
                valid_stage1     <= valid_stage0[lane_ptr];
                idx_stage1       <= idx_stage0[lane_ptr];
                last_stage1      <= last_stage0[lane_ptr];
                first_col_stage1 <= first_col_stage0[lane_ptr];
                last_col_stage1  <= last_col_stage0[lane_ptr];

                mode_stage1           <= mode_stage0;
                first_channel_stage1  <= first_channel_stage0;
                last_channel_stage1   <= last_channel_stage0;
                is_boundary_stage1    <= is_boundary_stage0[lane_ptr];
                boundary_final_stage1 <= boundary_final_stage0[lane_ptr];
            end
        end
    end

    // ============================================================
    // Stage1: mode-dependent accumulation
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_stage2 <= 1'b0;
            data_stage2  <= '0;
            idx_stage2   <= '0;
            last_stage2  <= 1'b0;

            mode_stage2           <= MODE_3X3;
            first_channel_stage2  <= 1'b0;
            last_channel_stage2   <= 1'b0;
            is_boundary_stage2    <= 1'b0;
            boundary_final_stage2 <= 1'b0;
        end else if (!pipeline_stall) begin
            valid_stage2 <= 1'b0;

            if (valid_stage1) begin
                if (mode_stage1 == MODE_1X1 || mode_stage1 == MODE_FC) begin
                    // 1x1 / FC mode:
                    // No spatial filter-column accumulation is required.
                    data_stage2  <= data_stage1;
                    valid_stage2 <= 1'b1;
                    idx_stage2   <= idx_stage1;
                    last_stage2  <= last_stage1;

                    mode_stage2           <= mode_stage1;
                    first_channel_stage2  <= first_channel_stage1;
                    last_channel_stage2   <= last_channel_stage1;
                    is_boundary_stage2    <= is_boundary_stage1;
                    boundary_final_stage2 <= boundary_final_stage1;
                end else begin
                    // 3x3 sparse-aware column accumulation.
                    // first_col / last_col are per lane and refer to the
                    // first/last VALID column contribution of this idx.
                    if (first_col_stage1 && last_col_stage1) begin
                        // Only one valid filter-column contribution exists.
                        // No buffer read is required.
                        data_stage2  <= data_stage1;
                        valid_stage2 <= 1'b1;
                        idx_stage2   <= idx_stage1;
                        last_stage2  <= last_stage1;

                        mode_stage2           <= mode_stage1;
                        first_channel_stage2  <= first_channel_stage1;
                        last_channel_stage2   <= last_channel_stage1;
                        is_boundary_stage2    <= is_boundary_stage1;
                        boundary_final_stage2 <= boundary_final_stage1;
                    end else if (first_col_stage1) begin
                        // First valid contribution starts a new accumulation.
                        col_acc_buffer[idx_stage1] <= data_stage1;
                    end else if (last_col_stage1) begin
                        // Last valid contribution completes this channel sum.
                        data_stage2  <= col_acc_buffer[idx_stage1] + data_stage1;
                        valid_stage2 <= 1'b1;
                        idx_stage2   <= idx_stage1;
                        last_stage2  <= last_stage1;

                        mode_stage2           <= mode_stage1;
                        first_channel_stage2  <= first_channel_stage1;
                        last_channel_stage2   <= last_channel_stage1;
                        is_boundary_stage2    <= is_boundary_stage1;
                        boundary_final_stage2 <= boundary_final_stage1;
                    end else begin
                        // Middle valid contribution.
                        col_acc_buffer[idx_stage1]
                            <= col_acc_buffer[idx_stage1] + data_stage1;
                    end
                end
            end
        end
    end

    // ============================================================
    // Stage2: channel accumulation + boundary / PPU output
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_ppu_hold <= 1'b0;
            data_ppu_hold  <= '0;
            idx_ppu_hold   <= '0;
            last_ppu_hold  <= 1'b0;

            boundary_out_valid <= 1'b0;
            boundary_wdata     <= '0;
            boundary_idx       <= '0;
        end else begin
            boundary_out_valid <= 1'b0;

            if (valid_ppu_hold && ppu_ready) begin
                valid_ppu_hold <= 1'b0;
            end

            if (!pipeline_stall && valid_stage2) begin
                if (first_channel_stage2 && last_channel_stage2) begin
                    if (is_boundary_stage2) begin
                        if (boundary_final_stage2) begin
                            if (boundary_valid && output_can_accept) begin
                                data_ppu_hold  <= boundary_rdata + data_stage2;
                                idx_ppu_hold   <= idx_stage2;
                                last_ppu_hold  <= last_stage2;
                                valid_ppu_hold <= 1'b1;
                            end
                        end else begin
                            boundary_wdata     <= data_stage2;
                            boundary_idx       <= idx_stage2;
                            boundary_out_valid <= 1'b1;
                        end
                    end else if (output_can_accept) begin
                        data_ppu_hold  <= data_stage2;
                        idx_ppu_hold   <= idx_stage2;
                        last_ppu_hold  <= last_stage2;
                        valid_ppu_hold <= 1'b1;
                    end
                end else if (first_channel_stage2) begin
                    ch_acc_buffer[idx_stage2] <= data_stage2;
                end else if (last_channel_stage2) begin
                    if (is_boundary_stage2) begin
                        if (boundary_final_stage2) begin
                            if (boundary_valid && output_can_accept) begin
                                data_ppu_hold  <= boundary_rdata
                                                + ch_acc_buffer[idx_stage2]
                                                + data_stage2;
                                idx_ppu_hold   <= idx_stage2;
                                last_ppu_hold  <= last_stage2;
                                valid_ppu_hold <= 1'b1;
                            end
                        end else begin
                            boundary_wdata     <= ch_acc_buffer[idx_stage2] + data_stage2;
                            boundary_idx       <= idx_stage2;
                            boundary_out_valid <= 1'b1;
                        end
                    end else if (output_can_accept) begin
                        data_ppu_hold  <= ch_acc_buffer[idx_stage2] + data_stage2;
                        idx_ppu_hold   <= idx_stage2;
                        last_ppu_hold  <= last_stage2;
                        valid_ppu_hold <= 1'b1;
                    end
                end else begin
                    ch_acc_buffer[idx_stage2]
                        <= ch_acc_buffer[idx_stage2] + data_stage2;
                end
            end
        end
    end

    assign ppu_valid = valid_ppu_hold;
    assign ppu_data  = data_ppu_hold;
    assign ppu_idx   = idx_ppu_hold;
    assign ppu_last  = last_ppu_hold;

endmodule

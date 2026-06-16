module accumulator #(
    parameter int NUM_LANES         = 9,
    parameter int DATA_W            = 32,
    parameter int IDX_W             = 10,
    parameter int ACC_DEPTH         = 1 << IDX_W,

    // Boundary-address configuration
    parameter int M_W               = 9,
    parameter int F_W               = 5,
    parameter int BOUNDARY_ROWS     = 2,
    parameter int BOUNDARY_ROW_W    = (BOUNDARY_ROWS <= 1)
                                      ? 1 : $clog2(BOUNDARY_ROWS),
    // Must be large enough for:
    // max_addr = M * BOUNDARY_ROWS * F - 1
    parameter int BOUNDARY_ADDR_W   = IDX_W,
    parameter int BOUNDARY_DEPTH    = 1 << BOUNDARY_ADDR_W
)(
    input  logic clk,
    input  logic rst, // active-high asynchronous reset

    // Input from PE block / controller
    input  logic                                      in_valid,
    output logic                                      in_ready,
    input  logic signed [NUM_LANES-1:0][DATA_W-1:0]   pe_data,
    input  logic        [NUM_LANES-1:0]               pe_valid,
    input  logic        [NUM_LANES-1:0][IDX_W-1:0]    pe_idx,
    input  logic        [NUM_LANES-1:0]               pe_last,

    // Per-lane sparse 3x3 column control
    input  logic        [NUM_LANES-1:0]               first_col,
    input  logic        [NUM_LANES-1:0]               last_col,

    input  logic        [1:0]                         mode, // 00: 3x3, 01: 1x1, 10: FC
    input  logic                                      first_channel,
    input  logic                                      last_channel,

    // Boundary metadata supplied by the controller.
    // The accumulator calculates:
    // addr = (m * BOUNDARY_ROWS + boundary_row) * F + f_idx
    input  logic        [NUM_LANES-1:0]                         boundary_en,
    input  logic        [M_W-1:0]                               output_channel_m,
    input  logic        [F_W-1:0]                               ofmap_width_F,
    input  logic        [NUM_LANES-1:0][BOUNDARY_ROW_W-1:0]    boundary_row,
    input  logic        [NUM_LANES-1:0][F_W-1:0]                f_idx,

    // Output to PPU
    output logic                                      ppu_valid,
    input  logic                                      ppu_ready,
    output logic signed [DATA_W-1:0]                  ppu_data,
    output logic        [IDX_W-1:0]                   ppu_idx,
    output logic                                      ppu_last
);

    typedef logic signed [DATA_W-1:0] data_type;
    typedef logic        [IDX_W-1:0]  idx_type;
    typedef logic        [BOUNDARY_ADDR_W-1:0] boundary_addr_type;

    // Convert the controller-provided logical coordinates into one linear
    // Boundary RegFile address.
    function automatic boundary_addr_type calc_boundary_addr (
        input logic [M_W-1:0]            m,
        input logic [BOUNDARY_ROW_W-1:0] row,
        input logic [F_W-1:0]            F,
        input logic [F_W-1:0]            f
    );
        longint unsigned m_ext;
        longint unsigned row_ext;
        longint unsigned F_ext;
        longint unsigned f_ext;
        longint unsigned linear_addr;
        begin
            m_ext   = 64'($unsigned(m));
            row_ext = 64'($unsigned(row));
            F_ext   = 64'($unsigned(F));
            f_ext   = 64'($unsigned(f));

            linear_addr =
                ((m_ext * BOUNDARY_ROWS) + row_ext) * F_ext + f_ext;

            calc_boundary_addr = boundary_addr_type'(linear_addr);
        end
    endfunction

    localparam logic [1:0] MODE_3X3 = 2'b00;
    localparam logic [1:0] MODE_1X1 = 2'b01;
    localparam logic [1:0] MODE_FC  = 2'b10;

    // ============================================================
    // Stage 0: latch one complete PE packet
    // ============================================================
    data_type data_stage0          [0:NUM_LANES-1];
    logic     valid_stage0         [0:NUM_LANES-1];
    idx_type  idx_stage0           [0:NUM_LANES-1];
    logic     last_stage0          [0:NUM_LANES-1];
    logic     first_col_stage0     [0:NUM_LANES-1];
    logic     last_col_stage0      [0:NUM_LANES-1];
    logic     boundary_en_stage0   [0:NUM_LANES-1];
    boundary_addr_type boundary_addr_stage0 [0:NUM_LANES-1];

    // Combinational address generated from controller metadata. It is latched
    // into Stage 0 together with the corresponding PE lane.
    boundary_addr_type boundary_addr_calc [0:NUM_LANES-1];

    genvar boundary_lane;
    generate
        for (boundary_lane = 0;
             boundary_lane < NUM_LANES;
             boundary_lane = boundary_lane + 1) begin : GEN_BOUNDARY_ADDR
            assign boundary_addr_calc[boundary_lane] =
                calc_boundary_addr(
                    output_channel_m,
                    boundary_row[boundary_lane],
                    ofmap_width_F,
                    f_idx[boundary_lane]
                );
        end
    endgenerate

    logic [1:0] mode_stage0;
    logic       first_channel_stage0;
    logic       last_channel_stage0;

    // ============================================================
    // Stage 1: one selected scalar lane
    // ============================================================
    data_type data_stage1;
    logic     valid_stage1;
    idx_type  idx_stage1;
    logic     last_stage1;
    logic     first_col_stage1;
    logic     last_col_stage1;
    logic     boundary_en_stage1;
    boundary_addr_type boundary_addr_stage1;

    logic [1:0] mode_stage1;
    logic       first_channel_stage1;
    logic       last_channel_stage1;

    data_type col_acc_buffer [0:ACC_DEPTH-1];

    // ============================================================
    // Stage 2: completed per-channel contribution
    // ============================================================
    data_type data_stage2;
    logic     valid_stage2;
    idx_type  idx_stage2;
    logic     last_stage2;
    logic     boundary_en_stage2;
    boundary_addr_type boundary_addr_stage2;

    logic [1:0] mode_stage2;
    logic       first_channel_stage2;
    logic       last_channel_stage2;

    data_type ch_acc_buffer [0:ACC_DEPTH-1];

    // ============================================================
    // PPU output hold registers
    // ============================================================
    data_type data_ppu_hold;
    logic     valid_ppu_hold;
    idx_type  idx_ppu_hold;
    logic     last_ppu_hold;

    // ============================================================
    // Packet FSM and lane control
    // ============================================================
    typedef enum logic [1:0] {
        S_IDLE,
        S_PROC
    } state_t;

    state_t state;

    localparam int LANE_PTR_W = $clog2(NUM_LANES + 1);
    localparam logic [LANE_PTR_W-1:0] NUM_LANES_LP = LANE_PTR_W'(NUM_LANES);
    localparam logic [LANE_PTR_W-1:0] LAST_LANE_LP = LANE_PTR_W'(NUM_LANES - 1);

    logic [LANE_PTR_W-1:0] lane_ptr;

    // ============================================================
    // Boundary read state and pending registers
    // ============================================================
    typedef enum logic [1:0] {
        B_IDLE,
        B_WAIT_READ,
        B_WAIT_PPU
    } boundary_state_t;

    boundary_state_t boundary_state;

    // "pending" means the current boundary transaction has been accepted,
    // but the synchronous RegFile read has not been fully resolved yet.
    data_type          boundary_psum_pending;
    data_type          boundary_merged_pending;
    idx_type           boundary_idx_pending;
    boundary_addr_type boundary_addr_pending;
    logic              boundary_last_pending;

    // ============================================================
    // Global flow control
    // ============================================================
    logic ppu_stall;
    logic boundary_busy;
    logic pipeline_stall;
    logic output_can_accept;

    assign output_can_accept = (!valid_ppu_hold) || ppu_ready;
    assign ppu_stall         = valid_ppu_hold && !ppu_ready;
    assign boundary_busy     = (boundary_state != B_IDLE);
    assign pipeline_stall    = ppu_stall || boundary_busy;
    assign in_ready          = (state == S_IDLE) && !pipeline_stall;

    integer i;

    // ============================================================
    // Internal synchronous Boundary RegFile interface
    // ============================================================
    logic                         boundary_rf_rd_en;
    boundary_addr_type            boundary_rf_rd_addr;
    logic                         boundary_rf_rd_rsp_valid;
    logic                         boundary_rf_rd_entry_valid;
    data_type                     boundary_rf_rd_data;

    logic                         boundary_rf_wr_en;
    boundary_addr_type            boundary_rf_wr_addr;
    data_type                     boundary_rf_wr_data;

    logic                         boundary_rf_clear_en;
    boundary_addr_type            boundary_rf_clear_addr;

    // ============================================================
    // Final per-tile psum generation
    // ============================================================
    logic     channel_sum_ready;
    data_type tile_local_psum;
    logic     boundary_request;

    always_comb begin
        channel_sum_ready = 1'b0;
        tile_local_psum   = '0;

        if (valid_stage2) begin
            if (first_channel_stage2 && last_channel_stage2) begin
                channel_sum_ready = 1'b1;
                tile_local_psum   = data_stage2;
            end else if (last_channel_stage2) begin
                channel_sum_ready = 1'b1;
                tile_local_psum   = ch_acc_buffer[idx_stage2] + data_stage2;
            end
        end
    end

    assign boundary_request = (boundary_state == B_IDLE)
                            && output_can_accept
                            && channel_sum_ready
                            && boundary_en_stage2;

    // ============================================================
    // Boundary RegFile controls
    // ============================================================
    // Read request is issued when a completed tile-local boundary psum arrives.
    assign boundary_rf_rd_en   = boundary_request;
    assign boundary_rf_rd_addr = boundary_addr_stage2;

    // If the synchronous response says the entry was empty, store the pending
    // tile-local psum as the first tile contribution.
    assign boundary_rf_wr_en   = (boundary_state == B_WAIT_READ)
                               && boundary_rf_rd_rsp_valid
                               && !boundary_rf_rd_entry_valid;
    assign boundary_rf_wr_addr = boundary_addr_pending;
    assign boundary_rf_wr_data = boundary_psum_pending;

    // Clear after the old psum has been safely captured into the PPU hold
    // register. B_WAIT_PPU covers the rare case where the hold register was full.
    assign boundary_rf_clear_en =
          ((boundary_state == B_WAIT_READ)
            && boundary_rf_rd_rsp_valid
            && boundary_rf_rd_entry_valid
            && output_can_accept)
        || ((boundary_state == B_WAIT_PPU)
            && output_can_accept);

    assign boundary_rf_clear_addr = boundary_addr_pending;

    boundary_regfile #(
        .DATA_W (DATA_W),
        .ADDR_W (BOUNDARY_ADDR_W),
        .DEPTH  (BOUNDARY_DEPTH)
    ) u_boundary_regfile (
        .clk            (clk),
        .rst            (rst),
        .rd_en          (boundary_rf_rd_en),
        .rd_addr        (boundary_rf_rd_addr),
        .rd_rsp_valid   (boundary_rf_rd_rsp_valid),
        .rd_entry_valid (boundary_rf_rd_entry_valid),
        .rd_data        (boundary_rf_rd_data),
        .wr_en          (boundary_rf_wr_en),
        .wr_addr        (boundary_rf_wr_addr),
        .wr_data        (boundary_rf_wr_data),
        .clear_en       (boundary_rf_clear_en),
        .clear_addr     (boundary_rf_clear_addr)
    );

    // ============================================================
    // Packet FSM: receive one packet, then serialize its lanes
    // ============================================================
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

    // ============================================================
    // Stage 0: latch PE data, sideband information, and calculated boundary address
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mode_stage0          <= MODE_3X3;
            first_channel_stage0 <= 1'b0;
            last_channel_stage0  <= 1'b0;

            for (i = 0; i < NUM_LANES; i = i + 1) begin
                data_stage0[i]          <= '0;
                valid_stage0[i]         <= 1'b0;
                idx_stage0[i]           <= '0;
                last_stage0[i]          <= 1'b0;
                first_col_stage0[i]     <= 1'b0;
                last_col_stage0[i]      <= 1'b0;
                boundary_en_stage0[i]   <= 1'b0;
                boundary_addr_stage0[i] <= '0;
            end
        end else if (!pipeline_stall) begin
            if (state == S_IDLE && in_valid && in_ready) begin
                for (i = 0; i < NUM_LANES; i = i + 1) begin
                    data_stage0[i]          <= pe_data[i];
                    valid_stage0[i]         <= pe_valid[i];
                    idx_stage0[i]           <= pe_idx[i];
                    last_stage0[i]          <= pe_last[i];
                    first_col_stage0[i]     <= first_col[i];
                    last_col_stage0[i]      <= last_col[i];
                    boundary_en_stage0[i]   <= boundary_en[i];
                    boundary_addr_stage0[i] <= boundary_addr_calc[i];
                end

                mode_stage0          <= mode;
                first_channel_stage0 <= first_channel;
                last_channel_stage0  <= last_channel;
            end
        end
    end

    // ============================================================
    // Stage 0 -> Stage 1: select one lane per cycle
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_stage1          <= '0;
            valid_stage1         <= 1'b0;
            idx_stage1           <= '0;
            last_stage1          <= 1'b0;
            first_col_stage1     <= 1'b0;
            last_col_stage1      <= 1'b0;
            boundary_en_stage1   <= 1'b0;
            boundary_addr_stage1 <= '0;

            mode_stage1          <= MODE_3X3;
            first_channel_stage1 <= 1'b0;
            last_channel_stage1  <= 1'b0;
        end else if (!pipeline_stall) begin
            valid_stage1 <= 1'b0;

            if (state == S_PROC && lane_ptr < NUM_LANES_LP) begin
                data_stage1          <= data_stage0[lane_ptr];
                valid_stage1         <= valid_stage0[lane_ptr];
                idx_stage1           <= idx_stage0[lane_ptr];
                last_stage1          <= last_stage0[lane_ptr];
                first_col_stage1     <= first_col_stage0[lane_ptr];
                last_col_stage1      <= last_col_stage0[lane_ptr];
                boundary_en_stage1   <= boundary_en_stage0[lane_ptr];
                boundary_addr_stage1 <= boundary_addr_stage0[lane_ptr];

                mode_stage1          <= mode_stage0;
                first_channel_stage1 <= first_channel_stage0;
                last_channel_stage1  <= last_channel_stage0;
            end
        end
    end

    // ============================================================
    // Stage 1: mode-dependent spatial-column accumulation
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_stage2          <= '0;
            valid_stage2         <= 1'b0;
            idx_stage2           <= '0;
            last_stage2          <= 1'b0;
            boundary_en_stage2   <= 1'b0;
            boundary_addr_stage2 <= '0;

            mode_stage2          <= MODE_3X3;
            first_channel_stage2 <= 1'b0;
            last_channel_stage2  <= 1'b0;
        end else if (!pipeline_stall) begin
            valid_stage2 <= 1'b0;

            if (valid_stage1) begin
                if (mode_stage1 == MODE_1X1 || mode_stage1 == MODE_FC) begin
                    // 1x1 and FC bypass three-column spatial accumulation.
                    data_stage2          <= data_stage1;
                    valid_stage2         <= 1'b1;
                    idx_stage2           <= idx_stage1;
                    last_stage2          <= last_stage1;
                    boundary_en_stage2   <= boundary_en_stage1;
                    boundary_addr_stage2 <= boundary_addr_stage1;

                    mode_stage2          <= mode_stage1;
                    first_channel_stage2 <= first_channel_stage1;
                    last_channel_stage2  <= last_channel_stage1;
                end else begin
                    // Sparse-aware 3x3 accumulation using first/last valid column.
                    if (first_col_stage1 && last_col_stage1) begin
                        data_stage2          <= data_stage1;
                        valid_stage2         <= 1'b1;
                        idx_stage2           <= idx_stage1;
                        last_stage2          <= last_stage1;
                        boundary_en_stage2   <= boundary_en_stage1;
                        boundary_addr_stage2 <= boundary_addr_stage1;

                        mode_stage2          <= mode_stage1;
                        first_channel_stage2 <= first_channel_stage1;
                        last_channel_stage2  <= last_channel_stage1;
                    end else if (first_col_stage1) begin
                        col_acc_buffer[idx_stage1] <= data_stage1;
                    end else if (last_col_stage1) begin
                        data_stage2          <= col_acc_buffer[idx_stage1] + data_stage1;
                        valid_stage2         <= 1'b1;
                        idx_stage2           <= idx_stage1;
                        last_stage2          <= last_stage1;
                        boundary_en_stage2   <= boundary_en_stage1;
                        boundary_addr_stage2 <= boundary_addr_stage1;

                        mode_stage2          <= mode_stage1;
                        first_channel_stage2 <= first_channel_stage1;
                        last_channel_stage2  <= last_channel_stage1;
                    end else begin
                        col_acc_buffer[idx_stage1]
                            <= col_acc_buffer[idx_stage1] + data_stage1;
                    end
                end
            end
        end
    end

    // ============================================================
    // Stage 2 + synchronous boundary transaction controller
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_ppu_hold          <= '0;
            valid_ppu_hold         <= 1'b0;
            idx_ppu_hold           <= '0;
            last_ppu_hold          <= 1'b0;

            boundary_state         <= B_IDLE;
            boundary_psum_pending  <= '0;
            boundary_merged_pending<= '0;
            boundary_idx_pending   <= '0;
            boundary_addr_pending  <= '0;
            boundary_last_pending  <= 1'b0;
        end else begin
            // Remove an output only after a valid/ready handshake.
            // A new output may replace it in the same cycle.
            if (valid_ppu_hold && ppu_ready) begin
                valid_ppu_hold <= 1'b0;
            end

            case (boundary_state)
                B_IDLE: begin
                    if (output_can_accept && valid_stage2) begin
                        if (channel_sum_ready) begin
                            if (boundary_en_stage2) begin
                                // Launch synchronous read and preserve all data
                                // needed when the response returns.
                                boundary_psum_pending <= tile_local_psum;
                                boundary_idx_pending  <= idx_stage2;
                                boundary_addr_pending <= boundary_addr_stage2;
                                boundary_last_pending <= last_stage2;
                                boundary_state        <= B_WAIT_READ;
                            end else begin
                                // Normal final output; no boundary merge needed.
                                data_ppu_hold  <= tile_local_psum;
                                idx_ppu_hold   <= idx_stage2;
                                last_ppu_hold  <= last_stage2;
                                valid_ppu_hold <= 1'b1;
                            end
                        end else if (first_channel_stage2) begin
                            // First channel contribution initializes the entry.
                            ch_acc_buffer[idx_stage2] <= data_stage2;
                        end else begin
                            // Middle channel contribution continues accumulation.
                            ch_acc_buffer[idx_stage2]
                                <= ch_acc_buffer[idx_stage2] + data_stage2;
                        end
                    end
                end

                B_WAIT_READ: begin
                    if (boundary_rf_rd_rsp_valid) begin
                        if (!boundary_rf_rd_entry_valid) begin
                            // First tile contribution is written by the RegFile
                            // through boundary_rf_wr_en in this cycle.
                            boundary_state <= B_IDLE;
                        end else if (output_can_accept) begin
                            // Second tile contribution: merge, place result in
                            // the PPU hold register, and clear the RegFile entry.
                            data_ppu_hold  <= boundary_rf_rd_data
                                            + boundary_psum_pending;
                            idx_ppu_hold   <= boundary_idx_pending;
                            last_ppu_hold  <= boundary_last_pending;
                            valid_ppu_hold <= 1'b1;
                            boundary_state <= B_IDLE;
                        end else begin
                            // Defensive path: preserve the merged result until
                            // the PPU hold register can accept it.
                            boundary_merged_pending <= boundary_rf_rd_data
                                                     + boundary_psum_pending;
                            boundary_state <= B_WAIT_PPU;
                        end
                    end
                end

                B_WAIT_PPU: begin
                    if (output_can_accept) begin
                        data_ppu_hold  <= boundary_merged_pending;
                        idx_ppu_hold   <= boundary_idx_pending;
                        last_ppu_hold  <= boundary_last_pending;
                        valid_ppu_hold <= 1'b1;
                        boundary_state <= B_IDLE;
                    end
                end

                default: begin
                    boundary_state <= B_IDLE;
                end
            endcase
        end
    end

    assign ppu_valid = valid_ppu_hold;
    assign ppu_data  = data_ppu_hold;
    assign ppu_idx   = idx_ppu_hold;
    assign ppu_last  = last_ppu_hold;

endmodule

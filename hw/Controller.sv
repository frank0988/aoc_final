`timescale 1ns/1ps



module Controller(
    input  logic clk,
    input  logic rst,
    input  logic pe_en,
    input  logic [29:0] i_config,

    input  logic [55:0] ifmap_0,
    input  logic [55:0] ifmap_1,
    input  logic [55:0] ifmap_2,
    input  logic [23:0] filter,
    input  logic [31:0] ipsum,

    input  logic [2:0] ifmap_in_valid,
    input  logic filter_in_valid,
    input  logic ipsum_ready, //no use
    input  logic load_ready,
    input  logic opsum_valid, //no use
    input  logic preload_done,

    output logic [2:0] ifmap_valid,
    output logic filter_valid,
    output logic ipsum_valid,//no use
    output logic opsum_ready,//no use
    output logic ctrl_ready, //no use
    output logic [31:0] opsum,

    output logic [2:0] ifmap_ready,
    output logic filter_ready,
    output logic boundary_en,
    output logic pe_block_en,
    output logic [4:0] ofmap_col_index,
    output logic [4:0] ofmap_row_index,
    output logic [8:0] ifmap_ch_index,
    output logic [2:0] filter_col_index,

    output logic [7:0] ifmap_pe_0,
    output logic [7:0] ifmap_pe_1,
    output logic [7:0] ifmap_pe_2,
    output logic [7:0] ifmap_pe_3,
    output logic [7:0] ifmap_pe_4,
    output logic [7:0] ifmap_pe_5,
    output logic [7:0] ifmap_pe_6,
    output logic [55:0] ifmap_pe_group_0,
    output logic [55:0] ifmap_pe_group_1,
    output logic [55:0] ifmap_pe_group_2,
    output logic [7:0] filter_pe_0,
    output logic [7:0] filter_pe_1,
    output logic [7:0] filter_pe_2,

    output logic first_col,
    output logic last_col,
    output logic first_channel,
    output logic last_channel,
    output logic boundary_final,
    output logic pe_last,
    output logic layer_done,
    output logic [8:0] ofmap_ch_index,
    output logic [5:0] ifmap_col_index,
    output logic [1:0] filter_load_index,
    output logic compute_sram_sel,
    output logic preload_sram_sel,
    output logic preload_start,
    output logic compute_done,
    output logic swap_enable,
    output logic [8:0] current_m,
    output logic [8:0] next_m
);

localparam logic [3:0] IDLE        = 4'd0;
localparam logic [3:0] LOAD_CONFIG = 4'd1;
localparam logic [3:0] LOAD_SRAM   = 4'd2;
localparam logic [3:0] LOAD_FILTER = 4'd3;
localparam logic [3:0] COMPUTE_S1  = 4'd4;
localparam logic [3:0] COMPUTE_S2  = 4'd5;
localparam logic [3:0] COMPUTE_S3  = 4'd6;
localparam logic [3:0] COMPUTE_S4  = 4'd7;
localparam logic [3:0] COMPUTE_S5  = 4'd8;
localparam logic [3:0] COMPUTE_1X1 = 4'd9;
localparam logic [3:0] WAIT_PRELOAD = 4'd10;
localparam logic [3:0] SWAP_SRAM   = 4'd11;
localparam logic [3:0] DONE        = 4'd15;

logic [3:0] curr, next;
logic compute_sram_sel_r;
logic preload_sram_sel_r;
logic channel_compute_done;
logic last_channel_compute;

logic [1:0] mode;
logic [8:0] cfg_c;
logic [8:0] cfg_m;
logic [4:0] cfg_e_last;
logic [4:0] cfg_f_last;

logic [8:0] m_cnt;
logic [8:0] c_cnt;
logic [4:0] e_cnt;
logic [5:0] w_cnt;
logic [1:0] filter_col_cnt;
logic [1:0] count3;
logic [1:0] load_filter_cnt;
logic [1:0] state_ifmap_cnt;
logic load_filter_done;
logic [2:0] ifmap_stream_sel;
logic [2:0] ifmap_col_bank_sel;

logic [2:0] ifmap_valid_r;
logic filter_valid_r;
logic [4:0] ofmap_col_index_r;
logic [2:0] filter_col_index_r;
logic [8:0] ifmap_ch_index_r;
logic [4:0] ofmap_row_index_r;
logic [8:0] ofmap_ch_index_r;
logic [5:0] ifmap_col_index_r;
logic first_col_r;
logic last_col_r;
logic first_channel_r;
logic last_channel_r;
logic boundary_final_r;
logic boundary_en_r;
logic pe_last_r;
logic layer_done_r;
logic [4:0] next_ofmap_col_index;
logic [2:0] count7;
logic [2:0] next_count7;
// Three independently fetched 7-lane operands for the 1x1 channel group.
// 3x3 continues to use bank 0 only.
logic [7:0] ifmap_pe_r [0:2][0:6];
logic [7:0] filter_pe_r [0:2];
logic [7:0] filter_bank [0:2][0:2];

logic compute_state;
logic selected_ifmap_valid;
logic ifmap_req_state;
logic ifmap_hs;
logic load_filter_hs;
logic op_hs;
logic [5:0] w_last;
logic at_last_op;
logic [1:0] active_filter_col;
logic [1:0] one_by_one_phase;
logic [1:0] state_ifmap_need;
logic state_ifmap_done;
logic s5_done;
logic [4:0] s3_repeat_cnt;
logic s3_last_repeat;
logic at_last_1x1;

// These sidebands travel with the registered PE operands.  The top samples
// them when ifmap_valid/filter_valid produce the PE fire one cycle later.
assign first_col = first_col_r;
assign last_col = last_col_r;
assign first_channel = first_channel_r;
assign last_channel = last_channel_r;
assign boundary_final = boundary_final_r;
assign boundary_en = boundary_en_r;
assign pe_last = pe_last_r;


assign compute_state = (curr == COMPUTE_S1) ||
                       (curr == COMPUTE_S2) ||
                       (curr == COMPUTE_S3) ||
                       (curr == COMPUTE_S4) ||
                       (curr == COMPUTE_S5) ||
                       (curr == COMPUTE_1X1);

always_comb begin
    unique case (count3)
        2'd0: ifmap_stream_sel = 3'b001;
        2'd1: ifmap_stream_sel = 3'b010;
        2'd2: ifmap_stream_sel = 3'b100;
        default: ifmap_stream_sel = 3'b000;
    endcase
end

always_comb begin
    unique case (w_cnt)
        6'd0,  6'd3,  6'd6,  6'd9,  6'd12, 6'd15,
        6'd18, 6'd21, 6'd24, 6'd27, 6'd30, 6'd33: ifmap_col_bank_sel = 3'b001;
        6'd1,  6'd4,  6'd7,  6'd10, 6'd13, 6'd16,
        6'd19, 6'd22, 6'd25, 6'd28, 6'd31, 6'd34: ifmap_col_bank_sel = 3'b010;
        default: ifmap_col_bank_sel = 3'b100;
    endcase
end

assign selected_ifmap_valid = mode[0] ? (&ifmap_in_valid) :
                                           (|(ifmap_in_valid & ifmap_col_bank_sel));
assign ifmap_req_state = (curr == COMPUTE_S1) ||
                         (curr == COMPUTE_S2) ||
                         (curr == COMPUTE_S3) ||
                         (curr == COMPUTE_S4) ||
                         (curr == COMPUTE_S5) ||
                         (curr == COMPUTE_1X1);
assign ifmap_hs = ifmap_req_state & selected_ifmap_valid;
assign load_filter_hs = (curr == LOAD_FILTER) & !load_filter_done & filter_in_valid;
assign op_hs = ifmap_hs;
assign w_last = {1'b0, cfg_f_last} + 6'd2;
assign at_last_op = (m_cnt == (cfg_m - 9'd1)) &
                    (e_cnt == cfg_e_last) &
                    (c_cnt == (cfg_c - 9'd1)) &
                    (w_cnt == w_last) &
                    (filter_col_cnt == 2'd2);
assign at_last_1x1 = (m_cnt == (cfg_m - 9'd1)) &
                     (e_cnt == cfg_e_last) &
                     (c_cnt == (cfg_c - 9'd1)) &
                     (w_cnt == {1'b0, cfg_f_last});
always_comb begin
    unique case (curr)
        COMPUTE_S1: state_ifmap_need = 2'd1;
        COMPUTE_S2: state_ifmap_need = 2'd2;
        COMPUTE_S3: state_ifmap_need = 2'd3;
        COMPUTE_S4: state_ifmap_need = 2'd2;
        COMPUTE_S5: state_ifmap_need = 2'd1;
        COMPUTE_1X1: state_ifmap_need = 2'd1;
        default:    state_ifmap_need = 2'd0;
    endcase
end

assign state_ifmap_done = op_hs & ((state_ifmap_cnt + 2'd1) == state_ifmap_need);
assign s5_done = state_ifmap_done & (curr == COMPUTE_S5);
assign s3_last_repeat = (cfg_f_last <= 5'd1) || (s3_repeat_cnt >= (cfg_f_last - 5'd2));
assign active_filter_col = mode[0] ? one_by_one_phase : filter_col_cnt;

always_comb begin
    if (mode[0]) begin
        next_ofmap_col_index = w_cnt[4:0];
    end else begin
        next_ofmap_col_index = w_cnt[4:0] - {3'd0, filter_col_cnt};
    end
end

always_comb begin
    unique case (next_ofmap_col_index)
        5'd0,  5'd7,  5'd14, 5'd21, 5'd28: next_count7 = 3'd0;
        5'd1,  5'd8,  5'd15, 5'd22, 5'd29: next_count7 = 3'd1;
        5'd2,  5'd9,  5'd16, 5'd23, 5'd30: next_count7 = 3'd2;
        5'd3,  5'd10, 5'd17, 5'd24, 5'd31: next_count7 = 3'd3;
        5'd4,  5'd11, 5'd18, 5'd25:       next_count7 = 3'd4;
        5'd5,  5'd12, 5'd19, 5'd26:       next_count7 = 3'd5;
        default:                            next_count7 = 3'd6;
    endcase
end

assign ctrl_ready = (curr == LOAD_SRAM);
assign ifmap_ready = ifmap_req_state ? (mode[0] ? 3'b111 : ifmap_col_bank_sel) : 3'b000;
assign filter_ready = (curr == LOAD_FILTER) & !load_filter_done;
assign ifmap_valid = ifmap_valid_r;
assign filter_valid = filter_valid_r;
assign ipsum_valid = 1'b0;
assign opsum_ready = 1'b0;
assign opsum = '0;
assign pe_block_en = compute_state;
assign ofmap_col_index = ofmap_col_index_r;
assign filter_col_index = filter_col_index_r;
// These indices also drive the controller-side SRAM addresses, so they remain
// live FSM counters.  PE sidebands that need cycle alignment are registered above.
assign ifmap_ch_index = c_cnt;
assign ofmap_row_index = e_cnt;
assign ofmap_ch_index = m_cnt;
assign ifmap_col_index = w_cnt;
assign filter_load_index = load_filter_cnt;
assign layer_done = layer_done_r;
assign compute_sram_sel = compute_sram_sel_r;
assign preload_sram_sel = preload_sram_sel_r;
assign current_m = m_cnt;
assign next_m = m_cnt + 9'd1;
assign last_channel_compute = (m_cnt == (cfg_m - 9'd1));
assign channel_compute_done = (curr == COMPUTE_S5 && state_ifmap_done &&
                               c_cnt == (cfg_c - 9'd1) && e_cnt == cfg_e_last) ||
                              (curr == COMPUTE_1X1 && state_ifmap_done &&
                               w_cnt == {1'b0, cfg_f_last} && c_cnt == (cfg_c - 9'd1) &&
                               e_cnt == cfg_e_last);
assign compute_done = channel_compute_done;
assign preload_start = compute_state && !last_channel_compute;
assign swap_enable = channel_compute_done && preload_done && !last_channel_compute;

// Legacy signals expose operand group 0 for existing 3x3 TB/debug code.
assign ifmap_pe_0 = ifmap_pe_r[0][0];
assign ifmap_pe_1 = ifmap_pe_r[0][1];
assign ifmap_pe_2 = ifmap_pe_r[0][2];
assign ifmap_pe_3 = ifmap_pe_r[0][3];
assign ifmap_pe_4 = ifmap_pe_r[0][4];
assign ifmap_pe_5 = ifmap_pe_r[0][5];
assign ifmap_pe_6 = ifmap_pe_r[0][6];
assign ifmap_pe_group_0 = {ifmap_pe_r[0][6], ifmap_pe_r[0][5], ifmap_pe_r[0][4],
                           ifmap_pe_r[0][3], ifmap_pe_r[0][2], ifmap_pe_r[0][1], ifmap_pe_r[0][0]};
assign ifmap_pe_group_1 = {ifmap_pe_r[1][6], ifmap_pe_r[1][5], ifmap_pe_r[1][4],
                           ifmap_pe_r[1][3], ifmap_pe_r[1][2], ifmap_pe_r[1][1], ifmap_pe_r[1][0]};
assign ifmap_pe_group_2 = {ifmap_pe_r[2][6], ifmap_pe_r[2][5], ifmap_pe_r[2][4],
                           ifmap_pe_r[2][3], ifmap_pe_r[2][2], ifmap_pe_r[2][1], ifmap_pe_r[2][0]};
assign filter_pe_0 = filter_pe_r[0];
assign filter_pe_1 = filter_pe_r[1];
assign filter_pe_2 = filter_pe_r[2];

always_comb begin
    next = curr;
    unique case (curr)
        IDLE:        next = pe_en ? LOAD_CONFIG : IDLE;
        LOAD_CONFIG: next = LOAD_SRAM;
        LOAD_SRAM:   next = load_ready ? LOAD_FILTER : LOAD_SRAM;
        LOAD_FILTER: next = load_filter_done ? (mode[0] ? COMPUTE_1X1 : COMPUTE_S1) : LOAD_FILTER;
        COMPUTE_S1:  next = state_ifmap_done ? COMPUTE_S2 : COMPUTE_S1;
        COMPUTE_S2:  next = state_ifmap_done ? COMPUTE_S3 : COMPUTE_S2;
        COMPUTE_S3: begin
            if (state_ifmap_done) begin
                next = s3_last_repeat ? COMPUTE_S4 : COMPUTE_S3;
            end
        end
        COMPUTE_S4:  next = state_ifmap_done ? COMPUTE_S5 : COMPUTE_S4;
        COMPUTE_S5: begin
            if (state_ifmap_done) begin
                if (at_last_op) next = DONE;
                else if (c_cnt == (cfg_c - 9'd1) && e_cnt == cfg_e_last)
                    next = preload_done ? SWAP_SRAM : WAIT_PRELOAD;
                else next = LOAD_FILTER;
            end
        end
        COMPUTE_1X1: begin
            if (state_ifmap_done) begin
                if (at_last_1x1) next = DONE;
                else if (w_cnt == {1'b0, cfg_f_last}) begin
                    if (c_cnt == (cfg_c - 9'd1) && e_cnt == cfg_e_last)
                        next = preload_done ? SWAP_SRAM : WAIT_PRELOAD;
                    else next = LOAD_FILTER;
                end else next = COMPUTE_1X1;
            end
        end
        WAIT_PRELOAD: next = preload_done ? SWAP_SRAM : WAIT_PRELOAD;
        SWAP_SRAM: next = LOAD_FILTER;
        DONE:        next = pe_en ? DONE : IDLE;
        default:     next = IDLE;
    endcase
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) curr <= IDLE;
    else curr <= next;
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        mode <= 2'd0;
        cfg_c <= 9'd0;
        cfg_m <= 9'd0;
        cfg_e_last <= 5'd0;
        cfg_f_last <= 5'd0;
    end else if (curr == IDLE && pe_en) begin
        {mode, cfg_c, cfg_m, cfg_e_last, cfg_f_last} <= i_config;
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        load_filter_cnt <= 2'd0;
        load_filter_done <= 1'b0;
        for (int s = 0; s < 3; s++) begin
            for (int r = 0; r < 3; r++) begin
                filter_bank[s][r] <= 8'd0;
            end
        end
    end else if (curr != LOAD_FILTER) begin
        load_filter_cnt <= 2'd0;
        load_filter_done <= 1'b0;
    end else if (load_filter_hs) begin
        filter_bank[load_filter_cnt][0] <= filter[7:0];
        filter_bank[load_filter_cnt][1] <= filter[15:8];
        filter_bank[load_filter_cnt][2] <= filter[23:16];
        if ((mode[0] && load_filter_cnt == 2'd0) || (!mode[0] && load_filter_cnt == 2'd2)) begin
            load_filter_done <= 1'b1;
        end else begin
            load_filter_cnt <= load_filter_cnt + 2'd1;
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state_ifmap_cnt <= 2'd0;
    end else if (curr == LOAD_CONFIG || curr == LOAD_FILTER) begin
        state_ifmap_cnt <= 2'd0;
    end else if (op_hs) begin
        state_ifmap_cnt <= state_ifmap_done ? 2'd0 : (state_ifmap_cnt + 2'd1);
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        s3_repeat_cnt <= 5'd0;
    end else if (curr == LOAD_CONFIG || curr == LOAD_FILTER || curr == COMPUTE_S5 || curr == COMPUTE_1X1) begin
        s3_repeat_cnt <= 5'd0;
    end else if (op_hs && curr == COMPUTE_S3 && state_ifmap_cnt == 2'd2) begin
        s3_repeat_cnt <= s3_last_repeat ? 5'd0 : (s3_repeat_cnt + 5'd1);
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        w_cnt <= 6'd0;
        filter_col_cnt <= 2'd0;
    end else if (curr == LOAD_CONFIG || curr == LOAD_FILTER) begin
        w_cnt <= 6'd0;
        filter_col_cnt <= 2'd0;
    end else if (op_hs) begin
        unique case (curr)
            COMPUTE_S1: begin
                w_cnt <= 6'd1;
                filter_col_cnt <= 2'd0;
            end
            COMPUTE_S2: begin
                if (state_ifmap_cnt == 2'd0) begin
                    filter_col_cnt <= 2'd1;
                end else begin
                    w_cnt <= 6'd2;
                    filter_col_cnt <= 2'd0;
                end
            end
            COMPUTE_S3: begin
                if (state_ifmap_cnt == 2'd0) begin
                    filter_col_cnt <= 2'd1;
                end else if (state_ifmap_cnt == 2'd1) begin
                    filter_col_cnt <= 2'd2;
                end else if (s3_last_repeat) begin
                    w_cnt <= {1'b0, cfg_f_last} + 6'd1;
                    filter_col_cnt <= 2'd1;
                end else begin
                    w_cnt <= w_cnt + 6'd1;
                    filter_col_cnt <= 2'd0;
                end
            end
            COMPUTE_S4: begin
                if (state_ifmap_cnt == 2'd0) begin
                    filter_col_cnt <= 2'd2;
                end else begin
                    w_cnt <= {1'b0, cfg_f_last} + 6'd2;
                    filter_col_cnt <= 2'd2;
                end
            end
            COMPUTE_S5: begin
                w_cnt <= 6'd0;
                filter_col_cnt <= 2'd0;
            end
            COMPUTE_1X1: begin
                if (w_cnt < {1'b0, cfg_f_last}) w_cnt <= w_cnt + 6'd1;
                else w_cnt <= 6'd0;
            end
            default: ;
        endcase
    end
end

// In 1x1 mode filter_col_index is an accumulator stage-1 phase, not a
// spatial filter column.  It advances only with an accepted PE operand.
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        one_by_one_phase <= 2'd0;
    end else if (curr == IDLE || curr == DONE || curr == LOAD_CONFIG || curr == LOAD_SRAM) begin
        one_by_one_phase <= 2'd0;
    end else if (op_hs && curr == COMPUTE_1X1) begin
        one_by_one_phase <= (one_by_one_phase == 2'd2) ? 2'd0 : (one_by_one_phase + 2'd1);
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        compute_sram_sel_r <= 1'b0;
        preload_sram_sel_r <= 1'b1;
    end else if (curr == LOAD_CONFIG) begin
        compute_sram_sel_r <= 1'b0;
        preload_sram_sel_r <= 1'b1;
    end else if (curr == SWAP_SRAM) begin
        compute_sram_sel_r <= preload_sram_sel_r;
        preload_sram_sel_r <= compute_sram_sel_r;
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        m_cnt <= 9'd0;
        e_cnt <= 5'd0;
        c_cnt <= 9'd0;
    end else if (curr == LOAD_CONFIG) begin
        m_cnt <= 9'd0;
        e_cnt <= 5'd0;
        c_cnt <= 9'd0;
    end else if (op_hs && curr == COMPUTE_S5 && !at_last_op) begin
        if (c_cnt < (cfg_c - 9'd1)) begin
            c_cnt <= c_cnt + 9'd1;
        end else begin
            c_cnt <= 9'd0;
            if (e_cnt < cfg_e_last) begin
                e_cnt <= e_cnt + 5'd1;
            end else begin
                e_cnt <= 5'd0;
                m_cnt <= m_cnt + 9'd1;
            end
        end
    end else if (op_hs && curr == COMPUTE_1X1 && w_cnt == {1'b0, cfg_f_last} && !at_last_1x1) begin
        if (c_cnt < (cfg_c - 9'd1)) begin
            c_cnt <= c_cnt + 9'd1;
        end else begin
            c_cnt <= 9'd0;
            if (e_cnt < cfg_e_last) begin
                e_cnt <= e_cnt + 5'd1;
            end else begin
                e_cnt <= 5'd0;
                m_cnt <= m_cnt + 9'd1;
            end
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        count3 <= 2'd0;
    end else if (curr == IDLE || curr == DONE || curr == LOAD_CONFIG || curr == LOAD_SRAM || curr == LOAD_FILTER) begin
        count3 <= 2'd0;
    end else if (ifmap_hs) begin
        if (count3 == 2'd2) begin
            count3 <= 2'd0;
        end else begin
            count3 <= count3 + 2'd1;
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        ifmap_valid_r <= 3'b000;
        filter_valid_r <= 1'b0;
        ofmap_col_index_r <= 5'd0;
        filter_col_index_r <= 3'd0;
        ifmap_ch_index_r <= 9'd0;
        ofmap_row_index_r <= 5'd0;
        ofmap_ch_index_r <= 9'd0;
        ifmap_col_index_r <= 6'd0;
        first_col_r <= 1'b0;
        last_col_r <= 1'b0;
        first_channel_r <= 1'b0;
        last_channel_r <= 1'b0;
        boundary_final_r <= 1'b0;
        boundary_en_r <= 1'b0;
        pe_last_r <= 1'b0;
        layer_done_r <= 1'b0;
        count7 <= 3'd0;
    end else begin
        ifmap_valid_r <= 3'b000;
        filter_valid_r <= 1'b0;
        if (op_hs) begin
            ifmap_valid_r <= mode[0] ? 3'b111 : ifmap_col_bank_sel;
            filter_valid_r <= 1'b1;
            ofmap_col_index_r <= next_ofmap_col_index;
            count7 <= next_count7;
            ifmap_ch_index_r <= c_cnt;
            ofmap_row_index_r <= e_cnt;
            ofmap_ch_index_r <= m_cnt;
            ifmap_col_index_r <= w_cnt;
            first_col_r <= !mode[0] && (filter_col_cnt == 2'd0);
            last_col_r <= !mode[0] && (filter_col_cnt == 2'd2);
            first_channel_r <= (c_cnt == 9'd0);
            last_channel_r <= (c_cnt == (cfg_c - 9'd1));
            boundary_final_r <= (e_cnt == cfg_e_last);
            boundary_en_r <= (e_cnt != cfg_e_last);
            pe_last_r <= mode[0] ? at_last_1x1 :
                         (((next_count7 == 3'd6) || (next_ofmap_col_index == cfg_f_last)) &&
                          (filter_col_cnt == 2'd2));
            layer_done_r <= mode[0] ? at_last_1x1 : at_last_op;
            filter_col_index_r <= {1'b0, active_filter_col};
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        for (int bank = 0; bank < 3; bank++) begin
            for (int row = 0; row < 7; row++) begin
                ifmap_pe_r[bank][row] <= 8'd0;
            end
        end
    end else if (op_hs) begin
        if (mode[0]) begin
            // A 1x1 group consumes all three SRAM-bank reads in the same
            // handshake.  The count3 stream scheduler remains 3x3-only.
            for (int row = 0; row < 7; row++) begin
                ifmap_pe_r[0][row] <= {~ifmap_0[row*8 + 7], ifmap_0[row*8 +: 7]};
                ifmap_pe_r[1][row] <= {~ifmap_1[row*8 + 7], ifmap_1[row*8 +: 7]};
                ifmap_pe_r[2][row] <= {~ifmap_2[row*8 + 7], ifmap_2[row*8 +: 7]};
            end
        end else begin
            unique case (ifmap_col_bank_sel)
                3'b001: begin
                    for (int row = 0; row < 7; row++)
                        ifmap_pe_r[0][row] <= {~ifmap_0[row*8 + 7], ifmap_0[row*8 +: 7]};
                end
                3'b010: begin
                    for (int row = 0; row < 7; row++)
                        ifmap_pe_r[0][row] <= {~ifmap_1[row*8 + 7], ifmap_1[row*8 +: 7]};
                end
                default: begin
                    for (int row = 0; row < 7; row++)
                        ifmap_pe_r[0][row] <= {~ifmap_2[row*8 + 7], ifmap_2[row*8 +: 7]};
                end
            endcase
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        filter_pe_r[0] <= 8'd0;
        filter_pe_r[1] <= 8'd0;
        filter_pe_r[2] <= 8'd0;
    end 
    else begin
        if (op_hs) begin
            if (mode[0]) begin
                // 1x1 phase is accumulator metadata.  The current filter beat
                // remains the packed {wch0, wch1, wch2} group in bank 0.
                filter_pe_r[0] <= filter_bank[0][0];
                filter_pe_r[1] <= filter_bank[0][1];
                filter_pe_r[2] <= filter_bank[0][2];
            end else begin
                filter_pe_r[0] <= filter_bank[active_filter_col][0];
                filter_pe_r[1] <= filter_bank[active_filter_col][1];
                filter_pe_r[2] <= filter_bank[active_filter_col][2];
            end
        end
    end
end

endmodule

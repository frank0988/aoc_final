`timescale 1ns/1ps

module top (
    input clk,
    input rst,

    input [55:0] input_zero_vec_i,
    input [55:0] output_zero_vec_i,

    // Input activation RLC token stream from TB or upstream bus.
    input [63:0] input_token_data_i,
    input input_token_valid_i,
    output input_token_ready_o,

    // Decoded input stream events for the future controller.
    output input_ctrl_valid_o,
    input input_ctrl_ready_i,
    output [15:0] input_ctrl_run_o,
    output [15:0] input_ctrl_dense_index_o,
    output input_ctrl_vec_nonzero_o,
    output input_ctrl_last_o,
    output input_ctrl_done_o,

    // Input SRAM debug/read port. Future compute/controller logic can own this.
    output input_sram_wen_o,
    output [15:0] input_sram_waddr_o,
    output [55:0] input_sram_wdata_o,
    output input_sram_ready_o,
    input [15:0] input_sram_raddr_i,
    output [55:0] input_sram_rdata_o,

    // Raw filter SRAM load/read port. Each beat is {filter[2], filter[1], filter[0]}.
    input weight_sram_wen_i,
    input [19:0] weight_sram_waddr_i,
    input [23:0] weight_sram_wdata_i,
    output weight_sram_ready_o,
    input [19:0] weight_sram_raddr_i,
    output [23:0] weight_sram_rdata_o,
    input weight_preload_done_i,
    input weight_preload_wen_i,
    input weight_preload_sram_sel_i,
    input [10:0] weight_preload_addr_i,
    input [23:0] weight_preload_wdata_i,
    output weight_preload_start_o,
    output weight_compute_sram_sel_o,
    output weight_preload_sram_sel_o,
    output [8:0] weight_current_m_o,
    output [8:0] weight_next_m_o,
    output weight_compute_done_o,
    output weight_swap_enable_o,

    // Direct packed-vector bypass into the output RLC encoder. The TB keeps
    // using this path for isolated RLC checks.
    input [55:0] ppu_data_i,
    input ppu_valid_i,
    input ppu_last_i,
    output ppu_ready_o,

    // Real PPU scalar path: accumulator/PPU scalar input -> PPU -> packer ->
    // output RLC encoder. Set output_use_hw_ppu_i=1 to select this path.
    input output_use_hw_ppu_i,
    input signed [31:0] ppu_scalar_data_i,
    input ppu_scalar_valid_i,
    input ppu_scalar_last_i,
    output ppu_scalar_ready_o,
    input [5:0] ppu_scaling_factor_i,
    input signed [31:0] ppu_bias_i,
    input ppu_relu_en_i,
    input ppu_maxpool_en_i,
    input ppu_maxpool_init_i,
    input ppu_maxpool_emit_i,

    // Temporary single-PE smoke path. This bypasses the real controller and
    // only proves PE -> accumulator -> PPU -> output RLC is physically wired.
    input output_use_pe_accum_i,
    input pe_accum_valid_i,
    output pe_accum_ready_o,
    input pe_mode_1x1_i,
    input [55:0] pe_ifmap_data_i,
    input [55:0] pe_ifmap_1x1_data_0_i,
    input [55:0] pe_ifmap_1x1_data_1_i,
    input [55:0] pe_ifmap_1x1_data_2_i,
    input [23:0] pe_weight_data_i,
    input pe_accum_last_i,
    input [9:0] pe_accum_base_idx_i,

    // Temporary Controller smoke path. SRAM data is wired into Controller,
    // Controller drives PE, and this top-level harness only supplies SRAM read
    // addresses plus a one-packet accumulator smoke capture.
    input output_use_controller_i,
    input [29:0] controller_config_i,
    input [15:0] controller_ifmap_base_addr_i,
    input [19:0] controller_filter_base_addr_i,
    input [15:0] controller_capture_limit_i,
    output controller_pe_fire_o,
    output [55:0] controller_pe_ifmap_o,
    output [23:0] controller_pe_weight_o,
    output [8:0] ppu_channel_o,

    // Output RLC token stream back to TB or downstream bus.
    output [63:0] output_token_data_o,
    output output_token_valid_o,
    input output_token_ready_i,

    output output_ctrl_busy_o,
    output output_ctrl_token_fire_o,
    output output_ctrl_done_o
);

wire encoder_vec_ready;
wire [55:0] encoder_vec_data;
wire encoder_vec_valid;
wire encoder_vec_last;

wire [55:0] input_sram_rdata_internal;
wire [55:0] input_sram_1x1_rdata_0;
wire [55:0] input_sram_1x1_rdata_1;
wire [55:0] input_sram_1x1_rdata_2;
wire [23:0] weight_sram_rdata_internal;
wire [23:0] pingpong_weight_rdata;
wire [15:0] selected_input_sram_raddr;
wire [15:0] controller_ifmap_group_raddr;
logic [4:0] controller_ifmap_w_group;
logic [4:0] controller_ifmap_groups_per_row;
wire [19:0] selected_weight_sram_raddr;

wire ppu_hw_in_ready;
wire ppu_hw_out_valid;
wire ppu_hw_out_ready;
wire [7:0] ppu_hw_out_data;
wire ppu_hw_out_last;

wire output_use_ppu_path;
wire selected_ppu_in_valid;
wire signed [31:0] selected_ppu_in_data;
wire selected_ppu_in_last;

wire pe_accum_fire;
wire pe_capture_fire;
wire pe_input_mode_1x1;
wire [55:0] pe_ifmap_selected;
wire [167:0] pe_ifmap_bank_selected;
wire [55:0] pe_ifmap_1x1_selected_0;
wire [55:0] pe_ifmap_1x1_selected_1;
wire [55:0] pe_ifmap_1x1_selected_2;
wire [23:0] pe_weight_selected;
wire signed [287:0] pe_psum_out;

wire [2:0] controller_ifmap_valid;
wire controller_filter_valid;
wire [2:0] controller_ifmap_ready;
wire controller_filter_ready;
wire controller_ctrl_ready;
wire controller_boundary_en;
wire controller_pe_block_en;
wire [4:0] controller_ofmap_col_index;
wire [4:0] controller_ofmap_row_index;
wire [8:0] controller_ifmap_ch_index;
wire [2:0] controller_filter_col_index;
wire [7:0] controller_ifmap_pe_0;
wire [7:0] controller_ifmap_pe_1;
wire [7:0] controller_ifmap_pe_2;
wire [7:0] controller_ifmap_pe_3;
wire [7:0] controller_ifmap_pe_4;
wire [7:0] controller_ifmap_pe_5;
wire [7:0] controller_ifmap_pe_6;
wire [55:0] controller_ifmap_pe_group_0;
wire [55:0] controller_ifmap_pe_group_1;
wire [55:0] controller_ifmap_pe_group_2;
wire [7:0] controller_filter_pe_0;
wire [7:0] controller_filter_pe_1;
wire [7:0] controller_filter_pe_2;
wire controller_first_col;
wire controller_last_col;
wire controller_first_channel;
wire controller_last_channel;
wire controller_boundary_final;
wire controller_pe_last;
wire controller_layer_done;
wire [8:0] controller_ofmap_ch_index;
wire [5:0] controller_ifmap_col_index;
wire [1:0] controller_filter_load_index;
wire [15:0] controller_ifmap_calc_raddr;
wire [19:0] controller_filter_calc_raddr;
wire [5:0] controller_input_w_span;
wire [8:0] controller_layer_e;
wire [8:0] controller_layer_c;
wire [19:0] controller_ifmap_linear;
wire [19:0] controller_filter_linear;
wire controller_mode_1x1;
wire controller_compute_sram_sel;
wire controller_preload_sram_sel;
wire controller_preload_start;
wire controller_compute_done;
wire controller_swap_enable;
wire [8:0] controller_current_m;
wire [8:0] controller_next_m;
wire controller_pe_fire;
wire controller_ifmap_hs;
wire controller_filter_hs;
wire controller_can_issue_pe;
wire [2:0] controller_ifmap_in_valid;
wire controller_filter_in_valid;

logic [15:0] controller_ifmap_raddr;
logic [19:0] controller_filter_raddr;
logic [15:0] controller_capture_count;
logic controller_issue_inflight;
logic controller_ifmap_fetch_valid;
logic controller_filter_fetch_valid;

logic pe_capture_pending;
logic pe_acc_valid_hold;
logic signed [287:0] pe_psum_hold;
logic pe_mode_1x1_pending;
logic pe_mode_1x1_hold;
logic pe_last_pending;
logic pe_last_hold;
logic [9:0] pe_base_idx_pending;
logic [9:0] pe_base_idx_hold;
logic pe_first_col_pending;
logic pe_first_col_hold;
logic pe_last_col_pending;
logic pe_last_col_hold;
logic pe_first_channel_pending;
logic pe_first_channel_hold;
logic pe_last_channel_pending;
logic pe_last_channel_hold;
logic pe_boundary_en_pending;
logic pe_boundary_en_hold;
logic [8:0] pe_ofmap_ch_pending;
logic [8:0] pe_ofmap_ch_hold;
logic [4:0] pe_ofmap_col_pending;
logic [4:0] pe_ofmap_col_hold;
logic [4:0] pe_ofmap_row_pending;
logic [4:0] pe_ofmap_row_hold;
logic [5:0] pe_ofmap_width_pending;
logic [5:0] pe_ofmap_width_hold;

logic issue_first_channel;
logic issue_last_channel;
logic issue_boundary_en;
logic issue_layer_done;
logic [8:0] issue_ofmap_ch;
logic issue_first_col;
logic issue_last_col;
logic [4:0] issue_ofmap_col;
logic [4:0] issue_ofmap_row;

wire acc_in_ready;
logic signed [8:0][31:0] acc_pe_data;
logic [8:0] acc_pe_valid;
logic [8:0][9:0] acc_pe_idx;
logic [8:0] acc_pe_last;
wire [8:0] acc_first_col;
wire [8:0] acc_last_col;
logic [8:0] acc_boundary_en;
logic [8:0][0:0] acc_boundary_row;
logic [8:0][5:0] acc_boundary_f_idx;
wire acc_ppu_valid;
wire acc_ppu_ready;
wire signed [31:0] acc_ppu_data;
wire [8:0] acc_ppu_channel;
wire acc_ppu_last;

wire [55:0] packer_rlc_data;
wire packer_rlc_valid;
wire packer_rlc_ready;
wire packer_rlc_last;

assign output_use_ppu_path = output_use_hw_ppu_i || output_use_pe_accum_i || output_use_controller_i;

assign ppu_ready_o = output_use_ppu_path ? 1'b0 : encoder_vec_ready;
assign ppu_scalar_ready_o = output_use_hw_ppu_i && !output_use_pe_accum_i &&
                            !output_use_controller_i && ppu_hw_in_ready;
assign packer_rlc_ready = output_use_ppu_path ? encoder_vec_ready : 1'b0;

assign selected_ppu_in_valid = (output_use_pe_accum_i || output_use_controller_i) ? acc_ppu_valid :
                               (output_use_hw_ppu_i && ppu_scalar_valid_i);
assign selected_ppu_in_data = (output_use_pe_accum_i || output_use_controller_i) ? acc_ppu_data : ppu_scalar_data_i;
assign selected_ppu_in_last = (output_use_pe_accum_i || output_use_controller_i) ? acc_ppu_last : ppu_scalar_last_i;
assign acc_ppu_ready = (output_use_pe_accum_i || output_use_controller_i) && ppu_hw_in_ready;
assign ppu_channel_o = (output_use_pe_accum_i || output_use_controller_i) ? acc_ppu_channel : 9'd0;

assign encoder_vec_data = output_use_ppu_path ? packer_rlc_data : ppu_data_i;
assign encoder_vec_valid = output_use_ppu_path ? packer_rlc_valid : ppu_valid_i;
assign encoder_vec_last = output_use_ppu_path ? packer_rlc_last : ppu_last_i;

assign controller_mode_1x1 = controller_config_i[28];
assign controller_input_w_span = controller_mode_1x1 ? ({1'b0, controller_config_i[4:0]} + 6'd1)
                                                    : ({1'b0, controller_config_i[4:0]} + 6'd3);
assign controller_layer_e = {4'd0, controller_config_i[9:5]} + 9'd1;
assign controller_layer_c = controller_config_i[27:19];

always_comb begin
    unique case (controller_ifmap_col_index)
        6'd0,  6'd1,  6'd2:  controller_ifmap_w_group = 5'd0;
        6'd3,  6'd4,  6'd5:  controller_ifmap_w_group = 5'd1;
        6'd6,  6'd7,  6'd8:  controller_ifmap_w_group = 5'd2;
        6'd9,  6'd10, 6'd11: controller_ifmap_w_group = 5'd3;
        6'd12, 6'd13, 6'd14: controller_ifmap_w_group = 5'd4;
        6'd15, 6'd16, 6'd17: controller_ifmap_w_group = 5'd5;
        6'd18, 6'd19, 6'd20: controller_ifmap_w_group = 5'd6;
        6'd21, 6'd22, 6'd23: controller_ifmap_w_group = 5'd7;
        6'd24, 6'd25, 6'd26: controller_ifmap_w_group = 5'd8;
        6'd27, 6'd28, 6'd29: controller_ifmap_w_group = 5'd9;
        6'd30, 6'd31, 6'd32: controller_ifmap_w_group = 5'd10;
        default:              controller_ifmap_w_group = 5'd11;
    endcase

    unique case (controller_config_i[4:0])
        5'd0:  controller_ifmap_groups_per_row = 5'd1;
        5'd1,  5'd2,  5'd3:  controller_ifmap_groups_per_row = 5'd2;
        5'd4,  5'd5,  5'd6:  controller_ifmap_groups_per_row = 5'd3;
        5'd7,  5'd8,  5'd9:  controller_ifmap_groups_per_row = 5'd4;
        5'd10, 5'd11, 5'd12: controller_ifmap_groups_per_row = 5'd5;
        5'd13, 5'd14, 5'd15: controller_ifmap_groups_per_row = 5'd6;
        5'd16, 5'd17, 5'd18: controller_ifmap_groups_per_row = 5'd7;
        5'd19, 5'd20, 5'd21: controller_ifmap_groups_per_row = 5'd8;
        5'd22, 5'd23, 5'd24: controller_ifmap_groups_per_row = 5'd9;
        5'd25, 5'd26, 5'd27: controller_ifmap_groups_per_row = 5'd10;
        5'd28, 5'd29, 5'd30: controller_ifmap_groups_per_row = 5'd11;
        default:              controller_ifmap_groups_per_row = 5'd12;
    endcase
end

assign controller_ifmap_linear = controller_mode_1x1 ?
                                 20'(controller_ifmap_ch_index) :
                                 (((20'(controller_ifmap_ch_index) * 20'(controller_layer_e)) +
                                   20'(controller_ofmap_row_index)) *
                                  20'(controller_ifmap_groups_per_row)) +
                                 20'(controller_ifmap_w_group);
assign controller_filter_linear = controller_mode_1x1 ?
                                  ((20'(controller_ofmap_ch_index) * 20'(controller_layer_c)) +
                                   20'(controller_ifmap_ch_index)) :
                                  ((((20'(controller_ofmap_ch_index) * 20'(controller_layer_c)) +
                                     20'(controller_ifmap_ch_index)) * 20'd3) +
                                   20'(controller_filter_load_index));
assign controller_ifmap_calc_raddr = controller_ifmap_linear[15:0];
assign controller_ifmap_group_raddr = controller_ifmap_calc_raddr;
assign controller_filter_calc_raddr = controller_filter_linear;
assign selected_input_sram_raddr = output_use_controller_i ? controller_ifmap_calc_raddr : input_sram_raddr_i;
assign selected_weight_sram_raddr = output_use_controller_i ? controller_filter_calc_raddr : weight_sram_raddr_i;
assign input_sram_rdata_o = input_sram_rdata_internal;
assign weight_sram_rdata_o = weight_sram_rdata_internal;
assign weight_preload_start_o = controller_preload_start;
assign weight_compute_sram_sel_o = controller_compute_sram_sel;
assign weight_preload_sram_sel_o = controller_preload_sram_sel;
assign weight_current_m_o = controller_current_m;
assign weight_next_m_o = controller_next_m;
assign weight_compute_done_o = controller_compute_done;
assign weight_swap_enable_o = controller_swap_enable;

assign pe_accum_ready_o = output_use_pe_accum_i && !output_use_controller_i && acc_in_ready &&
                          !pe_capture_pending && !pe_acc_valid_hold;
assign pe_accum_fire = pe_accum_valid_i && pe_accum_ready_o;
assign controller_can_issue_pe = output_use_controller_i && acc_in_ready &&
                                 !pe_capture_pending && !pe_acc_valid_hold &&
                                 !controller_issue_inflight &&
                                 ((controller_capture_limit_i == 16'd0) ||
                                  (controller_capture_count < controller_capture_limit_i));
// SRAM_rtl has a registered read port.  Fetch each controller operand for one
// cycle before advertising valid, so Controller samples the matching Q value.
assign controller_ifmap_in_valid = (controller_can_issue_pe && controller_ifmap_fetch_valid) ?
                                  controller_ifmap_ready : 3'b000;
assign controller_filter_in_valid = (output_use_controller_i && controller_filter_fetch_valid) ?
                                   controller_filter_ready : 1'b0;
assign controller_pe_fire = output_use_controller_i &&
                            controller_filter_valid && (|controller_ifmap_valid) &&
                            ((controller_capture_limit_i == 16'd0) ||
                             (controller_capture_count < controller_capture_limit_i));
assign controller_pe_fire_o = controller_pe_fire;
assign controller_pe_ifmap_o = {controller_ifmap_pe_6, controller_ifmap_pe_5,
                                controller_ifmap_pe_4, controller_ifmap_pe_3,
                                controller_ifmap_pe_2, controller_ifmap_pe_1,
                                controller_ifmap_pe_0};
assign controller_pe_weight_o = {controller_filter_pe_2, controller_filter_pe_1, controller_filter_pe_0};
assign pe_capture_fire = pe_accum_fire ||
                         (controller_pe_fire && !pe_capture_pending && !pe_acc_valid_hold);
assign pe_input_mode_1x1 = output_use_controller_i ? controller_config_i[28] : pe_mode_1x1_i;
assign pe_ifmap_selected = output_use_controller_i ? controller_pe_ifmap_o : pe_ifmap_data_i;
// Direct PE tests may drive three channel-group vectors independently.
// The controller branch remains temporarily mirrored until its banked group
// issue protocol is converted to one three-operand handshake.
assign pe_ifmap_1x1_selected_0 = output_use_controller_i ? controller_ifmap_pe_group_0 :
                                  pe_ifmap_1x1_data_0_i;
assign pe_ifmap_1x1_selected_1 = output_use_controller_i ? controller_ifmap_pe_group_1 :
                                  pe_ifmap_1x1_data_1_i;
assign pe_ifmap_1x1_selected_2 = output_use_controller_i ? controller_ifmap_pe_group_2 :
                                  pe_ifmap_1x1_data_2_i;
assign pe_ifmap_bank_selected = pe_input_mode_1x1 ?
                                {pe_ifmap_1x1_selected_2, pe_ifmap_1x1_selected_1, pe_ifmap_1x1_selected_0} :
                                {112'd0, pe_ifmap_selected};
assign pe_weight_selected = output_use_controller_i ? controller_pe_weight_o : pe_weight_data_i;
assign controller_ifmap_hs = output_use_controller_i && (|(controller_ifmap_in_valid & controller_ifmap_ready));
assign controller_filter_hs = output_use_controller_i && controller_filter_in_valid && controller_filter_ready;

always_comb begin
    for (int lane = 0; lane < 9; lane++) begin
        acc_pe_data[lane] = pe_psum_hold[(lane * 32) +: 32];
        acc_pe_idx[lane] = pe_base_idx_hold + 10'(lane);
        acc_boundary_en[lane] = pe_boundary_en_hold;
        acc_boundary_row[lane] = pe_ofmap_row_hold[0];
        acc_boundary_f_idx[lane] = {1'b0, pe_ofmap_col_hold} + 6'(lane);
        if (output_use_controller_i) begin
            if (pe_mode_1x1_hold) begin
                acc_pe_valid[lane] = (lane == 0);
                acc_pe_last[lane] = pe_last_hold && (lane == 0);
            end else begin
                // psum[2] is the valid 3-tap vertical convolution at the
                // current E row.  One PE block has no inter-block boundary.
                acc_pe_valid[lane] = (lane == 2);
                acc_pe_idx[lane] = pe_base_idx_hold;
                acc_boundary_en[lane] = 1'b0;
                acc_boundary_f_idx[lane] = {1'b0, pe_ofmap_col_hold};
                acc_pe_last[lane] = pe_last_hold && (lane == 2);
            end
        end else begin
            acc_pe_valid[lane] = (({1'b0, pe_ofmap_col_hold} + 6'(lane)) < pe_ofmap_width_hold);
            acc_pe_last[lane] = pe_last_hold && acc_pe_valid[lane] &&
                                ((({1'b0, pe_ofmap_col_hold} + 6'(lane) + 6'd1) >= pe_ofmap_width_hold) ||
                                 (lane == 8));
        end
    end
end

// acc_pe_valid/acc_pe_last are generated per lane in the sideband loop above.
assign acc_first_col = {9{pe_first_col_hold}};
assign acc_last_col = {9{pe_last_col_hold}};

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        pe_capture_pending <= 1'b0;
        pe_acc_valid_hold <= 1'b0;
        pe_psum_hold <= '0;
        controller_capture_count <= 16'd0;
        controller_issue_inflight <= 1'b0;
        pe_mode_1x1_pending <= 1'b0;
        pe_mode_1x1_hold <= 1'b0;
        pe_last_pending <= 1'b0;
        pe_last_hold <= 1'b0;
        pe_base_idx_pending <= 10'd0;
        pe_base_idx_hold <= 10'd0;
        pe_first_col_pending <= 1'b0;
        pe_first_col_hold <= 1'b0;
        pe_last_col_pending <= 1'b0;
        pe_last_col_hold <= 1'b0;
        pe_first_channel_pending <= 1'b0;
        pe_first_channel_hold <= 1'b0;
        pe_last_channel_pending <= 1'b0;
        pe_last_channel_hold <= 1'b0;
        pe_boundary_en_pending <= 1'b0;
        pe_boundary_en_hold <= 1'b0;
        pe_ofmap_ch_pending <= 9'd0;
        pe_ofmap_ch_hold <= 9'd0;
        pe_ofmap_col_pending <= 5'd0;
        pe_ofmap_col_hold <= 5'd0;
        pe_ofmap_row_pending <= 5'd0;
        pe_ofmap_row_hold <= 5'd0;
        pe_ofmap_width_pending <= 6'd1;
        pe_ofmap_width_hold <= 6'd1;
        issue_first_channel <= 1'b0;
        issue_last_channel <= 1'b0;
        issue_boundary_en <= 1'b0;
        issue_layer_done <= 1'b0;
        issue_ofmap_ch <= 9'd0;
        issue_first_col <= 1'b0;
        issue_last_col <= 1'b0;
        issue_ofmap_col <= 5'd0;
        issue_ofmap_row <= 5'd0;
    end else begin
        if (pe_acc_valid_hold && acc_in_ready) begin
            pe_acc_valid_hold <= 1'b0;
        end

        if (pe_capture_pending && !pe_acc_valid_hold) begin
            pe_capture_pending <= 1'b0;
            pe_acc_valid_hold <= 1'b1;
            pe_psum_hold <= pe_psum_out;
            pe_mode_1x1_hold <= pe_mode_1x1_pending;
            pe_last_hold <= pe_last_pending;
            pe_base_idx_hold <= pe_base_idx_pending;
            pe_first_col_hold <= pe_first_col_pending;
            pe_last_col_hold <= pe_last_col_pending;
            pe_first_channel_hold <= pe_first_channel_pending;
            pe_last_channel_hold <= pe_last_channel_pending;
            pe_boundary_en_hold <= pe_boundary_en_pending;
            pe_ofmap_ch_hold <= pe_ofmap_ch_pending;
            pe_ofmap_col_hold <= pe_ofmap_col_pending;
            pe_ofmap_row_hold <= pe_ofmap_row_pending;
            pe_ofmap_width_hold <= pe_ofmap_width_pending;
        end

        if (!output_use_controller_i) begin
            controller_capture_count <= 16'd0;
            controller_issue_inflight <= 1'b0;
        end else begin
            if (controller_ifmap_hs) begin
                controller_issue_inflight <= 1'b1;
                // m/e are live Controller counters for SRAM addressing.  Keep
                // their operation coordinates until the registered PE data fires.
                issue_ofmap_ch <= controller_ofmap_ch_index;
                issue_ofmap_row <= controller_ofmap_row_index;
            end
            if (controller_pe_fire) begin
                controller_issue_inflight <= 1'b0;
            end
        end

        if (pe_capture_fire) begin
            pe_capture_pending <= 1'b1;
            pe_mode_1x1_pending <= output_use_controller_i ? controller_config_i[28] : pe_mode_1x1_i;
            pe_last_pending <= output_use_controller_i ? controller_layer_done : pe_accum_last_i;
            pe_base_idx_pending <= output_use_controller_i ?
                                   {5'd0, controller_ofmap_col_index} :
                                   pe_accum_base_idx_i;
            pe_first_col_pending <= output_use_controller_i ? controller_first_col : 1'b1;
            pe_last_col_pending <= output_use_controller_i ? controller_last_col : 1'b1;
            pe_first_channel_pending <= output_use_controller_i ? controller_first_channel : 1'b1;
            pe_last_channel_pending <= output_use_controller_i ? controller_last_channel : 1'b1;
            pe_boundary_en_pending <= output_use_controller_i ? controller_boundary_en : 1'b0;
            pe_ofmap_ch_pending <= output_use_controller_i ? issue_ofmap_ch : 9'd0;
            pe_ofmap_col_pending <= output_use_controller_i ? controller_ofmap_col_index :
                                     pe_accum_base_idx_i[4:0];
            pe_ofmap_row_pending <= output_use_controller_i ? issue_ofmap_row : 5'd0;
            pe_ofmap_width_pending <= output_use_controller_i ?
                                      ({1'b0, controller_config_i[4:0]} + 6'd1) : 6'd1;
            if (output_use_controller_i &&
                ((controller_capture_limit_i == 16'd0) ||
                 (controller_capture_count < controller_capture_limit_i))) begin
                controller_capture_count <= controller_capture_count + 16'd1;
            end
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        controller_ifmap_fetch_valid <= 1'b0;
        controller_filter_fetch_valid <= 1'b0;
    end else if (!output_use_controller_i) begin
        controller_ifmap_fetch_valid <= 1'b0;
        controller_filter_fetch_valid <= 1'b0;
    end else begin
        if (!(|controller_ifmap_ready) || !controller_can_issue_pe) begin
            controller_ifmap_fetch_valid <= 1'b0;
        end else if (controller_ifmap_hs) begin
            controller_ifmap_fetch_valid <= 1'b0;
        end else begin
            controller_ifmap_fetch_valid <= 1'b1;
        end

        if (!controller_filter_ready) begin
            controller_filter_fetch_valid <= 1'b0;
        end else if (controller_filter_hs) begin
            controller_filter_fetch_valid <= 1'b0;
        end else begin
            controller_filter_fetch_valid <= 1'b1;
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        controller_ifmap_raddr <= 16'd0;
        controller_filter_raddr <= 20'd0;
    end else if (!output_use_controller_i) begin
        controller_ifmap_raddr <= controller_ifmap_base_addr_i;
        controller_filter_raddr <= controller_filter_base_addr_i;
    end else begin
        if (controller_ifmap_hs) begin
            controller_ifmap_raddr <= controller_ifmap_raddr + 16'd1;
        end
        if (controller_filter_hs) begin
            controller_filter_raddr <= controller_filter_raddr + 20'd1;
        end
    end
end

input_RLC_decoder u_input_RLC_decoder (
    .clk(clk),
    .rst(rst),
    .token_data_i(input_token_data_i),
    .token_valid_i(input_token_valid_i),
    .token_ready_o(input_token_ready_o),
    .ctrl_valid_o(input_ctrl_valid_o),
    .ctrl_ready_i(input_ctrl_ready_i),
    .ctrl_run_o(input_ctrl_run_o),
    .ctrl_dense_index_o(input_ctrl_dense_index_o),
    .ctrl_vec_nonzero_o(input_ctrl_vec_nonzero_o),
    .ctrl_last_o(input_ctrl_last_o),
    .ctrl_done_o(input_ctrl_done_o),
    .input_sram_wen_o(input_sram_wen_o),
    .input_sram_waddr_o(input_sram_waddr_o),
    .input_sram_wdata_o(input_sram_wdata_o),
    .input_sram_ready_i(input_sram_ready_o),
    .zero_vec_i(input_zero_vec_i)
);

input_sram_wrapper u_input_sram_reg (
    .clk(clk),
    .rst(rst),
    .mode_1x1_i(controller_mode_1x1),
    .wen_i(input_sram_wen_o),
    .waddr_i(input_sram_waddr_o),
    .wdata_i(input_sram_wdata_o),
    .ready_o(input_sram_ready_o),
    .raddr_i(selected_input_sram_raddr),
    .default_rdata_i(input_zero_vec_i),
    .rdata_o(input_sram_rdata_internal),
    .rdata_1x1_0_o(input_sram_1x1_rdata_0),
    .rdata_1x1_1_o(input_sram_1x1_rdata_1),
    .rdata_1x1_2_o(input_sram_1x1_rdata_2)
);

weight_pingpong_wrapper u_weight_pingpong (
    .clk(clk), .rst(rst),
    .compute_sram_sel(controller_compute_sram_sel),
    .compute_addr(controller_mode_1x1 ? {2'd0, controller_ifmap_ch_index} :
                  ((controller_ifmap_ch_index * 11'd3) + {9'd0, controller_filter_load_index})),
    .compute_rdata(pingpong_weight_rdata),
    .preload_sram_sel(weight_preload_sram_sel_i),
    .preload_wen(weight_preload_wen_i),
    .preload_addr(weight_preload_addr_i),
    .preload_wdata(weight_preload_wdata_i),
    .preload_ready()
);

weight_sram_wrapper u_weight_sram_reg (
    .clk(clk),
    .rst(rst),
    .wen_i(weight_sram_wen_i),
    .waddr_i(weight_sram_waddr_i),
    .wdata_i(weight_sram_wdata_i),
    .ready_o(weight_sram_ready_o),
    .raddr_i(selected_weight_sram_raddr),
    .rdata_o(weight_sram_rdata_internal)
);

Controller u_controller (
    .clk(clk),
    .rst(rst),
    .pe_en(output_use_controller_i),
    .i_config(controller_config_i),

    .ifmap_0(input_sram_1x1_rdata_0),
    .ifmap_1(input_sram_1x1_rdata_1),
    .ifmap_2(input_sram_1x1_rdata_2),
    .filter(output_use_controller_i ? pingpong_weight_rdata : weight_sram_rdata_internal),
    .ipsum(32'd0),

    .ifmap_in_valid(controller_ifmap_in_valid),
    .filter_in_valid(controller_filter_in_valid),
    .ipsum_ready(1'b0),
    .load_ready(1'b1),
    .opsum_valid(1'b0),
    .preload_done(weight_preload_done_i),

    .ifmap_valid(controller_ifmap_valid),
    .filter_valid(controller_filter_valid),
    .ipsum_valid(),
    .opsum_ready(),
    .ctrl_ready(controller_ctrl_ready),
    .opsum(),

    .ifmap_ready(controller_ifmap_ready),
    .filter_ready(controller_filter_ready),
    .boundary_en(controller_boundary_en),
    .pe_block_en(controller_pe_block_en),
    .ofmap_col_index(controller_ofmap_col_index),
    .ofmap_row_index(controller_ofmap_row_index),
    .ifmap_ch_index(controller_ifmap_ch_index),
    .filter_col_index(controller_filter_col_index),

    .ifmap_pe_0(controller_ifmap_pe_0),
    .ifmap_pe_1(controller_ifmap_pe_1),
    .ifmap_pe_2(controller_ifmap_pe_2),
    .ifmap_pe_3(controller_ifmap_pe_3),
    .ifmap_pe_4(controller_ifmap_pe_4),
    .ifmap_pe_5(controller_ifmap_pe_5),
    .ifmap_pe_6(controller_ifmap_pe_6),
    .ifmap_pe_group_0(controller_ifmap_pe_group_0),
    .ifmap_pe_group_1(controller_ifmap_pe_group_1),
    .ifmap_pe_group_2(controller_ifmap_pe_group_2),
    .filter_pe_0(controller_filter_pe_0),
    .filter_pe_1(controller_filter_pe_1),
    .filter_pe_2(controller_filter_pe_2),

    .first_col(controller_first_col),
    .last_col(controller_last_col),
    .first_channel(controller_first_channel),
    .last_channel(controller_last_channel),
    .boundary_final(controller_boundary_final),
    .pe_last(controller_pe_last),
    .layer_done(controller_layer_done),
    .ofmap_ch_index(controller_ofmap_ch_index),
    .ifmap_col_index(controller_ifmap_col_index),
    .filter_load_index(controller_filter_load_index),
    .compute_sram_sel(controller_compute_sram_sel),
    .preload_sram_sel(controller_preload_sram_sel),
    .preload_start(controller_preload_start),
    .compute_done(controller_compute_done),
    .swap_enable(controller_swap_enable),
    .current_m(controller_current_m),
    .next_m(controller_next_m)
);

pe_block_7x3 u_pe_block_7x3 (
    .clk(clk),
    .rst_n(~rst),
    .mode_1x1(pe_input_mode_1x1),
    .ifmap_data(pe_ifmap_bank_selected),
    .weight_data(pe_weight_selected),
    .all_zero_ifmap(),
    .all_zero_weight(),
    .psum_out(pe_psum_out)
);

accumulator #(
    .NUM_LANES(9),
    .DATA_W(32),
    .IDX_W(10),
    .F_W(6)
) u_accumulator (
    .clk(clk),
    .rst(rst),

    .in_valid((output_use_pe_accum_i || output_use_controller_i) && pe_acc_valid_hold),
    .in_ready(acc_in_ready),
    .pe_data(acc_pe_data),
    .pe_valid(acc_pe_valid),
    .pe_idx(acc_pe_idx),
    .pe_last(acc_pe_last),

    .first_col(acc_first_col),
    .last_col(acc_last_col),
    .mode({1'b0, pe_mode_1x1_hold}),
    .first_channel(pe_first_channel_hold),
    .last_channel(pe_last_channel_hold),

    .boundary_en(acc_boundary_en),
    .output_channel_m(output_use_controller_i ? pe_ofmap_ch_hold : 9'd0),
    .ofmap_width_F(pe_ofmap_width_hold),
    .boundary_row(acc_boundary_row),
    .f_idx(acc_boundary_f_idx),

    .ppu_valid(acc_ppu_valid),
    .ppu_ready(acc_ppu_ready),
    .ppu_data(acc_ppu_data),
    .ppu_idx(),
    .ppu_channel_m(acc_ppu_channel),
    .ppu_last(acc_ppu_last)
);

PPU u_ppu (
    .clk(clk),
    .rst(rst),

    .in_valid(selected_ppu_in_valid),
    .in_ready(ppu_hw_in_ready),
    .data_in(selected_ppu_in_data),
    .in_last(selected_ppu_in_last),

    .bias_i(ppu_bias_i),
    .scaling_factor(ppu_scaling_factor_i),
    .maxpool_en(ppu_maxpool_en_i),
    .maxpool_init(ppu_maxpool_init_i),
    .maxpool_emit(ppu_maxpool_emit_i),
    .relu_en(ppu_relu_en_i),

    .out_valid(ppu_hw_out_valid),
    .out_ready(ppu_hw_out_ready),
    .data_out(ppu_hw_out_data),
    .out_last(ppu_hw_out_last)
);
PPU_to_RLC_Packer u_ppu_to_rlc_packer (
    .clk(clk),
    .rst(rst),

    .scalar_valid_i(ppu_hw_out_valid),
    .scalar_ready_o(ppu_hw_out_ready),
    .scalar_data_i(ppu_hw_out_data),
    .scalar_last_i(ppu_hw_out_last),
    .pad_data_i(output_zero_vec_i[7:0]),

    .rlc_data_o(packer_rlc_data),
    .rlc_valid_o(packer_rlc_valid),
    .rlc_ready_i(packer_rlc_ready),
    .rlc_last_o(packer_rlc_last)
);

output_RLC_encoder u_output_RLC_encoder (
    .clk(clk),
    .rst(rst),
    .ppu_data_i(encoder_vec_data),
    .ppu_valid_i(encoder_vec_valid),
    .ppu_last_i(encoder_vec_last),
    .ppu_ready_o(encoder_vec_ready),
    .zero_vec_i(output_zero_vec_i),
    .token_data_o(output_token_data_o),
    .token_valid_o(output_token_valid_o),
    .token_ready_i(output_token_ready_i),
    .ctrl_busy_o(output_ctrl_busy_o),
    .ctrl_token_fire_o(output_ctrl_token_fire_o),
    .ctrl_done_o(output_ctrl_done_o)
);

endmodule

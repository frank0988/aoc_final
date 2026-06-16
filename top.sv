`timescale 1ns/1ps

module top (
    input clk,
    input rst,

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
    input [15:0] weight_sram_waddr_i,
    input [23:0] weight_sram_wdata_i,
    output weight_sram_ready_o,
    input [15:0] weight_sram_raddr_i,
    output [23:0] weight_sram_rdata_o,

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
    input [23:0] pe_weight_data_i,
    input pe_accum_last_i,
    input [9:0] pe_accum_base_idx_i,

    // Temporary Controller smoke path. SRAM data is wired into Controller,
    // Controller drives PE, and this top-level harness only supplies SRAM read
    // addresses plus a one-packet accumulator smoke capture.
    input output_use_controller_i,
    input [29:0] controller_config_i,
    input [15:0] controller_ifmap_base_addr_i,
    input [15:0] controller_filter_base_addr_i,
    input [15:0] controller_capture_limit_i,
    output controller_pe_fire_o,
    output [55:0] controller_pe_ifmap_o,
    output [23:0] controller_pe_weight_o,

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
wire [23:0] weight_sram_rdata_internal;
wire [15:0] selected_input_sram_raddr;
wire [15:0] selected_weight_sram_raddr;

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
wire [7:0] controller_filter_pe_0;
wire [7:0] controller_filter_pe_1;
wire [7:0] controller_filter_pe_2;
wire controller_first_col;
wire controller_last_col;
wire controller_first_channel;
wire controller_last_channel;
wire controller_boundary_final;
wire controller_pe_last;
wire controller_pe_fire;
wire controller_ifmap_hs;
wire controller_filter_hs;
wire controller_can_issue_pe;
wire [2:0] controller_ifmap_in_valid;
wire controller_filter_in_valid;

logic [15:0] controller_ifmap_raddr;
logic [15:0] controller_filter_raddr;
logic [15:0] controller_capture_count;
logic controller_issue_inflight;

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
logic [4:0] pe_ofmap_col_pending;
logic [4:0] pe_ofmap_col_hold;
logic [4:0] pe_ofmap_row_pending;
logic [4:0] pe_ofmap_row_hold;
logic [4:0] pe_ofmap_width_pending;
logic [4:0] pe_ofmap_width_hold;

wire acc_in_ready;
logic signed [8:0][31:0] acc_pe_data;
wire [8:0] acc_pe_valid;
logic [8:0][9:0] acc_pe_idx;
wire [8:0] acc_pe_last;
wire [8:0] acc_first_col;
wire [8:0] acc_last_col;
logic [8:0] acc_boundary_en;
logic [8:0][0:0] acc_boundary_row;
logic [8:0][4:0] acc_boundary_f_idx;
wire acc_ppu_valid;
wire acc_ppu_ready;
wire signed [31:0] acc_ppu_data;
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

assign encoder_vec_data = output_use_ppu_path ? packer_rlc_data : ppu_data_i;
assign encoder_vec_valid = output_use_ppu_path ? packer_rlc_valid : ppu_valid_i;
assign encoder_vec_last = output_use_ppu_path ? packer_rlc_last : ppu_last_i;

assign selected_input_sram_raddr = output_use_controller_i ? controller_ifmap_raddr : input_sram_raddr_i;
assign selected_weight_sram_raddr = output_use_controller_i ? controller_filter_raddr : weight_sram_raddr_i;
assign input_sram_rdata_o = input_sram_rdata_internal;
assign weight_sram_rdata_o = weight_sram_rdata_internal;

assign pe_accum_ready_o = output_use_pe_accum_i && !output_use_controller_i && acc_in_ready &&
                          !pe_capture_pending && !pe_acc_valid_hold;
assign pe_accum_fire = pe_accum_valid_i && pe_accum_ready_o;
assign controller_can_issue_pe = output_use_controller_i && acc_in_ready &&
                                 !pe_capture_pending && !pe_acc_valid_hold &&
                                 !controller_issue_inflight &&
                                 (controller_capture_count < controller_capture_limit_i);
assign controller_ifmap_in_valid = controller_can_issue_pe ? controller_ifmap_ready : 3'b000;
assign controller_filter_in_valid = output_use_controller_i && controller_filter_ready;
assign controller_pe_fire = output_use_controller_i && controller_pe_block_en &&
                            controller_filter_valid && (|controller_ifmap_valid) &&
                            (controller_capture_count < controller_capture_limit_i);
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
assign pe_weight_selected = output_use_controller_i ? controller_pe_weight_o : pe_weight_data_i;
assign controller_ifmap_hs = output_use_controller_i && (|(controller_ifmap_in_valid & controller_ifmap_ready));
assign controller_filter_hs = output_use_controller_i && controller_filter_in_valid && controller_filter_ready;

always_comb begin
    for (int lane = 0; lane < 9; lane++) begin
        acc_pe_data[lane] = pe_psum_hold[(lane * 32) +: 32];
        acc_pe_idx[lane] = pe_base_idx_hold + 10'(lane);
        acc_boundary_en[lane] = pe_boundary_en_hold;
        acc_boundary_row[lane] = pe_ofmap_row_hold[0];
        acc_boundary_f_idx[lane] = pe_ofmap_col_hold + 5'(lane);
    end
end

assign acc_pe_valid = pe_mode_1x1_hold ? 9'b001111111 : 9'b111111111;
assign acc_pe_last = pe_last_hold ? (pe_mode_1x1_hold ? 9'b001000000 : 9'b100000000) : 9'd0;
assign acc_first_col = output_use_controller_i ? 9'h1ff : {9{pe_first_col_hold}};
assign acc_last_col = output_use_controller_i ? 9'h1ff : {9{pe_last_col_hold}};

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
        pe_ofmap_col_pending <= 5'd0;
        pe_ofmap_col_hold <= 5'd0;
        pe_ofmap_row_pending <= 5'd0;
        pe_ofmap_row_hold <= 5'd0;
        pe_ofmap_width_pending <= 5'd1;
        pe_ofmap_width_hold <= 5'd1;
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
            end
            if (controller_pe_fire) begin
                controller_issue_inflight <= 1'b0;
            end
        end

        if (pe_capture_fire) begin
            pe_capture_pending <= 1'b1;
            pe_mode_1x1_pending <= output_use_controller_i ? controller_config_i[28] : pe_mode_1x1_i;
            pe_last_pending <= output_use_controller_i ?
                               ((controller_capture_count + 16'd1) >= controller_capture_limit_i) :
                               pe_accum_last_i;
            pe_base_idx_pending <= output_use_controller_i ?
                                   {1'b0, controller_capture_count[8:0]} * 10'd9 :
                                   pe_accum_base_idx_i;
            pe_first_col_pending <= output_use_controller_i ? controller_first_col : 1'b1;
            pe_last_col_pending <= output_use_controller_i ? controller_last_col : 1'b1;
            pe_first_channel_pending <= output_use_controller_i ? controller_first_channel : 1'b1;
            pe_last_channel_pending <= output_use_controller_i ? controller_last_channel : 1'b1;
            pe_boundary_en_pending <= output_use_controller_i ? controller_boundary_en : 1'b0;
            pe_ofmap_col_pending <= output_use_controller_i ? controller_ofmap_col_index :
                                     pe_accum_base_idx_i[4:0];
            pe_ofmap_row_pending <= output_use_controller_i ? controller_ofmap_row_index : 5'd0;
            pe_ofmap_width_pending <= output_use_controller_i ?
                                      (controller_config_i[4:0] + 5'd1) : 5'd1;
            if (output_use_controller_i && controller_capture_count < controller_capture_limit_i) begin
                controller_capture_count <= controller_capture_count + 16'd1;
            end
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        controller_ifmap_raddr <= 16'd0;
        controller_filter_raddr <= 16'd0;
    end else if (!output_use_controller_i) begin
        controller_ifmap_raddr <= controller_ifmap_base_addr_i;
        controller_filter_raddr <= controller_filter_base_addr_i;
    end else begin
        if (controller_ifmap_hs) begin
            controller_ifmap_raddr <= controller_ifmap_raddr + 16'd1;
        end
        if (controller_filter_hs) begin
            controller_filter_raddr <= controller_filter_raddr + 16'd1;
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
    .input_sram_ready_i(input_sram_ready_o)
);

input_sram_reg u_input_sram_reg (
    .clk(clk),
    .rst(rst),
    .wen_i(input_sram_wen_o),
    .waddr_i(input_sram_waddr_o),
    .wdata_i(input_sram_wdata_o),
    .ready_o(input_sram_ready_o),
    .raddr_i(selected_input_sram_raddr),
    .rdata_o(input_sram_rdata_internal)
);

weight_sram_reg u_weight_sram_reg (
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

    .ifmap_0(input_sram_rdata_internal),
    .ifmap_1(input_sram_rdata_internal),
    .ifmap_2(input_sram_rdata_internal),
    .filter(weight_sram_rdata_internal),
    .ipsum(32'd0),

    .ifmap_in_valid(controller_ifmap_in_valid),
    .filter_in_valid(controller_filter_in_valid),
    .ipsum_ready(1'b0),
    .load_ready(1'b1),
    .opsum_valid(1'b0),

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
    .filter_pe_0(controller_filter_pe_0),
    .filter_pe_1(controller_filter_pe_1),
    .filter_pe_2(controller_filter_pe_2),

    .first_col(controller_first_col),
    .last_col(controller_last_col),
    .first_channel(controller_first_channel),
    .last_channel(controller_last_channel),
    .boundary_final(controller_boundary_final),
    .pe_last(controller_pe_last)
);

pe_block_7x3 u_pe_block_7x3 (
    .clk(clk),
    .rst_n(~rst),
    .mode_1x1(pe_input_mode_1x1),
    .ifmap_data(pe_ifmap_selected),
    .weight_data(pe_weight_selected),
    .all_zero_ifmap(),
    .all_zero_weight(),
    .psum_out(pe_psum_out)
);

accumulator #(
    .NUM_LANES(9),
    .DATA_W(32),
    .IDX_W(10)
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
    .first_channel(output_use_controller_i ? 1'b1 : pe_first_channel_hold),
    .last_channel(output_use_controller_i ? 1'b1 : pe_last_channel_hold),

    .boundary_en(acc_boundary_en),
    .output_channel_m(9'd0),
    .ofmap_width_F(pe_ofmap_width_hold),
    .boundary_row(acc_boundary_row),
    .f_idx(acc_boundary_f_idx),

    .ppu_valid(acc_ppu_valid),
    .ppu_ready(acc_ppu_ready),
    .ppu_data(acc_ppu_data),
    .ppu_idx(),
    .ppu_last(acc_ppu_last)
);

PPU u_ppu (
    .clk(clk),
    .rst(rst),

    .in_valid(selected_ppu_in_valid),
    .in_ready(ppu_hw_in_ready),
    .data_in(selected_ppu_in_data),
    .in_last(selected_ppu_in_last),

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
    .token_data_o(output_token_data_o),
    .token_valid_o(output_token_valid_o),
    .token_ready_i(output_token_ready_i),
    .ctrl_busy_o(output_ctrl_busy_o),
    .ctrl_token_fire_o(output_ctrl_token_fire_o),
    .ctrl_done_o(output_ctrl_done_o)
);

endmodule

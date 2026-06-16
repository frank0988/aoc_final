`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// pe_col0_cell
// -----------------------------------------------------------------------------
// Left-most cell in one row.
// If act or weight is zero, the cell is bypassed and outputs zero.
// -----------------------------------------------------------------------------
module pe_col0_cell #(
    parameter integer DATA_W   = 8,
    parameter integer WEIGHT_W = 8,
    parameter integer ACC_W    = 32
) (
    input  wire signed [DATA_W-1:0]   act_in,
    input  wire signed [WEIGHT_W-1:0] weight_in,
    output wire                       cell_valid,
    output wire signed [ACC_W-1:0]    product_out,
    output wire signed [ACC_W-1:0]    pe_out
);

    localparam integer PROD_W = DATA_W + WEIGHT_W;

    wire signed [PROD_W-1:0] product_raw;
    wire signed [DATA_W-1:0] act_gated;
    wire signed [WEIGHT_W-1:0] weight_gated;

    assign cell_valid = (act_in != {DATA_W{1'b0}}) && (weight_in != {WEIGHT_W{1'b0}});
    assign act_gated = cell_valid ? act_in : {DATA_W{1'b0}};
    assign weight_gated = cell_valid ? weight_in : {WEIGHT_W{1'b0}};
    assign product_raw = $signed(act_gated) * $signed(weight_gated);
    assign product_out = {{(ACC_W-PROD_W){product_raw[PROD_W-1]}}, product_raw};
    assign pe_out      = cell_valid ? product_out : {ACC_W{1'b0}};

endmodule

// -----------------------------------------------------------------------------
// pe_add_cell
// -----------------------------------------------------------------------------
// PE add cell used by col1 / col2.
// mode_1x1 = 1: add the same-row partial sum from the left cell
// mode_1x1 = 0: add the diagonal partial sum from the upper-left cell
// If act or weight is zero, bypass the MAC and forward mux_out directly.
// -----------------------------------------------------------------------------
module pe_add_cell #(
    parameter integer DATA_W   = 8,
    parameter integer WEIGHT_W = 8,
    parameter integer ACC_W    = 32
) (
    input  wire                      mode_1x1,
    input  wire signed [DATA_W-1:0]   act_in,
    input  wire signed [WEIGHT_W-1:0] weight_in,
    input  wire signed [ACC_W-1:0]    row_psum_in,
    input  wire signed [ACC_W-1:0]    diag_psum_in,
    output wire                       cell_valid,
    output wire signed [ACC_W-1:0]    mux_out,
    output wire signed [ACC_W-1:0]    product_out,
    output wire signed [ACC_W-1:0]    pe_out
);

    localparam integer PROD_W = DATA_W + WEIGHT_W;

    wire signed [PROD_W-1:0] product_raw;
    wire signed [DATA_W-1:0] act_gated;
    wire signed [WEIGHT_W-1:0] weight_gated;

    assign cell_valid  = (act_in != {DATA_W{1'b0}}) && (weight_in != {WEIGHT_W{1'b0}});
    assign mux_out     = mode_1x1 ? row_psum_in : diag_psum_in;
    assign act_gated   = cell_valid ? act_in : {DATA_W{1'b0}};
    assign weight_gated = cell_valid ? weight_in : {WEIGHT_W{1'b0}};
    assign product_raw = $signed(act_gated) * $signed(weight_gated);
    assign product_out = {{(ACC_W-PROD_W){product_raw[PROD_W-1]}}, product_raw};
    assign pe_out      = cell_valid ? (mux_out + product_out) : mux_out;

endmodule

// -----------------------------------------------------------------------------
// pe_mac_row_1x3
// -----------------------------------------------------------------------------
// One row contains three PE cells:
// - col0: product only
// - col1: mux + adder + product
// - col2: mux + adder + product
//
// 1x1 mode:
//   c0 = a*w0
//   c1 = c0 + a*w1
//   c2 = c1 + a*w2
//
// 3x3 mode:
//   c0 = a*w0
//   c1 = diag_in_col1 + a*w1
//   c2 = diag_in_col2 + a*w2
// -----------------------------------------------------------------------------
module pe_mac_row_1x3 #(
    parameter integer DATA_W   = 8,
    parameter integer WEIGHT_W = 8,
    parameter integer ACC_W    = 32
) (
    input  wire                      mode_1x1,
    input  wire signed [3*DATA_W-1:0]   act_row,
    input  wire signed [3*WEIGHT_W-1:0] weight_row,
    input  wire signed [ACC_W-1:0]      diag_in_col1,
    input  wire signed [ACC_W-1:0]      diag_in_col2,
    output wire [2:0]                   cell_valids,
    output wire signed [3*ACC_W-1:0]    row_products,
    output wire signed [3*ACC_W-1:0]    col_psums,
    output wire signed [ACC_W-1:0]      row_sum
);

    wire signed [DATA_W-1:0]   a0;
    wire signed [DATA_W-1:0]   a1;
    wire signed [DATA_W-1:0]   a2;
    wire signed [WEIGHT_W-1:0] w0;
    wire signed [WEIGHT_W-1:0] w1;
    wire signed [WEIGHT_W-1:0] w2;

    wire signed [ACC_W-1:0]    p0;
    wire signed [ACC_W-1:0]    p1;
    wire signed [ACC_W-1:0]    p2;
    wire signed [ACC_W-1:0]    c0;
    wire signed [ACC_W-1:0]    c1;
    wire signed [ACC_W-1:0]    c2;
    wire signed [ACC_W-1:0]    mux1_out;
    wire signed [ACC_W-1:0]    mux2_out;
    wire                       cell_valid0;
    wire                       cell_valid1;
    wire                       cell_valid2;

    assign a0 = act_row[(0*DATA_W) +: DATA_W];
    assign a1 = act_row[(1*DATA_W) +: DATA_W];
    assign a2 = act_row[(2*DATA_W) +: DATA_W];

    assign w0 = weight_row[(0*WEIGHT_W) +: WEIGHT_W];
    assign w1 = weight_row[(1*WEIGHT_W) +: WEIGHT_W];
    assign w2 = weight_row[(2*WEIGHT_W) +: WEIGHT_W];

    pe_col0_cell #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .ACC_W(ACC_W)
    ) u_pe_add0 (
        .act_in(a0),
        .weight_in(w0),
        .cell_valid(cell_valid0),
        .product_out(p0),
        .pe_out(c0)
    );

    pe_add_cell #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .ACC_W(ACC_W)
    ) u_pe_add1 (
        .mode_1x1(mode_1x1),
        .act_in(a1),
        .weight_in(w1),
        .row_psum_in(c0),
        .diag_psum_in(diag_in_col1),
        .cell_valid(cell_valid1),
        .mux_out(mux1_out),
        .product_out(p1),
        .pe_out(c1)
    );

    pe_add_cell #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .ACC_W(ACC_W)
    ) u_pe_add2 (
        .mode_1x1(mode_1x1),
        .act_in(a2),
        .weight_in(w2),
        .row_psum_in(c1),
        .diag_psum_in(diag_in_col2),
        .cell_valid(cell_valid2),
        .mux_out(mux2_out),
        .product_out(p2),
        .pe_out(c2)
    );

    assign cell_valids[0] = cell_valid0;
    assign cell_valids[1] = cell_valid1;
    assign cell_valids[2] = cell_valid2;
    assign row_products[(0*ACC_W) +: ACC_W] = p0;
    assign row_products[(1*ACC_W) +: ACC_W] = p1;
    assign row_products[(2*ACC_W) +: ACC_W] = p2;

    assign col_psums[(0*ACC_W) +: ACC_W] = c0;
    assign col_psums[(1*ACC_W) +: ACC_W] = c1;
    assign col_psums[(2*ACC_W) +: ACC_W] = c2;

    assign row_sum = c2;

endmodule

// -----------------------------------------------------------------------------
// pe_block_7x3
// -----------------------------------------------------------------------------
// One-bank 7x3 PE block.
//
// Shared input interface:
//   ifmap_data  = 7 x 8-bit => [a0 ... a6]
//   weight_data = 3 x 8-bit => [w0 w1 w2]
//
// Internal simplification used by this project:
//   each row reuses the same scalar across its 3 columns
// -----------------------------------------------------------------------------
module pe_block_7x3 #(
    parameter integer DATA_W   = 8,
    parameter integer WEIGHT_W = 8,
    parameter integer ACC_W    = 32,
    parameter integer PE_ROWS  = 7,
    parameter integer PE_COLS  = 3,
    parameter integer PE_OUTS  = 9
) (
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  mode_1x1,
    input  wire signed [PE_ROWS*DATA_W-1:0]      ifmap_data,
    input  wire signed [PE_COLS*WEIGHT_W-1:0]    weight_data,
    output wire                                  all_zero_ifmap,
    output wire                                  all_zero_weight,
    output wire signed [PE_OUTS*ACC_W-1:0]       psum_out
);

    reg  signed [ACC_W-1:0] psum_reg [0:PE_OUTS-1];
    wire signed [PE_ROWS*PE_COLS*ACC_W-1:0] row_products_flat;
    wire signed [PE_ROWS*PE_COLS*ACC_W-1:0] col_psums_flat;
    wire signed [PE_ROWS*ACC_W-1:0]         row_sum_flat;
    wire [PE_ROWS*PE_COLS-1:0]              cell_valids_flat;
    wire signed [ACC_W-1:0]                 zero_acc;
    wire signed [ACC_W-1:0]                 o0;
    wire signed [ACC_W-1:0]                 o1;
    wire signed [ACC_W-1:0]                 o2;
    wire signed [ACC_W-1:0]                 o3;
    wire signed [ACC_W-1:0]                 o4;
    wire signed [ACC_W-1:0]                 o5;
    wire signed [ACC_W-1:0]                 o6;
    wire signed [ACC_W-1:0]                 o7;
    wire signed [ACC_W-1:0]                 o8;

    integer out_idx;
    genvar g;

    assign zero_acc = {ACC_W{1'b0}};
    assign all_zero_ifmap = (ifmap_data == {PE_ROWS*DATA_W{1'b0}});
    assign all_zero_weight = (weight_data == {PE_COLS*WEIGHT_W{1'b0}});

    generate
        for (g = 0; g < PE_ROWS; g = g + 1) begin : g_row
            wire signed [DATA_W-1:0]     ifmap_elem;
            wire signed [3*DATA_W-1:0]   act_row;
            wire signed [ACC_W-1:0]      diag_in_col1;
            wire signed [ACC_W-1:0]      diag_in_col2;
            wire [2:0]                   cell_valids;
            wire signed [3*ACC_W-1:0]    row_products;
            wire signed [3*ACC_W-1:0]    col_psums;
            wire signed [ACC_W-1:0]      row_sum;

            assign ifmap_elem = ifmap_data[g*DATA_W +: DATA_W];
            assign act_row    = {ifmap_elem, ifmap_elem, ifmap_elem};

            if (g == 0) begin : g_first_row
                assign diag_in_col1 = zero_acc;
                assign diag_in_col2 = zero_acc;
            end else begin : g_other_rows
                assign diag_in_col1 = col_psums_flat[(((g-1)*PE_COLS)+0)*ACC_W +: ACC_W];
                assign diag_in_col2 = col_psums_flat[(((g-1)*PE_COLS)+1)*ACC_W +: ACC_W];
            end

            pe_mac_row_1x3 #(
                .DATA_W(DATA_W),
                .WEIGHT_W(WEIGHT_W),
                .ACC_W(ACC_W)
            ) u_row (
                .mode_1x1(mode_1x1),
                .act_row(act_row),
                .weight_row(weight_data),
                .diag_in_col1(diag_in_col1),
                .diag_in_col2(diag_in_col2),
                .cell_valids(cell_valids),
                .row_products(row_products),
                .col_psums(col_psums),
                .row_sum(row_sum)
            );

            assign cell_valids_flat[g*PE_COLS +: PE_COLS]                 = cell_valids;
            assign row_products_flat[g*PE_COLS*ACC_W +: PE_COLS*ACC_W] = row_products;
            assign col_psums_flat[g*PE_COLS*ACC_W +: PE_COLS*ACC_W]    = col_psums;
            assign row_sum_flat[g*ACC_W +: ACC_W]                      = row_sum;
        end
    endgenerate

    // The col2 PE output is the row result in 1x1 mode,
    // and also the diagonal output o0~o6 in 3x3 mode.
    assign o0 = col_psums_flat[((0*PE_COLS)+2)*ACC_W +: ACC_W];
    assign o1 = col_psums_flat[((1*PE_COLS)+2)*ACC_W +: ACC_W];
    assign o2 = col_psums_flat[((2*PE_COLS)+2)*ACC_W +: ACC_W];
    assign o3 = col_psums_flat[((3*PE_COLS)+2)*ACC_W +: ACC_W];
    assign o4 = col_psums_flat[((4*PE_COLS)+2)*ACC_W +: ACC_W];
    assign o5 = col_psums_flat[((5*PE_COLS)+2)*ACC_W +: ACC_W];
    assign o6 = col_psums_flat[((6*PE_COLS)+2)*ACC_W +: ACC_W];
    assign o7 = mode_1x1 ? zero_acc : col_psums_flat[((6*PE_COLS)+1)*ACC_W +: ACC_W];
    assign o8 = mode_1x1 ? zero_acc : col_psums_flat[((6*PE_COLS)+0)*ACC_W +: ACC_W];

    assign psum_out[(0*ACC_W) +: ACC_W] = psum_reg[0];
    assign psum_out[(1*ACC_W) +: ACC_W] = psum_reg[1];
    assign psum_out[(2*ACC_W) +: ACC_W] = psum_reg[2];
    assign psum_out[(3*ACC_W) +: ACC_W] = psum_reg[3];
    assign psum_out[(4*ACC_W) +: ACC_W] = psum_reg[4];
    assign psum_out[(5*ACC_W) +: ACC_W] = psum_reg[5];
    assign psum_out[(6*ACC_W) +: ACC_W] = psum_reg[6];
    assign psum_out[(7*ACC_W) +: ACC_W] = psum_reg[7];
    assign psum_out[(8*ACC_W) +: ACC_W] = psum_reg[8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (out_idx = 0; out_idx < PE_OUTS; out_idx = out_idx + 1) begin
                psum_reg[out_idx] <= {ACC_W{1'b0}};
            end
        end else begin
            psum_reg[0] <= o0;
            psum_reg[1] <= o1;
            psum_reg[2] <= o2;
            psum_reg[3] <= o3;
            psum_reg[4] <= o4;
            psum_reg[5] <= o5;
            psum_reg[6] <= o6;
            psum_reg[7] <= o7;
            psum_reg[8] <= o8;
        end
    end

endmodule

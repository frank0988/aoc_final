`timescale 1ns/1ps
`define MAX 100000
`include "../Src/pe_block_7x3.v"

// VCS example:
//   vcs -full64 -sverilog -debug_access+all +define+FSDB pe_block_7x3_tb.sv
//   ./simv

module pe_block_7x3_tb;

  parameter DATA_W   = 8;
  parameter WEIGHT_W = 8;
  parameter ACC_W    = 32;
  parameter PE_ROWS  = 7;
  parameter PE_COLS  = 3;
  parameter PE_OUTS  = 9;

  logic clk;
  logic rst_n;
  logic mode_1x1;
  logic signed [PE_ROWS*DATA_W-1:0]           ifmap_data;
  logic signed [PE_COLS*WEIGHT_W-1:0]         weight_data;
  logic all_zero_ifmap;
  logic all_zero_weight;
  logic signed [PE_OUTS*ACC_W-1:0]            psum_out;

  integer error_count;
  integer total_count;

  integer ifmap_vals [0:PE_ROWS-1];
  integer weights        [0:PE_COLS-1];
  integer expected       [0:PE_OUTS-1];

  integer got;
  integer r;
  integer c;

  pe_block_7x3 #(
    .DATA_W(DATA_W),
    .WEIGHT_W(WEIGHT_W),
    .ACC_W(ACC_W),
    .PE_ROWS(PE_ROWS),
    .PE_COLS(PE_COLS),
    .PE_OUTS(PE_OUTS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .mode_1x1(mode_1x1),
    .ifmap_data(ifmap_data),
    .weight_data(weight_data),
    .all_zero_ifmap(all_zero_ifmap),
    .all_zero_weight(all_zero_weight),
    .psum_out(psum_out)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task clear_bus;
    begin
      mode_1x1        = 1'b0;
      ifmap_data      = '0;
      weight_data     = '0;
    end
  endtask

  task pack_bus;
    begin
      ifmap_data   = '0;
      weight_data  = '0;

      for (r = 0; r < PE_ROWS; r = r + 1) begin
        ifmap_data[r*DATA_W +: DATA_W] = ifmap_vals[r];
      end

      for (c = 0; c < PE_COLS; c = c + 1) begin
        weight_data[c*WEIGHT_W +: WEIGHT_W] = weights[c];
      end
    end
  endtask

  task check_outputs;
    input [255:0] case_name;
    input expected_all_zero_ifmap;
    input expected_all_zero_weight;
    begin
      total_count = total_count + 1;
      if (all_zero_ifmap !== expected_all_zero_ifmap) begin
        $display("[FAIL] %0s all_zero_ifmap expected=%0d got=%0d", case_name, expected_all_zero_ifmap, all_zero_ifmap);
        error_count = error_count + 1;
      end

      if (all_zero_weight !== expected_all_zero_weight) begin
        $display("[FAIL] %0s all_zero_weight expected=%0d got=%0d", case_name, expected_all_zero_weight, all_zero_weight);
        error_count = error_count + 1;
      end

      for (r = 0; r < PE_OUTS; r = r + 1) begin
        got = $signed(psum_out[r*ACC_W +: ACC_W]);
        if (got !== expected[r]) begin
          $display("[FAIL] %0s o%0d expected=%0d got=%0d", case_name, r, expected[r], got);
          error_count = error_count + 1;
        end
      end
    end
  endtask

  task run_one_cycle;
    input [255:0] case_name;
    input mode_sel;
    input expected_all_zero_ifmap;
    input expected_all_zero_weight;
    begin
      @(posedge clk);
      #1;
      mode_1x1 = mode_sel;
      pack_bus;

      @(posedge clk);
      #1;
      check_outputs(case_name, expected_all_zero_ifmap, expected_all_zero_weight);
    end
  endtask

  task build_case3x3_0;
    begin
      ifmap_vals[0] =  2;
      ifmap_vals[1] = -1;
      ifmap_vals[2] =  4;
      ifmap_vals[3] =  0;
      ifmap_vals[4] =  3;
      ifmap_vals[5] =  1;
      ifmap_vals[6] = -2;

      weights[0] =  1;
      weights[1] = -2;
      weights[2] =  3;

      expected[0] = (ifmap_vals[0] * weights[2]);
      expected[1] = (ifmap_vals[0] * weights[1]) + (ifmap_vals[1] * weights[2]);
      expected[2] = (ifmap_vals[0] * weights[0]) + (ifmap_vals[1] * weights[1]) + (ifmap_vals[2] * weights[2]);
      expected[3] = (ifmap_vals[1] * weights[0]) + (ifmap_vals[2] * weights[1]) + (ifmap_vals[3] * weights[2]);
      expected[4] = (ifmap_vals[2] * weights[0]) + (ifmap_vals[3] * weights[1]) + (ifmap_vals[4] * weights[2]);
      expected[5] = (ifmap_vals[3] * weights[0]) + (ifmap_vals[4] * weights[1]) + (ifmap_vals[5] * weights[2]);
      expected[6] = (ifmap_vals[4] * weights[0]) + (ifmap_vals[5] * weights[1]) + (ifmap_vals[6] * weights[2]);
      expected[7] = (ifmap_vals[5] * weights[0]) + (ifmap_vals[6] * weights[1]);
      expected[8] = (ifmap_vals[6] * weights[0]);
    end
  endtask

  task build_case3x3_1;
    begin
      ifmap_vals[0] = -3;
      ifmap_vals[1] =  5;
      ifmap_vals[2] =  1;
      ifmap_vals[3] = -2;
      ifmap_vals[4] =  4;
      ifmap_vals[5] =  0;
      ifmap_vals[6] =  6;

      weights[0] =  2;
      weights[1] =  1;
      weights[2] = -1;

      expected[0] = (ifmap_vals[0] * weights[2]);
      expected[1] = (ifmap_vals[0] * weights[1]) + (ifmap_vals[1] * weights[2]);
      expected[2] = (ifmap_vals[0] * weights[0]) + (ifmap_vals[1] * weights[1]) + (ifmap_vals[2] * weights[2]);
      expected[3] = (ifmap_vals[1] * weights[0]) + (ifmap_vals[2] * weights[1]) + (ifmap_vals[3] * weights[2]);
      expected[4] = (ifmap_vals[2] * weights[0]) + (ifmap_vals[3] * weights[1]) + (ifmap_vals[4] * weights[2]);
      expected[5] = (ifmap_vals[3] * weights[0]) + (ifmap_vals[4] * weights[1]) + (ifmap_vals[5] * weights[2]);
      expected[6] = (ifmap_vals[4] * weights[0]) + (ifmap_vals[5] * weights[1]) + (ifmap_vals[6] * weights[2]);
      expected[7] = (ifmap_vals[5] * weights[0]) + (ifmap_vals[6] * weights[1]);
      expected[8] = (ifmap_vals[6] * weights[0]);
    end
  endtask

  task build_case1x1_0;
    begin
      weights[0] =  2;
      weights[1] = -1;
      weights[2] =  3;

      // First 1x1 case uses the same row value replicated across the 3 columns:
      // row0 = [2, 2, 2], row1 = [-1, -1, -1], ...
      ifmap_vals[0] =  2;
      ifmap_vals[1] = -1;
      ifmap_vals[2] =  4;
      ifmap_vals[3] =  0;
      ifmap_vals[4] =  3;
      ifmap_vals[5] =  1;
      ifmap_vals[6] = -2;

      expected[0] = ifmap_vals[0] * (weights[0] + weights[1] + weights[2]);
      expected[1] = ifmap_vals[1] * (weights[0] + weights[1] + weights[2]);
      expected[2] = ifmap_vals[2] * (weights[0] + weights[1] + weights[2]);
      expected[3] = ifmap_vals[3] * (weights[0] + weights[1] + weights[2]);
      expected[4] = ifmap_vals[4] * (weights[0] + weights[1] + weights[2]);
      expected[5] = ifmap_vals[5] * (weights[0] + weights[1] + weights[2]);
      expected[6] = ifmap_vals[6] * (weights[0] + weights[1] + weights[2]);
      expected[7] = 0;
      expected[8] = 0;
    end
  endtask

  task build_case1x1_1;
    begin
      weights[0] = -2;
      weights[1] =  4;
      weights[2] =  1;

      // Second 1x1 case follows the same 56-bit input model as case0:
      // one scalar per row, then the PE block replicates it across 3 columns.
      // row0 = [7, 7, 7], row1 = [6, 6, 6], ...
      ifmap_vals[0] =  7;
      ifmap_vals[1] =  6;
      ifmap_vals[2] =  5;
      ifmap_vals[3] =  4;
      ifmap_vals[4] =  3;
      ifmap_vals[5] =  2;
      ifmap_vals[6] =  1;

      expected[0] = ifmap_vals[0] * (weights[0] + weights[1] + weights[2]);
      expected[1] = ifmap_vals[1] * (weights[0] + weights[1] + weights[2]);
      expected[2] = ifmap_vals[2] * (weights[0] + weights[1] + weights[2]);
      expected[3] = ifmap_vals[3] * (weights[0] + weights[1] + weights[2]);
      expected[4] = ifmap_vals[4] * (weights[0] + weights[1] + weights[2]);
      expected[5] = ifmap_vals[5] * (weights[0] + weights[1] + weights[2]);
      expected[6] = ifmap_vals[6] * (weights[0] + weights[1] + weights[2]);
      expected[7] = 0;
      expected[8] = 0;
    end
  endtask

  task build_sparse_zero_ifmap;
    begin
      ifmap_vals[0] = 0;
      ifmap_vals[1] = 0;
      ifmap_vals[2] = 0;
      ifmap_vals[3] = 0;
      ifmap_vals[4] = 0;
      ifmap_vals[5] = 0;
      ifmap_vals[6] = 0;

      weights[0] =  3;
      weights[1] = -1;
      weights[2] =  2;

      for (r = 0; r < PE_OUTS; r = r + 1) begin
        expected[r] = 0;
      end
    end
  endtask

  task build_sparse_zero_weight;
    begin
      ifmap_vals[0] =  7;
      ifmap_vals[1] =  6;
      ifmap_vals[2] =  5;
      ifmap_vals[3] =  4;
      ifmap_vals[4] =  3;
      ifmap_vals[5] =  2;
      ifmap_vals[6] =  1;

      weights[0] = 0;
      weights[1] = 0;
      weights[2] = 0;

      for (r = 0; r < PE_OUTS; r = r + 1) begin
        expected[r] = 0;
      end
    end
  endtask

  task build_sparse_bypass_3x3;
    begin
      ifmap_vals[0] =  2;
      ifmap_vals[1] =  0;
      ifmap_vals[2] =  4;
      ifmap_vals[3] =  5;
      ifmap_vals[4] =  0;
      ifmap_vals[5] =  1;
      ifmap_vals[6] = -2;

      weights[0] =  1;
      weights[1] =  0;
      weights[2] =  3;

      expected[0] = (ifmap_vals[0] * weights[2]);
      expected[1] = (ifmap_vals[0] * weights[1]) + (ifmap_vals[1] * weights[2]);
      expected[2] = (ifmap_vals[0] * weights[0]) + (ifmap_vals[1] * weights[1]) + (ifmap_vals[2] * weights[2]);
      expected[3] = (ifmap_vals[1] * weights[0]) + (ifmap_vals[2] * weights[1]) + (ifmap_vals[3] * weights[2]);
      expected[4] = (ifmap_vals[2] * weights[0]) + (ifmap_vals[3] * weights[1]) + (ifmap_vals[4] * weights[2]);
      expected[5] = (ifmap_vals[3] * weights[0]) + (ifmap_vals[4] * weights[1]) + (ifmap_vals[5] * weights[2]);
      expected[6] = (ifmap_vals[4] * weights[0]) + (ifmap_vals[5] * weights[1]) + (ifmap_vals[6] * weights[2]);
      expected[7] = (ifmap_vals[5] * weights[0]) + (ifmap_vals[6] * weights[1]);
      expected[8] = (ifmap_vals[6] * weights[0]);
    end
  endtask

  task build_sparse_bypass_1x1;
    begin
      ifmap_vals[0] =  2;
      ifmap_vals[1] = -1;
      ifmap_vals[2] =  4;
      ifmap_vals[3] =  0;
      ifmap_vals[4] =  3;
      ifmap_vals[5] =  1;
      ifmap_vals[6] = -2;

      weights[0] =  2;
      weights[1] =  0;
      weights[2] =  3;

      expected[0] = ifmap_vals[0] * (weights[0] + weights[2]);
      expected[1] = ifmap_vals[1] * (weights[0] + weights[2]);
      expected[2] = ifmap_vals[2] * (weights[0] + weights[2]);
      expected[3] = 0;
      expected[4] = ifmap_vals[4] * (weights[0] + weights[2]);
      expected[5] = ifmap_vals[5] * (weights[0] + weights[2]);
      expected[6] = ifmap_vals[6] * (weights[0] + weights[2]);
      expected[7] = 0;
      expected[8] = 0;
    end
  endtask

  task clear_vectors;
    begin
      for (r = 0; r < PE_ROWS; r = r + 1) begin
        ifmap_vals[r] = 0;
      end

      for (c = 0; c < PE_COLS; c = c + 1) begin
        weights[c] = 0;
      end

      for (r = 0; r < PE_OUTS; r = r + 1) begin
        expected[r] = 0;
      end
    end
  endtask

  initial begin
    rst_n       = 1'b0;
    error_count = 0;
    total_count = 0;
    clear_bus;
    clear_vectors;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    @(posedge clk);
    #1;
    for (r = 0; r < PE_OUTS; r = r + 1) begin
      got = $signed(psum_out[r*ACC_W +: ACC_W]);
      if (got !== 0) begin
        $display("[FAIL] reset o%0d expected=0 got=%0d", r, got);
        error_count = error_count + 1;
      end
    end

    clear_vectors;
    build_case3x3_0;
    run_one_cycle("3x3_stride1_case0", 1'b0, 1'b0, 1'b0);

    clear_vectors;
    build_case3x3_1;
    run_one_cycle("3x3_stride1_case1", 1'b0, 1'b0, 1'b0);

    clear_vectors;
    build_case1x1_0;
    run_one_cycle("1x1_row_sum_case0", 1'b1, 1'b0, 1'b0);

    clear_vectors;
    build_case1x1_1;
    run_one_cycle("1x1_row_sum_case1", 1'b1, 1'b0, 1'b0);

    clear_vectors;
    build_sparse_zero_ifmap;
    run_one_cycle("sparse_zero_ifmap_3x3_case", 1'b0, 1'b1, 1'b0);

    clear_vectors;
    build_sparse_zero_ifmap;
    run_one_cycle("sparse_zero_ifmap_1x1_case", 1'b1, 1'b1, 1'b0);

    clear_vectors;
    build_sparse_zero_weight;
    run_one_cycle("sparse_zero_weight_3x3_case", 1'b0, 1'b0, 1'b1);

    clear_vectors;
    build_sparse_zero_weight;
    run_one_cycle("sparse_zero_weight_1x1_case", 1'b1, 1'b0, 1'b1);

    clear_vectors;
    build_sparse_bypass_3x3;
    run_one_cycle("sparse_bypass_3x3_case", 1'b0, 1'b0, 1'b0);

    clear_vectors;
    build_sparse_bypass_1x1;
    run_one_cycle("sparse_bypass_1x1_case", 1'b1, 1'b0, 1'b0);

    #(10);
    $display("TOTAL=%0d FAIL=%0d", total_count, error_count);

    if (error_count != 0) begin
      $display("FAIL: pe_block_7x3_tb");
    end else begin
      $display("PASS: pe_block_7x3_tb");
    end

    $finish;
  end

  initial begin
    `ifdef FSDB
      $fsdbDumpfile("pe_block_7x3.fsdb");
      $fsdbDumpvars(0, pe_block_7x3_tb, "+all");
    `elsif VCD
      $dumpfile("pe_block_7x3.vcd");
      $dumpvars(0, pe_block_7x3_tb);
    `endif
  end

endmodule

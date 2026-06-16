`timescale 1ns/1ps

module tb;
    import rlc_encode_pkg::*;
    import rlc_decode_pkg::*;
    import weight_tb_pkg::*;

    localparam int MAX_VALUES = 8192;
    localparam int MAX_VECS   = 2048;
    localparam int MAX_TOKENS = 4096;

    typedef logic [23:0] filter_beat_t;

    logic [7:0] input_zero_lane;
    logic [7:0] weight_zero_lane;
    logic [7:0] output_zero_lane;

    int input_zero_lane_arg;
    int weight_zero_lane_arg;
    int output_zero_lane_arg;
    int process_golden_psum_arg;
    int scaling_factor_arg;
    int relu_en_arg;
    int maxpool_en_arg;
    int full_hw_path_arg;
    int full_hw_packet_limit_arg;
    int stream_hw_path_arg;
    int stream_input_scalars_arg;

    bit process_golden_psum;
    int scaling_factor;
    bit relu_en;
    bit maxpool_en;
    bit full_hw_path;
    int full_hw_packet_limit;
    bit stream_hw_path;
    int stream_input_scalars;

    string ifmap_file;
    string weight_file;
    string golden_file;
    string trace_file;
    string stream_hw_out_file;

    int ifmap_values  [0:MAX_VALUES-1];
    int weight_values [0:MAX_VALUES-1];
    int golden_values [0:MAX_VALUES-1];
    int golden_ppu_values [0:MAX_VALUES-1];

    int ifmap_count;
    int weight_count;
    int golden_count;
    int golden_ppu_count;

    rlc_vec_t ifmap_vecs       [0:MAX_VECS-1];
    rlc_vec_t ifmap_roundtrip  [0:MAX_VECS-1];
    filter_beat_t weight_filter_beats [0:MAX_VALUES-1];
    rlc_vec_t golden_vecs      [0:MAX_VECS-1];
    rlc_vec_t golden_roundtrip [0:MAX_VECS-1];

    rlc_token_t ifmap_tokens  [0:MAX_TOKENS-1];
    rlc_token_t golden_tokens [0:MAX_TOKENS-1];

    int ifmap_vec_count;
    int ifmap_roundtrip_count;
    int weight_filter_beat_count;
    int golden_vec_count;
    int golden_roundtrip_count;
    int ifmap_token_count;
    int golden_token_count;

    bit pass;

    logic clk = 1'b0;
    logic rst = 1'b1;

    rlc_token_t dec_token_data_i = '0;
    logic dec_token_valid_i = 1'b0;
    logic dec_token_ready_o;
    logic dec_ctrl_valid_o;
    logic dec_ctrl_ready_i = 1'b1;
    logic [15:0] dec_ctrl_run_o;
    logic [15:0] dec_ctrl_dense_index_o;
    logic dec_ctrl_vec_nonzero_o;
    logic dec_ctrl_last_o;
    logic dec_ctrl_done_o;
    logic dec_sram_wen_o;
    logic [15:0] dec_sram_waddr_o;
    rlc_vec_t dec_sram_wdata_o;
    logic dec_sram_ready_i;
    logic [15:0] dec_sram_raddr_i = 16'd0;
    rlc_vec_t dec_sram_rdata_o;

    logic weight_sram_wen_i = 1'b0;
    logic [15:0] weight_sram_waddr_i = 16'd0;
    filter_beat_t weight_sram_wdata_i = '0;
    logic weight_sram_ready_o;
    logic [15:0] weight_sram_raddr_i = 16'd0;
    filter_beat_t weight_sram_rdata_o;

    rlc_vec_t enc_ppu_data_i = '0;
    logic enc_ppu_valid_i = 1'b0;
    logic enc_ppu_last_i = 1'b0;
    logic enc_ppu_ready_o;

    logic output_use_hw_ppu_i = 1'b0;
    logic signed [31:0] ppu_scalar_data_i = '0;
    logic ppu_scalar_valid_i = 1'b0;
    logic ppu_scalar_last_i = 1'b0;
    logic ppu_scalar_ready_o;
    logic [5:0] ppu_scaling_factor_i = 6'd0;
    logic ppu_relu_en_i = 1'b1;
    logic ppu_maxpool_en_i = 1'b0;
    logic ppu_maxpool_init_i = 1'b0;
    logic ppu_maxpool_emit_i = 1'b0;

    logic output_use_pe_accum_i = 1'b0;
    logic pe_accum_valid_i = 1'b0;
    logic pe_accum_ready_o;
    logic pe_mode_1x1_i = 1'b0;
    rlc_vec_t pe_ifmap_data_i = '0;
    filter_beat_t pe_weight_data_i = '0;
    logic pe_accum_last_i = 1'b0;
    logic [9:0] pe_accum_base_idx_i = 10'd0;

    logic output_use_controller_i = 1'b0;
    logic [29:0] controller_config_i = '0;
    logic [15:0] controller_ifmap_base_addr_i = 16'd0;
    logic [15:0] controller_filter_base_addr_i = 16'd0;
    logic [15:0] controller_capture_limit_i = 16'd0;
    logic controller_pe_fire_o;
    rlc_vec_t controller_pe_ifmap_o;
    filter_beat_t controller_pe_weight_o;

    rlc_token_t enc_token_data_o;
    logic enc_token_valid_o;
    logic enc_token_ready_i = 1'b1;
    logic enc_ctrl_busy_o;
    logic enc_ctrl_token_fire_o;
    logic enc_ctrl_done_o;

    rlc_token_t hw_golden_tokens [0:MAX_TOKENS-1];
    int hw_golden_token_count;

    rlc_vec_t pe_hw_expected_vecs [0:MAX_VECS-1];
    rlc_token_t pe_hw_expected_tokens [0:MAX_TOKENS-1];
    int pe_hw_expected_vec_count;
    int pe_hw_expected_token_count;

    rlc_vec_t hw_output_roundtrip [0:MAX_VECS-1];
    int hw_output_roundtrip_count;

    int dec_event_count;
    int dec_nonzero_event_count;
    int dec_zero_event_count;
    int dec_last_event_count;

    top u_top (
        .clk(clk),
        .rst(rst),

        .input_token_data_i(dec_token_data_i),
        .input_token_valid_i(dec_token_valid_i),
        .input_token_ready_o(dec_token_ready_o),

        .input_ctrl_valid_o(dec_ctrl_valid_o),
        .input_ctrl_ready_i(dec_ctrl_ready_i),
        .input_ctrl_run_o(dec_ctrl_run_o),
        .input_ctrl_dense_index_o(dec_ctrl_dense_index_o),
        .input_ctrl_vec_nonzero_o(dec_ctrl_vec_nonzero_o),
        .input_ctrl_last_o(dec_ctrl_last_o),
        .input_ctrl_done_o(dec_ctrl_done_o),

        .input_sram_wen_o(dec_sram_wen_o),
        .input_sram_waddr_o(dec_sram_waddr_o),
        .input_sram_wdata_o(dec_sram_wdata_o),
        .input_sram_ready_o(dec_sram_ready_i),
        .input_sram_raddr_i(dec_sram_raddr_i),
        .input_sram_rdata_o(dec_sram_rdata_o),

        .weight_sram_wen_i(weight_sram_wen_i),
        .weight_sram_waddr_i(weight_sram_waddr_i),
        .weight_sram_wdata_i(weight_sram_wdata_i),
        .weight_sram_ready_o(weight_sram_ready_o),
        .weight_sram_raddr_i(weight_sram_raddr_i),
        .weight_sram_rdata_o(weight_sram_rdata_o),

        .ppu_data_i(enc_ppu_data_i),
        .ppu_valid_i(enc_ppu_valid_i),
        .ppu_last_i(enc_ppu_last_i),
        .ppu_ready_o(enc_ppu_ready_o),

        .output_use_hw_ppu_i(output_use_hw_ppu_i),
        .ppu_scalar_data_i(ppu_scalar_data_i),
        .ppu_scalar_valid_i(ppu_scalar_valid_i),
        .ppu_scalar_last_i(ppu_scalar_last_i),
        .ppu_scalar_ready_o(ppu_scalar_ready_o),
        .ppu_scaling_factor_i(ppu_scaling_factor_i),
        .ppu_relu_en_i(ppu_relu_en_i),
        .ppu_maxpool_en_i(ppu_maxpool_en_i),
        .ppu_maxpool_init_i(ppu_maxpool_init_i),
        .ppu_maxpool_emit_i(ppu_maxpool_emit_i),

        .output_use_pe_accum_i(output_use_pe_accum_i),
        .pe_accum_valid_i(pe_accum_valid_i),
        .pe_accum_ready_o(pe_accum_ready_o),
        .pe_mode_1x1_i(pe_mode_1x1_i),
        .pe_ifmap_data_i(pe_ifmap_data_i),
        .pe_weight_data_i(pe_weight_data_i),
        .pe_accum_last_i(pe_accum_last_i),
        .pe_accum_base_idx_i(pe_accum_base_idx_i),

        .output_use_controller_i(output_use_controller_i),
        .controller_config_i(controller_config_i),
        .controller_ifmap_base_addr_i(controller_ifmap_base_addr_i),
        .controller_filter_base_addr_i(controller_filter_base_addr_i),
        .controller_capture_limit_i(controller_capture_limit_i),
        .controller_pe_fire_o(controller_pe_fire_o),
        .controller_pe_ifmap_o(controller_pe_ifmap_o),
        .controller_pe_weight_o(controller_pe_weight_o),

        .output_token_data_o(enc_token_data_o),
        .output_token_valid_o(enc_token_valid_o),
        .output_token_ready_i(enc_token_ready_i),

        .output_ctrl_busy_o(enc_ctrl_busy_o),
        .output_ctrl_token_fire_o(enc_ctrl_token_fire_o),
        .output_ctrl_done_o(enc_ctrl_done_o)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst && enc_token_valid_o && enc_token_ready_i) begin
            if (hw_golden_token_count >= MAX_TOKENS) begin
                $fatal(1, "[tb] output_RLC_encoder exceeds MAX_TOKENS=%0d", MAX_TOKENS);
            end
            hw_golden_tokens[hw_golden_token_count] = enc_token_data_o;
            hw_golden_token_count++;
        end
    end

    always @(posedge clk) begin
        if (!rst && dec_ctrl_valid_o && dec_ctrl_ready_i) begin
            $display("[tb] input_RLC_decoder event[%0d]: run=%0d dense_index=%0d nonzero=%0b last=%0b sram_wen=%0b sram_waddr=%0d sram_wdata=0x%014h",
                     dec_event_count, dec_ctrl_run_o, dec_ctrl_dense_index_o,
                     dec_ctrl_vec_nonzero_o, dec_ctrl_last_o,
                     dec_sram_wen_o, dec_sram_waddr_o, dec_sram_wdata_o);
            dec_event_count++;
            if (dec_ctrl_vec_nonzero_o) begin
                dec_nonzero_event_count++;
            end else begin
                dec_zero_event_count++;
            end
            if (dec_ctrl_last_o) begin
                dec_last_event_count++;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && controller_pe_fire_o) begin
            $display("[tb] Controller->PE fire: pe_ifmap=0x%014h pe_weight=0x%06h",
                     controller_pe_ifmap_o, controller_pe_weight_o);
        end
    end

    initial begin
`ifdef TRACE_ON
        if ($value$plusargs("TRACE_FILE=%s", trace_file)) begin
            $dumpfile(trace_file);
            $dumpvars(0, tb);
            $display("[tb] TRACE_FILE      = %s", trace_file);
        end
`endif
        pass = 1'b1;
        input_zero_lane = 8'd0;
        weight_zero_lane = 8'd0;
        output_zero_lane = 8'd0;
        process_golden_psum = 1'b0;
        scaling_factor = 0;
        relu_en = 1'b1;
        maxpool_en = 1'b0;
        full_hw_path = 1'b0;
        full_hw_packet_limit = 8;
        stream_hw_path = 1'b0;
        stream_input_scalars = 490;

        if ($value$plusargs("INPUT_ZERO_LANE=%d", input_zero_lane_arg)) begin
            check_zero_lane_arg("INPUT_ZERO_LANE", input_zero_lane_arg);
            input_zero_lane = input_zero_lane_arg[7:0];
        end
        if ($value$plusargs("WEIGHT_ZERO_LANE=%d", weight_zero_lane_arg)) begin
            check_zero_lane_arg("WEIGHT_ZERO_LANE", weight_zero_lane_arg);
            weight_zero_lane = weight_zero_lane_arg[7:0];
        end
        if ($value$plusargs("OUTPUT_ZERO_LANE=%d", output_zero_lane_arg)) begin
            check_zero_lane_arg("OUTPUT_ZERO_LANE", output_zero_lane_arg);
            output_zero_lane = output_zero_lane_arg[7:0];
        end
        if ($value$plusargs("PROCESS_GOLDEN_PSUM=%d", process_golden_psum_arg)) begin
            process_golden_psum = process_golden_psum_arg != 0;
        end
        if ($value$plusargs("SCALING_FACTOR=%d", scaling_factor_arg)) begin
            if (scaling_factor_arg < 0 || scaling_factor_arg > 31) begin
                $fatal(1, "[tb] SCALING_FACTOR=%0d is outside 0..31", scaling_factor_arg);
            end
            scaling_factor = scaling_factor_arg;
        end
        if ($value$plusargs("RELU_EN=%d", relu_en_arg)) begin
            relu_en = relu_en_arg != 0;
        end
        if ($value$plusargs("MAXPOOL_EN=%d", maxpool_en_arg)) begin
            maxpool_en = maxpool_en_arg != 0;
        end
        if ($value$plusargs("FULL_HW_PATH=%d", full_hw_path_arg)) begin
            full_hw_path = full_hw_path_arg != 0;
        end
        if ($value$plusargs("STREAM_HW_PATH=%d", stream_hw_path_arg)) begin
            stream_hw_path = stream_hw_path_arg != 0;
        end
        if ($value$plusargs("STREAM_INPUT_SCALARS=%d", stream_input_scalars_arg)) begin
            if (stream_input_scalars_arg <= 0 || stream_input_scalars_arg > MAX_VALUES) begin
                $fatal(1, "[tb] STREAM_INPUT_SCALARS=%0d is outside 1..%0d",
                       stream_input_scalars_arg, MAX_VALUES);
            end
            stream_input_scalars = stream_input_scalars_arg;
        end
        if ($value$plusargs("FULL_HW_PACKET_LIMIT=%d", full_hw_packet_limit_arg)) begin
            if (full_hw_packet_limit_arg <= 0 || full_hw_packet_limit_arg > 256) begin
                $fatal(1, "[tb] FULL_HW_PACKET_LIMIT=%0d is outside 1..256", full_hw_packet_limit_arg);
            end
            full_hw_packet_limit = full_hw_packet_limit_arg;
        end
        if (!$value$plusargs("IFMAP_FILE=%s", ifmap_file)) begin
            ifmap_file = "test_data/PE_test_data/tb0/ifmap_tb0.txt";
        end
        if (!$value$plusargs("WEIGHT_FILE=%s", weight_file)) begin
            weight_file = "test_data/PE_test_data/tb0/filter_tb0.txt";
        end
        if (!$value$plusargs("GOLDEN_FILE=%s", golden_file)) begin
            golden_file = "test_data/PE_test_data/tb0/ofmap_tb0.txt";
        end
        if (!$value$plusargs("STREAM_HW_OUT_FILE=%s", stream_hw_out_file)) begin
            stream_hw_out_file = "waves/stream_hw_vectors.txt";
        end

        $display("[tb] IFMAP_FILE       = %s", ifmap_file);
        $display("[tb] WEIGHT_FILE      = %s", weight_file);
        $display("[tb] GOLDEN_FILE      = %s", golden_file);
        $display("[tb] INPUT_ZERO_LANE  = %0d", input_zero_lane);
        $display("[tb] WEIGHT_ZERO_LANE = %0d", weight_zero_lane);
        $display("[tb] OUTPUT_ZERO_LANE = %0d", output_zero_lane);
        $display("[tb] PROCESS_GOLDEN_PSUM = %0d", process_golden_psum);
        $display("[tb] FULL_HW_PATH   = %0d", full_hw_path);
        $display("[tb] STREAM_HW_PATH = %0d", stream_hw_path);
        if (full_hw_path) begin
            $display("[tb] FULL_HW_PACKET_LIMIT = %0d", full_hw_packet_limit);
        end
        if (stream_hw_path) begin
            $display("[tb] STREAM_INPUT_SCALARS = %0d", stream_input_scalars);
            $display("[tb] STREAM_HW_OUT_FILE = %s", stream_hw_out_file);
        end
        if (process_golden_psum) begin
            $display("[tb] PPU reference: scaling_factor=%0d relu_en=%0d maxpool_en=%0d",
                     scaling_factor, relu_en, maxpool_en);
        end

        load_csv_i32(ifmap_file, ifmap_values, ifmap_count);
        load_csv_i32(weight_file, weight_values, weight_count);
        load_csv_i32(golden_file, golden_values, golden_count);

        pack_values_to_vecs("ifmap", ifmap_values, ifmap_count, input_zero_lane,
                            ifmap_vecs, ifmap_vec_count);
        pack_weight_values_to_filter_beats("weight", weight_values, weight_count, weight_zero_lane,
                                           weight_filter_beats, weight_filter_beat_count);
        if (process_golden_psum) begin
            process_psum_with_ppu_ref(golden_values, golden_count, scaling_factor, relu_en, maxpool_en,
                                      golden_ppu_values, golden_ppu_count);
            pack_values_to_vecs("golden_ppu", golden_ppu_values, golden_ppu_count, output_zero_lane,
                                golden_vecs, golden_vec_count);
        end else begin
            golden_ppu_count = golden_count;
            pack_values_to_vecs("golden", golden_values, golden_count, output_zero_lane,
                                golden_vecs, golden_vec_count);
        end

        compress_vecs("ifmap", ifmap_vecs, ifmap_vec_count, rlc_zero_vec(input_zero_lane),
                      ifmap_tokens, ifmap_token_count);
        decompress_tokens("ifmap", ifmap_tokens, ifmap_token_count, rlc_zero_vec(input_zero_lane),
                          ifmap_roundtrip, ifmap_roundtrip_count);
        pass &= compare_vecs("ifmap roundtrip", ifmap_vecs, ifmap_vec_count,
                             ifmap_roundtrip, ifmap_roundtrip_count);

        compress_vecs("golden", golden_vecs, golden_vec_count, rlc_zero_vec(output_zero_lane),
                      golden_tokens, golden_token_count);
        decompress_tokens("golden", golden_tokens, golden_token_count, rlc_zero_vec(output_zero_lane),
                          golden_roundtrip, golden_roundtrip_count);
        pass &= compare_vecs("golden roundtrip", golden_vecs, golden_vec_count,
                             golden_roundtrip, golden_roundtrip_count);

        $display("[tb] ifmap scalar count  = %0d", ifmap_count);
        $display("[tb] ifmap vector count  = %0d", ifmap_vec_count);
        $display("[tb] ifmap token count   = %0d", ifmap_token_count);
        print_tokens("ifmap", ifmap_tokens, ifmap_token_count, 8);

        $display("[tb] weight scalar count = %0d", weight_count);
        $display("[tb] weight filter beat count = %0d (3x8 raw, not compressed)", weight_filter_beat_count);

        $display("[tb] golden scalar count = %0d", golden_count);
        if (process_golden_psum) begin
            $display("[tb] golden PPU scalar count = %0d", golden_ppu_count);
        end
        $display("[tb] golden vector count = %0d", golden_vec_count);
        $display("[tb] golden token count  = %0d", golden_token_count);
        print_tokens("golden", golden_tokens, golden_token_count, 8);

        if (stream_hw_path) begin
            run_pe_accumulator_stream_hw_check(pass);
        end else if (full_hw_path) begin
            run_full_controller_hw_path_check(pass);
        end else begin
            run_input_decoder_hw_check(pass);
            run_output_encoder_hw_check(pass);
            run_pe_accumulator_hw_smoke_check(pass);
            run_controller_sram_pe_hw_smoke_check(pass);
        end

        if (!pass) begin
            $fatal(1, "[tb] RLC reference / HW integration failed");
        end

        $display("[tb] PASS: reference converter and HW RLC units are consistent");
        $finish;
    end


    // ------------------------------------------------------------------------
    // Hardware stream drivers/checkers.
    //
    // A stream beat transfers on a rising clock edge where valid && ready are 1.
    // The driver waits for ready, drives data+valid for one clock, then moves on
    // to the next beat. Done signals are end-of-stream markers, not per-beat
    // permission to send the next item.
    // ------------------------------------------------------------------------
    task automatic reset_hw_units();
        rst = 1'b1;
        dec_token_data_i = '0;
        dec_token_valid_i = 1'b0;
        dec_ctrl_ready_i = 1'b1;
        dec_sram_raddr_i = 16'd0;
        weight_sram_wen_i = 1'b0;
        weight_sram_waddr_i = 16'd0;
        weight_sram_wdata_i = '0;
        weight_sram_raddr_i = 16'd0;
        enc_ppu_data_i = '0;
        enc_ppu_valid_i = 1'b0;
        enc_ppu_last_i = 1'b0;
        output_use_hw_ppu_i = 1'b0;
        ppu_scalar_data_i = '0;
        ppu_scalar_valid_i = 1'b0;
        ppu_scalar_last_i = 1'b0;
        ppu_scaling_factor_i = scaling_factor[5:0];
        ppu_relu_en_i = relu_en;
        ppu_maxpool_en_i = maxpool_en;
        ppu_maxpool_init_i = 1'b0;
        ppu_maxpool_emit_i = 1'b0;
        output_use_pe_accum_i = 1'b0;
        pe_accum_valid_i = 1'b0;
        pe_mode_1x1_i = 1'b0;
        pe_ifmap_data_i = '0;
        pe_weight_data_i = '0;
        pe_accum_last_i = 1'b0;
        pe_accum_base_idx_i = 10'd0;
        output_use_controller_i = 1'b0;
        controller_config_i = '0;
        controller_ifmap_base_addr_i = 16'd0;
        controller_filter_base_addr_i = 16'd0;
        controller_capture_limit_i = 16'd0;
        enc_token_ready_i = 1'b1;
        dec_event_count = 0;
        dec_nonzero_event_count = 0;
        dec_zero_event_count = 0;
        dec_last_event_count = 0;
        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;
        @(posedge clk);
        #1;
    endtask

    task automatic send_input_decoder_token(input rlc_token_t token);
        int guard;

        guard = 0;
        while (!dec_token_ready_o) begin
            @(posedge clk);
            #1;
            guard++;
            if (guard > 1000) begin
                $fatal(1, "[tb] timeout waiting for input_RLC_decoder.token_ready_o");
            end
        end

        dec_token_data_i = token;
        dec_token_valid_i = 1'b1;
        @(posedge clk);
        #1;
        dec_token_valid_i = 1'b0;
        dec_token_data_i = '0;
    endtask

    task automatic send_output_encoder_vector(
        input rlc_vec_t vector,
        input bit is_last
    );
        int guard;

        guard = 0;
        while (!enc_ppu_ready_o) begin
            @(posedge clk);
            #1;
            guard++;
            if (guard > 1000) begin
                $fatal(1, "[tb] timeout waiting for output_RLC_encoder.ppu_ready_o");
            end
        end

        enc_ppu_data_i = vector;
        enc_ppu_last_i = is_last;
        enc_ppu_valid_i = 1'b1;
        @(posedge clk);
        #1;
        enc_ppu_valid_i = 1'b0;
        enc_ppu_last_i = 1'b0;
        enc_ppu_data_i = '0;
    endtask

    task automatic send_pe_accumulator_packet(
        input rlc_vec_t ifmap_data,
        input filter_beat_t weight_data,
        input bit mode_1x1,
        input bit is_last,
        input logic [9:0] base_idx
    );
        int guard;

        guard = 0;
        while (!pe_accum_ready_o) begin
            @(posedge clk);
            #1;
            guard++;
            if (guard > 1000) begin
                $fatal(1, "[tb] timeout waiting for PE accumulator smoke ready");
            end
        end

        pe_ifmap_data_i = ifmap_data;
        pe_weight_data_i = weight_data;
        pe_mode_1x1_i = mode_1x1;
        pe_accum_last_i = is_last;
        pe_accum_base_idx_i = base_idx;
        pe_accum_valid_i = 1'b1;
        @(posedge clk);
        #1;
        pe_accum_valid_i = 1'b0;
        pe_accum_last_i = 1'b0;
        pe_accum_base_idx_i = 10'd0;
        pe_ifmap_data_i = '0;
        pe_weight_data_i = '0;
    endtask

    task automatic write_weight_sram_filter_beat(
        input int beat_idx,
        input filter_beat_t beat
    );
        int guard;

        guard = 0;
        while (!weight_sram_ready_o) begin
            @(posedge clk);
            #1;
            guard++;
            if (guard > 1000) begin
                $fatal(1, "[tb] timeout waiting for weight_sram_reg.ready_o");
            end
        end

        weight_sram_waddr_i = 16'(beat_idx);
        weight_sram_wdata_i = beat;
        weight_sram_wen_i = 1'b1;
        @(posedge clk);
        #1;
        weight_sram_wen_i = 1'b0;
        weight_sram_waddr_i = 16'd0;
        weight_sram_wdata_i = '0;
    endtask

    task automatic wait_input_decoder_stream_done(ref bit ok);
        int guard;

        guard = 0;
        while (!dec_ctrl_done_o) begin
            @(posedge clk);
            #1;
            guard++;
            if (guard > 1000) begin
                ok = 1'b0;
                $display("[tb] input_RLC_decoder timeout waiting for ctrl_done_o");
                return;
            end
        end
    endtask

    task automatic wait_output_encoder_stream_done(ref bit ok);
        wait_output_encoder_token_count(ok, golden_token_count, "output_RLC_encoder");
    endtask

    task automatic wait_output_encoder_token_count(
        ref bit ok,
        input int expected_count,
        input string label
    );
        int guard;

        guard = 0;
        while (hw_golden_token_count < expected_count) begin
            @(posedge clk);
            #1;
            guard++;
            if (guard > 2000) begin
                ok = 1'b0;
                $display("[tb] %s timeout waiting for expected token count: got=%0d expected=%0d",
                         label, hw_golden_token_count, expected_count);
                return;
            end
        end
    endtask

    task automatic wait_output_encoder_done(ref bit ok, input string label);
        int guard;

        guard = 0;
        while (!enc_ctrl_done_o) begin
            @(posedge clk);
            #1;
            guard++;
            if (guard > 10000) begin
                ok = 1'b0;
                $display("[tb] %s timeout waiting for output encoder terminal token: got_tokens=%0d",
                         label, hw_golden_token_count);
                return;
            end
        end
        @(posedge clk);
        #1;
    endtask

    task automatic run_input_decoder_hw_check(ref bit ok);
        int token_idx;

        reset_hw_units();

        if (ifmap_vec_count > 256) begin
            $fatal(1, "[tb] input_sram_reg only stores 256 vectors, got %0d", ifmap_vec_count);
        end
        if (weight_filter_beat_count > 256) begin
            $fatal(1, "[tb] weight_sram_reg only stores 256 filter beats, got %0d", weight_filter_beat_count);
        end

        load_weight_sram_hw();

        for (token_idx = 0; token_idx < ifmap_token_count; token_idx++) begin
            send_input_decoder_token(ifmap_tokens[token_idx]);
        end

        wait_input_decoder_stream_done(ok);
        @(posedge clk);
        #1;
        check_input_decoder_events(ok);
        check_input_sram_hw(ok);
        check_weight_sram_hw(ok);
    endtask

    task automatic check_input_decoder_events(ref bit ok);
        int token_idx;
        int expected_events;
        int expected_nonzero_events;
        int expected_zero_events;
        bit is_continuation;

        expected_events = 0;
        expected_nonzero_events = 0;
        expected_zero_events = 0;

        for (token_idx = 0; token_idx < ifmap_token_count; token_idx++) begin
            is_continuation = (rlc_token_payload(ifmap_tokens[token_idx]) == '0) &&
                              !rlc_token_last(ifmap_tokens[token_idx]);
            if (!is_continuation) begin
                expected_events++;
                if (rlc_token_payload(ifmap_tokens[token_idx]) != '0) begin
                    expected_nonzero_events++;
                end else begin
                    expected_zero_events++;
                end
            end
        end

        $display("[tb] input_RLC_decoder event summary: events=%0d/%0d nonzero=%0d/%0d zero_tail=%0d/%0d last=%0d/1",
                 dec_event_count, expected_events,
                 dec_nonzero_event_count, expected_nonzero_events,
                 dec_zero_event_count, expected_zero_events,
                 dec_last_event_count);

        if (dec_event_count != expected_events ||
            dec_nonzero_event_count != expected_nonzero_events ||
            dec_zero_event_count != expected_zero_events ||
            dec_last_event_count != 1) begin
            ok = 1'b0;
            $display("[tb] input_RLC_decoder event summary mismatch");
        end else begin
            $display("[tb] input_RLC_decoder ctrl event stream pass");
        end
    endtask

    task automatic check_input_sram_hw(ref bit ok);
        int vec_idx;
        int mismatch_prints;

        mismatch_prints = 0;
        for (vec_idx = 0; vec_idx < ifmap_vec_count; vec_idx++) begin
            dec_sram_raddr_i = 16'(vec_idx);
            #1;
            if (dec_sram_rdata_o !== ifmap_vecs[vec_idx]) begin
                ok = 1'b0;
                if (mismatch_prints < 8) begin
                    $display("[tb] input_RLC_decoder SRAM vec[%0d] mismatch: got=0x%014h expected=0x%014h",
                             vec_idx, dec_sram_rdata_o, ifmap_vecs[vec_idx]);
                    mismatch_prints++;
                end
            end
        end

        if (mismatch_prints == 0) begin
            $display("[tb] input_RLC_decoder hw pass: %0d token(s) decoded into %0d SRAM vector(s)",
                     ifmap_token_count, ifmap_vec_count);
        end
    endtask

    task automatic load_weight_sram_hw();
        int beat_idx;

        for (beat_idx = 0; beat_idx < weight_filter_beat_count; beat_idx++) begin
            write_weight_sram_filter_beat(beat_idx, weight_filter_beats[beat_idx]);
        end
    endtask

    task automatic check_weight_sram_hw(ref bit ok);
        int beat_idx;
        int mismatch_prints;

        mismatch_prints = 0;
        for (beat_idx = 0; beat_idx < weight_filter_beat_count; beat_idx++) begin
            weight_sram_raddr_i = 16'(beat_idx);
            #1;
            if (weight_sram_rdata_o !== weight_filter_beats[beat_idx]) begin
                ok = 1'b0;
                if (mismatch_prints < 8) begin
                    $display("[tb] weight_sram_reg beat[%0d] mismatch: got=0x%06h expected=0x%06h",
                             beat_idx, weight_sram_rdata_o, weight_filter_beats[beat_idx]);
                    mismatch_prints++;
                end
            end
        end

        if (mismatch_prints == 0) begin
            $display("[tb] weight_sram_reg hw pass: %0d raw 3x8 filter beat(s) stored", weight_filter_beat_count);
        end
    endtask

    task automatic run_output_encoder_hw_check(ref bit ok);
        int vec_idx;

        hw_golden_token_count = 0;
        reset_hw_units();

        for (vec_idx = 0; vec_idx < golden_vec_count; vec_idx++) begin
            send_output_encoder_vector(golden_vecs[vec_idx], vec_idx == golden_vec_count - 1);
        end

        wait_output_encoder_stream_done(ok);
        ok &= compare_tokens("output_RLC_encoder hw tokens", golden_tokens, golden_token_count,
                             hw_golden_tokens, hw_golden_token_count);
    endtask

    task automatic run_pe_accumulator_hw_smoke_check(ref bit ok);
        rlc_vec_t smoke_ifmap;
        filter_beat_t smoke_weight;
        int selected_weight_beat;

        hw_golden_token_count = 0;
        reset_hw_units();

        build_pe_accumulator_smoke_expected(smoke_ifmap, smoke_weight, selected_weight_beat);

        output_use_pe_accum_i = 1'b1;
        output_use_hw_ppu_i = 1'b0;
        ppu_scaling_factor_i = scaling_factor[5:0];
        ppu_relu_en_i = relu_en;
        ppu_maxpool_en_i = 1'b0;
        ppu_maxpool_init_i = 1'b0;
        ppu_maxpool_emit_i = 1'b0;

        $display("[tb] PE->accumulator smoke input: ifmap_vec[0] signed=0x%014h weight_beat[%0d]=0x%06h",
                 smoke_ifmap, selected_weight_beat, smoke_weight);
        $display("[tb] PE->accumulator smoke expected token count = %0d",
                 pe_hw_expected_token_count);

        send_pe_accumulator_packet(smoke_ifmap, smoke_weight, 1'b0, 1'b1, 10'd0);
        wait_output_encoder_token_count(ok, pe_hw_expected_token_count, "PE->accumulator smoke");
        ok &= compare_tokens("PE->accumulator->PPU->RLC smoke tokens",
                             pe_hw_expected_tokens, pe_hw_expected_token_count,
                             hw_golden_tokens, hw_golden_token_count);

        output_use_pe_accum_i = 1'b0;
    endtask

    task automatic run_controller_sram_pe_hw_smoke_check(ref bit ok);
        rlc_vec_t controller_ifmap;
        filter_beat_t controller_weight;
        int selected_weight_beat;
        int token_idx;

        reset_hw_units();

        if (ifmap_vec_count > 256) begin
            $fatal(1, "[tb] input_sram_reg only stores 256 vectors, got %0d", ifmap_vec_count);
        end
        if (weight_filter_beat_count > 256) begin
            $fatal(1, "[tb] weight_sram_reg only stores 256 filter beats, got %0d", weight_filter_beat_count);
        end

        load_weight_sram_hw();
        for (token_idx = 0; token_idx < ifmap_token_count; token_idx++) begin
            send_input_decoder_token(ifmap_tokens[token_idx]);
        end
        wait_input_decoder_stream_done(ok);
        @(posedge clk);
        #1;

        build_controller_sram_pe_smoke_expected(controller_ifmap, controller_weight, selected_weight_beat);

        hw_golden_token_count = 0;
        controller_config_i = {2'b00, 9'd1, 9'd1, 5'd0, 5'd0};
        controller_ifmap_base_addr_i = 16'd0;
        controller_filter_base_addr_i = 16'(selected_weight_beat);
        controller_capture_limit_i = 16'd1;
        output_use_hw_ppu_i = 1'b0;
        ppu_scaling_factor_i = scaling_factor[5:0];
        ppu_relu_en_i = relu_en;
        ppu_maxpool_en_i = 1'b0;
        ppu_maxpool_init_i = 1'b0;
        ppu_maxpool_emit_i = 1'b0;
        @(posedge clk);
        #1;

        $display("[tb] Controller SRAM smoke input: input_sram[0]=0x%014h filter_base=%0d filter=0x%06h config=0x%08h",
                 controller_ifmap, selected_weight_beat, controller_weight, controller_config_i);
        $display("[tb] Controller SRAM smoke expected token count = %0d",
                 pe_hw_expected_token_count);

        output_use_controller_i = 1'b1;
        wait_output_encoder_token_count(ok, pe_hw_expected_token_count, "Controller SRAM->PE smoke");
        ok &= compare_tokens("SRAM->Controller->PE->accumulator->PPU->RLC smoke tokens",
                             pe_hw_expected_tokens, pe_hw_expected_token_count,
                             hw_golden_tokens, hw_golden_token_count);

        output_use_controller_i = 1'b0;
    endtask

    task automatic run_full_controller_hw_path_check(ref bit ok);
        int selected_weight_beat;
        int token_idx;
        int expected_scalar_count;

        reset_hw_units();

        if (ifmap_vec_count > 256) begin
            $fatal(1, "[tb] input_sram_reg only stores 256 vectors, got %0d", ifmap_vec_count);
        end
        if (weight_filter_beat_count > 256) begin
            $fatal(1, "[tb] weight_sram_reg only stores 256 filter beats, got %0d", weight_filter_beat_count);
        end

        load_weight_sram_hw();
        for (token_idx = 0; token_idx < ifmap_token_count; token_idx++) begin
            send_input_decoder_token(ifmap_tokens[token_idx]);
        end
        wait_input_decoder_stream_done(ok);
        @(posedge clk);
        #1;
        check_input_decoder_events(ok);
        check_input_sram_hw(ok);
        check_weight_sram_hw(ok);

        selected_weight_beat = first_nonzero_weight_beat();
        expected_scalar_count = full_hw_packet_limit * 9;
        build_golden_prefix_expected(expected_scalar_count);

        hw_golden_token_count = 0;
        controller_config_i = {2'b00, 9'd1, 9'd1, 5'd0, 5'd0};
        controller_ifmap_base_addr_i = 16'd0;
        controller_filter_base_addr_i = 16'(selected_weight_beat);
        controller_capture_limit_i = 16'(full_hw_packet_limit);
        output_use_hw_ppu_i = 1'b0;
        ppu_scaling_factor_i = scaling_factor[5:0];
        ppu_relu_en_i = relu_en;
        ppu_maxpool_en_i = 1'b0;
        ppu_maxpool_init_i = 1'b0;
        ppu_maxpool_emit_i = 1'b0;
        @(posedge clk);
        #1;

        $display("[tb] FULL PATH start: packets=%0d expected_scalars=%0d filter_base=%0d config=0x%08h",
                 full_hw_packet_limit, expected_scalar_count, selected_weight_beat, controller_config_i);
        output_use_controller_i = 1'b1;
        wait_output_encoder_done(ok, "FULL PATH");

        $display("[tb] FULL PATH output token count = %0d", hw_golden_token_count);
        print_tokens("full_path_hw", hw_golden_tokens, hw_golden_token_count, 12);
        decompress_tokens("full_path_hw", hw_golden_tokens, hw_golden_token_count,
                          rlc_zero_vec(output_zero_lane),
                          hw_output_roundtrip, hw_output_roundtrip_count);
        ok &= compare_vecs("FULL PATH decoded output vs golden prefix",
                           pe_hw_expected_vecs, pe_hw_expected_vec_count,
                           hw_output_roundtrip, hw_output_roundtrip_count);

        output_use_controller_i = 1'b0;
    endtask

    task automatic run_pe_accumulator_stream_hw_check(ref bit ok);
        int selected_weight_beat;
        int token_idx;
        int packet_idx;
        int stream_vec_count;
        filter_beat_t stream_weight;
        rlc_vec_t sram_ifmap;
        rlc_vec_t pe_ifmap;

        reset_hw_units();

        if ((stream_input_scalars % RLC_LANES) != 0) begin
            $fatal(1, "[tb] STREAM_INPUT_SCALARS=%0d must be a multiple of %0d for this first stream test",
                   stream_input_scalars, RLC_LANES);
        end
        if (stream_input_scalars > ifmap_count) begin
            $fatal(1, "[tb] stream test needs %0d input scalars but IFMAP_FILE only has %0d",
                   stream_input_scalars, ifmap_count);
        end

        stream_vec_count = stream_input_scalars / RLC_LANES;
        if (stream_vec_count > ifmap_vec_count) begin
            $fatal(1, "[tb] stream test needs %0d vectors but only has %0d",
                   stream_vec_count, ifmap_vec_count);
        end
        if (stream_vec_count > 256) begin
            $fatal(1, "[tb] input_sram_reg only stores 256 vectors, got %0d", stream_vec_count);
        end
        if (weight_filter_beat_count > 256) begin
            $fatal(1, "[tb] weight_sram_reg only stores 256 filter beats, got %0d", weight_filter_beat_count);
        end

        load_weight_sram_hw();
        for (token_idx = 0; token_idx < ifmap_token_count; token_idx++) begin
            send_input_decoder_token(ifmap_tokens[token_idx]);
        end
        wait_input_decoder_stream_done(ok);
        @(posedge clk);
        #1;
        check_input_decoder_events(ok);
        check_input_sram_hw(ok);
        check_weight_sram_hw(ok);

        build_pe_accumulator_stream_expected(stream_vec_count, stream_weight, selected_weight_beat);

        weight_sram_raddr_i = 16'(selected_weight_beat);
        #1;
        if (weight_sram_rdata_o !== stream_weight) begin
            ok = 1'b0;
            $display("[tb] STREAM weight SRAM read mismatch: got=0x%06h expected=0x%06h",
                     weight_sram_rdata_o, stream_weight);
        end

        hw_golden_token_count = 0;
        output_use_pe_accum_i = 1'b1;
        output_use_hw_ppu_i = 1'b0;
        ppu_scaling_factor_i = scaling_factor[5:0];
        ppu_relu_en_i = relu_en;
        ppu_maxpool_en_i = 1'b0;
        ppu_maxpool_init_i = 1'b0;
        ppu_maxpool_emit_i = 1'b0;
        @(posedge clk);
        #1;

        $display("[tb] STREAM PATH start: input_scalars=%0d input_vectors=%0d pe_fires=%0d weight_beat[%0d]=0x%06h",
                 stream_input_scalars, stream_vec_count, stream_vec_count,
                 selected_weight_beat, stream_weight);

        for (packet_idx = 0; packet_idx < stream_vec_count; packet_idx++) begin
            dec_sram_raddr_i = 16'(packet_idx);
            #1;
            sram_ifmap = dec_sram_rdata_o;
            pe_ifmap = pe_ifmap_from_qint8_vec(sram_ifmap);
            send_pe_accumulator_packet(pe_ifmap, stream_weight, 1'b0,
                                       packet_idx == stream_vec_count - 1,
                                       10'(packet_idx * 9));
        end

        wait_output_encoder_token_count(ok, pe_hw_expected_token_count, "STREAM PATH");

        $display("[tb] STREAM PATH output token count = %0d", hw_golden_token_count);
        print_tokens("stream_hw", hw_golden_tokens, hw_golden_token_count, 12);
        decompress_tokens("stream_hw", hw_golden_tokens, hw_golden_token_count,
                          rlc_zero_vec(output_zero_lane),
                          hw_output_roundtrip, hw_output_roundtrip_count);
        write_vecs_to_file(stream_hw_out_file, hw_output_roundtrip, hw_output_roundtrip_count);
        ok &= compare_vecs("STREAM PATH decoded output vs expected",
                           pe_hw_expected_vecs, pe_hw_expected_vec_count,
                           hw_output_roundtrip, hw_output_roundtrip_count);

        output_use_pe_accum_i = 1'b0;
    endtask

    task automatic compute_pe_3x3_psums(
        input rlc_vec_t pe_ifmap,
        input filter_beat_t weight,
        ref int psum_values [0:MAX_VALUES-1],
        input int base
    );
        int lane;
        int signed_ifmap [0:6];
        int signed_weight [0:2];

        if ((base + 8) >= MAX_VALUES) begin
            $fatal(1, "[tb] PE psum base %0d exceeds MAX_VALUES=%0d", base, MAX_VALUES);
        end

        for (lane = 0; lane < RLC_LANES; lane++) begin
            signed_ifmap[lane] = int'($signed(pe_ifmap[lane * RLC_LANE_BITS +: RLC_LANE_BITS]));
        end
        for (lane = 0; lane < 3; lane++) begin
            signed_weight[lane] = int'($signed(weight[lane * 8 +: 8]));
        end

        psum_values[base + 0] = signed_ifmap[0] * signed_weight[2];
        psum_values[base + 1] = signed_ifmap[0] * signed_weight[1] + signed_ifmap[1] * signed_weight[2];
        for (lane = 2; lane < 7; lane++) begin
            psum_values[base + lane] = signed_ifmap[lane - 2] * signed_weight[0] +
                                       signed_ifmap[lane - 1] * signed_weight[1] +
                                       signed_ifmap[lane] * signed_weight[2];
        end
        psum_values[base + 7] = signed_ifmap[5] * signed_weight[0] + signed_ifmap[6] * signed_weight[1];
        psum_values[base + 8] = signed_ifmap[6] * signed_weight[0];
    endtask

    task automatic build_pe_accumulator_stream_expected(
        input int stream_vec_count,
        output filter_beat_t stream_weight,
        output int selected_weight_beat
    );
        int psum_values [0:MAX_VALUES-1];
        int ppu_values [0:MAX_VALUES-1];
        int ppu_count;
        int packet_idx;
        int psum_count;
        rlc_vec_t pe_ifmap;

        if (stream_vec_count <= 0) begin
            $fatal(1, "[tb] STREAM expected requires at least one vector");
        end
        if (weight_filter_beat_count <= 0) begin
            $fatal(1, "[tb] STREAM expected requires at least one filter beat");
        end

        psum_count = stream_vec_count * 9;
        if (psum_count > MAX_VALUES) begin
            $fatal(1, "[tb] STREAM expected needs %0d psums, MAX_VALUES=%0d", psum_count, MAX_VALUES);
        end

        selected_weight_beat = first_nonzero_weight_beat();
        stream_weight = weight_filter_beats[selected_weight_beat];

        for (packet_idx = 0; packet_idx < stream_vec_count; packet_idx++) begin
            pe_ifmap = pe_ifmap_from_qint8_vec(ifmap_vecs[packet_idx]);
            compute_pe_3x3_psums(pe_ifmap, stream_weight, psum_values, packet_idx * 9);
        end

        process_psum_with_ppu_ref(psum_values, psum_count, scaling_factor, relu_en, 1'b0,
                                  ppu_values, ppu_count);
        pack_values_to_vecs("STREAM expected", ppu_values, ppu_count, output_zero_lane,
                            pe_hw_expected_vecs, pe_hw_expected_vec_count);
        compress_vecs("STREAM expected",
                      pe_hw_expected_vecs, pe_hw_expected_vec_count, rlc_zero_vec(output_zero_lane),
                      pe_hw_expected_tokens, pe_hw_expected_token_count);

        $display("[tb] STREAM expected: psum_scalars=%0d ppu_scalars=%0d output_vectors=%0d tokens=%0d",
                 psum_count, ppu_count, pe_hw_expected_vec_count, pe_hw_expected_token_count);
        $display("[tb] STREAM first psum[0:8] = %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 psum_values[0], psum_values[1], psum_values[2],
                 psum_values[3], psum_values[4], psum_values[5],
                 psum_values[6], psum_values[7], psum_values[8]);
    endtask

    task automatic build_pe_accumulator_smoke_expected(
        output rlc_vec_t smoke_ifmap,
        output filter_beat_t smoke_weight,
        output int selected_weight_beat
    );
        int psum_values [0:MAX_VALUES-1];
        int ppu_values [0:MAX_VALUES-1];
        int ppu_count;
        int lane;
        int beat_idx;
        int signed_ifmap [0:6];
        int signed_weight [0:2];

        if (ifmap_vec_count <= 0) begin
            $fatal(1, "[tb] PE smoke requires at least one ifmap vector");
        end
        if (weight_filter_beat_count <= 0) begin
            $fatal(1, "[tb] PE smoke requires at least one filter beat");
        end

        selected_weight_beat = first_nonzero_weight_beat();

        smoke_ifmap = '0;
        for (lane = 0; lane < RLC_LANES; lane++) begin
            smoke_ifmap[lane * RLC_LANE_BITS +: RLC_LANE_BITS] =
                qint8_to_pe_signed(rlc_vec_lane(ifmap_vecs[0], lane));
            signed_ifmap[lane] = int'($signed(smoke_ifmap[lane * RLC_LANE_BITS +: RLC_LANE_BITS]));
        end

        smoke_weight = weight_filter_beats[selected_weight_beat];
        for (lane = 0; lane < 3; lane++) begin
            signed_weight[lane] = int'($signed(smoke_weight[lane * 8 +: 8]));
        end

        psum_values[0] = signed_ifmap[0] * signed_weight[2];
        psum_values[1] = signed_ifmap[0] * signed_weight[1] + signed_ifmap[1] * signed_weight[2];
        for (lane = 2; lane < 7; lane++) begin
            psum_values[lane] = signed_ifmap[lane - 2] * signed_weight[0] +
                                signed_ifmap[lane - 1] * signed_weight[1] +
                                signed_ifmap[lane] * signed_weight[2];
        end
        psum_values[7] = signed_ifmap[5] * signed_weight[0] + signed_ifmap[6] * signed_weight[1];
        psum_values[8] = signed_ifmap[6] * signed_weight[0];

        process_psum_with_ppu_ref(psum_values, 9, scaling_factor, relu_en, 1'b0,
                                  ppu_values, ppu_count);
        pack_values_to_vecs("PE accumulator smoke expected", ppu_values, ppu_count, 8'd0,
                            pe_hw_expected_vecs, pe_hw_expected_vec_count);
        compress_vecs("PE accumulator smoke expected",
                      pe_hw_expected_vecs, pe_hw_expected_vec_count, rlc_zero_vec(8'd0),
                      pe_hw_expected_tokens, pe_hw_expected_token_count);

        $display("[tb] PE smoke psum[0:8] = %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 psum_values[0], psum_values[1], psum_values[2],
                 psum_values[3], psum_values[4], psum_values[5],
                 psum_values[6], psum_values[7], psum_values[8]);
        $display("[tb] PE smoke PPU expected[0:8] = %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 ppu_values[0], ppu_values[1], ppu_values[2],
                 ppu_values[3], ppu_values[4], ppu_values[5],
                 ppu_values[6], ppu_values[7], ppu_values[8]);
    endtask

    function automatic int first_nonzero_weight_beat();
        for (int beat_idx = 0; beat_idx < weight_filter_beat_count; beat_idx++) begin
            if (weight_filter_beats[beat_idx] != '0) begin
                return beat_idx;
            end
        end
        return 0;
    endfunction

    task automatic build_golden_prefix_expected(input int scalar_count);
        int prefix_values [0:MAX_VALUES-1];
        int prefix_count;
        int idx;

        prefix_count = scalar_count;
        if (prefix_count > MAX_VALUES) begin
            $fatal(1, "[tb] full path expected prefix needs %0d scalars, MAX_VALUES=%0d",
                   prefix_count, MAX_VALUES);
        end
        if (prefix_count > golden_ppu_count) begin
            $display("[tb] full path expected prefix truncated: requested=%0d available=%0d",
                     prefix_count, golden_ppu_count);
            prefix_count = golden_ppu_count;
        end

        for (idx = 0; idx < prefix_count; idx++) begin
            if (process_golden_psum) begin
                prefix_values[idx] = golden_ppu_values[idx];
            end else begin
                prefix_values[idx] = golden_values[idx];
            end
        end

        pack_values_to_vecs("FULL PATH golden prefix", prefix_values, prefix_count, output_zero_lane,
                            pe_hw_expected_vecs, pe_hw_expected_vec_count);
        compress_vecs("FULL PATH golden prefix",
                      pe_hw_expected_vecs, pe_hw_expected_vec_count, rlc_zero_vec(output_zero_lane),
                      pe_hw_expected_tokens, pe_hw_expected_token_count);

        $display("[tb] FULL PATH golden prefix: scalars=%0d vectors=%0d tokens=%0d",
                 prefix_count, pe_hw_expected_vec_count, pe_hw_expected_token_count);
    endtask

    task automatic build_controller_sram_pe_smoke_expected(
        output rlc_vec_t controller_ifmap,
        output filter_beat_t controller_weight,
        output int selected_weight_beat
    );
        int psum_values [0:MAX_VALUES-1];
        int ppu_values [0:MAX_VALUES-1];
        int ppu_count;
        int lane;
        int beat_idx;
        int signed_ifmap [0:6];
        int signed_weight [0:2];

        if (ifmap_vec_count <= 0) begin
            $fatal(1, "[tb] Controller smoke requires at least one ifmap vector");
        end
        if (weight_filter_beat_count <= 0) begin
            $fatal(1, "[tb] Controller smoke requires at least one filter beat");
        end

        selected_weight_beat = first_nonzero_weight_beat();

        controller_ifmap = ifmap_vecs[0];
        controller_weight = weight_filter_beats[selected_weight_beat];

        for (lane = 0; lane < RLC_LANES; lane++) begin
            signed_ifmap[lane] = int'($signed(qint8_to_pe_signed(controller_ifmap[lane * RLC_LANE_BITS +: RLC_LANE_BITS])));
        end
        for (lane = 0; lane < 3; lane++) begin
            signed_weight[lane] = int'($signed(controller_weight[lane * 8 +: 8]));
        end

        psum_values[0] = signed_ifmap[0] * signed_weight[2];
        psum_values[1] = signed_ifmap[0] * signed_weight[1] + signed_ifmap[1] * signed_weight[2];
        for (lane = 2; lane < 7; lane++) begin
            psum_values[lane] = signed_ifmap[lane - 2] * signed_weight[0] +
                                signed_ifmap[lane - 1] * signed_weight[1] +
                                signed_ifmap[lane] * signed_weight[2];
        end
        psum_values[7] = signed_ifmap[5] * signed_weight[0] + signed_ifmap[6] * signed_weight[1];
        psum_values[8] = signed_ifmap[6] * signed_weight[0];

        process_psum_with_ppu_ref(psum_values, 9, scaling_factor, relu_en, 1'b0,
                                  ppu_values, ppu_count);
        pack_values_to_vecs("Controller SRAM smoke expected", ppu_values, ppu_count, 8'd0,
                            pe_hw_expected_vecs, pe_hw_expected_vec_count);
        compress_vecs("Controller SRAM smoke expected",
                      pe_hw_expected_vecs, pe_hw_expected_vec_count, rlc_zero_vec(8'd0),
                      pe_hw_expected_tokens, pe_hw_expected_token_count);

        $display("[tb] Controller smoke psum[0:8] = %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 psum_values[0], psum_values[1], psum_values[2],
                 psum_values[3], psum_values[4], psum_values[5],
                 psum_values[6], psum_values[7], psum_values[8]);
        $display("[tb] Controller smoke PPU expected[0:8] = %0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 ppu_values[0], ppu_values[1], ppu_values[2],
                 ppu_values[3], ppu_values[4], ppu_values[5],
                 ppu_values[6], ppu_values[7], ppu_values[8]);
    endtask

    function automatic logic [7:0] rlc_vec_lane(
        input rlc_vec_t vec,
        input int lane
    );
        return vec[(RLC_LANES - 1 - lane) * RLC_LANE_BITS +: RLC_LANE_BITS];
    endfunction

    function automatic logic [7:0] qint8_to_pe_signed(input logic [7:0] value);
        return {~value[7], value[6:0]};
    endfunction

    function automatic rlc_vec_t pe_ifmap_from_qint8_vec(input rlc_vec_t qint8_vec);
        rlc_vec_t pe_vec;
        for (int lane = 0; lane < RLC_LANES; lane++) begin
            pe_vec[lane * RLC_LANE_BITS +: RLC_LANE_BITS] =
                qint8_to_pe_signed(rlc_vec_lane(qint8_vec, lane));
        end
        return pe_vec;
    endfunction

    task automatic check_zero_lane_arg(
        input string name,
        input int value
    );
        if (value < 0 || value > 255) begin
            $fatal(1, "[tb] %s=%0d is outside 0..255", name, value);
        end
    endtask

    task automatic load_csv_i32(
        input string path,
        ref int values [0:MAX_VALUES-1],
        output int count
    );
        int fd;
        int code;
        int ch;
        int value;

        count = 0;
        fd = $fopen(path, "r");
        if (fd == 0) begin
            $fatal(1, "[tb] cannot open %s", path);
        end

        while (!$feof(fd)) begin
            code = $fscanf(fd, " %d", value);
            if (code == 1) begin
                if (count >= MAX_VALUES) begin
                    $fatal(1, "[tb] %s exceeds MAX_VALUES=%0d", path, MAX_VALUES);
                end
                values[count] = value;
                count++;
            end else begin
                ch = $fgetc(fd);
                if (ch < 0) begin
                    break;
                end
            end
        end
        $fclose(fd);
    endtask


    task automatic process_psum_with_ppu_ref(
        ref int psum_values [0:MAX_VALUES-1],
        input int psum_count,
        input int scaling,
        input bit relu_enable,
        input bit maxpool_enable,
        ref int out_values [0:MAX_VALUES-1],
        output int out_count
    );
        logic [7:0] post_values [0:MAX_VALUES-1];
        logic [7:0] pooled;
        int idx;
        int group_idx;

        out_count = 0;
        for (idx = 0; idx < psum_count; idx++) begin
            post_values[idx] = relu_qint8(post_quant_qint8(psum_values[idx], scaling), relu_enable);
        end

        if (maxpool_enable) begin
            idx = 0;
            while (idx < psum_count) begin
                pooled = post_values[idx];
                for (group_idx = 1; group_idx < 4 && (idx + group_idx) < psum_count; group_idx++) begin
                    if (post_values[idx + group_idx] > pooled) begin
                        pooled = post_values[idx + group_idx];
                    end
                end
                if (out_count >= MAX_VALUES) begin
                    $fatal(1, "[tb] PPU reference output exceeds MAX_VALUES=%0d", MAX_VALUES);
                end
                out_values[out_count] = int'(pooled);
                out_count++;
                idx += 4;
            end
        end else begin
            for (idx = 0; idx < psum_count; idx++) begin
                out_values[idx] = int'(post_values[idx]);
            end
            out_count = psum_count;
        end
    endtask

    function automatic logic [7:0] post_quant_qint8(
        input int psum,
        input int scaling
    );
        int shifted;
        int clipped;
        logic [7:0] signed_byte;

        shifted = psum >>> scaling;
        if (shifted > 127) begin
            clipped = 127;
        end else if (shifted < -128) begin
            clipped = -128;
        end else begin
            clipped = shifted;
        end

        signed_byte = clipped[7:0];
        return {~signed_byte[7], signed_byte[6:0]};
    endfunction

    function automatic logic [7:0] relu_qint8(
        input logic [7:0] value,
        input bit enable
    );
        if (enable && value < 8'd128) begin
            return 8'd128;
        end
        return value;
    endfunction

    task automatic pack_values_to_vecs(
        input string label,
        ref int values [0:MAX_VALUES-1],
        input int value_count,
        input logic [7:0] pad_lane,
        ref rlc_vec_t vecs [0:MAX_VECS-1],
        output int vec_count
    );
        int vec_idx;
        int lane;
        int value_idx;
        logic [7:0] lane_value;

        vec_count = (value_count + RLC_LANES - 1) / RLC_LANES;
        if (vec_count > MAX_VECS) begin
            $fatal(1, "[tb] %s needs %0d vectors, MAX_VECS=%0d", label, vec_count, MAX_VECS);
        end

        for (vec_idx = 0; vec_idx < vec_count; vec_idx++) begin
            vecs[vec_idx] = '0;
            for (lane = 0; lane < RLC_LANES; lane++) begin
                value_idx = vec_idx * RLC_LANES + lane;
                if (value_idx < value_count) begin
                    check_8bit_value(label, value_idx, values[value_idx]);
                    lane_value = values[value_idx][7:0];
                end else begin
                    lane_value = pad_lane;
                end
                vecs[vec_idx][(RLC_LANES - 1 - lane) * RLC_LANE_BITS +: RLC_LANE_BITS] = lane_value;
            end
        end
    endtask

    task automatic pack_weight_values_to_filter_beats(
        input string label,
        ref int values [0:MAX_VALUES-1],
        input int value_count,
        input logic [7:0] pad_lane,
        ref filter_beat_t beats [0:MAX_VALUES-1],
        output int beat_count
    );
        int beat_idx;
        int lane;
        int value_idx;
        logic [7:0] lane_value;

        beat_count = (value_count + 2) / 3;
        if (beat_count > MAX_VALUES) begin
            $fatal(1, "[tb] %s needs %0d filter beats, MAX_VALUES=%0d", label, beat_count, MAX_VALUES);
        end

        for (beat_idx = 0; beat_idx < beat_count; beat_idx++) begin
            beats[beat_idx] = '0;
            for (lane = 0; lane < 3; lane++) begin
                value_idx = beat_idx * 3 + lane;
                if (value_idx < value_count) begin
                    check_8bit_value(label, value_idx, values[value_idx]);
                    lane_value = values[value_idx][7:0];
                end else begin
                    lane_value = pad_lane;
                end
                beats[beat_idx][lane * 8 +: 8] = lane_value;
            end
        end
    endtask

    task automatic check_8bit_value(
        input string label,
        input int index,
        input int value
    );
        if (value < -128 || value > 255) begin
            $fatal(1, "[tb] %s[%0d]=%0d does not fit one 8-bit lane", label, index, value);
        end
    endtask

    task automatic compress_vecs(
        input string label,
        ref rlc_vec_t dense [0:MAX_VECS-1],
        input int dense_count,
        input rlc_vec_t zero_vec,
        ref rlc_token_t tokens [0:MAX_TOKENS-1],
        output int token_count
    );
        int run;
        int idx;
        bit is_zero;
        bit is_last_vec;
        rlc_vec_t zero_payload;

        token_count = 0;
        run = 0;
        zero_payload = '0;

        if (dense_count == 0) begin
            emit_token(label, tokens, token_count, 1'b1, 0, zero_payload);
        end

        for (idx = 0; idx < dense_count; idx++) begin
            is_zero = rlc_vec_is_zero(dense[idx], zero_vec);
            is_last_vec = idx == dense_count - 1;

            if (is_zero) begin
                if (is_last_vec) begin
                    if (run == RLC_MAX_RUN) begin
                        emit_token(label, tokens, token_count, 1'b0, RLC_MAX_RUN, zero_payload);
                        emit_token(label, tokens, token_count, 1'b1, 1, zero_payload);
                    end else begin
                        emit_token(label, tokens, token_count, 1'b1, run + 1, zero_payload);
                    end
                    run = 0;
                end else if (run == RLC_MAX_RUN) begin
                    emit_token(label, tokens, token_count, 1'b0, RLC_MAX_RUN, zero_payload);
                    run = 1;
                end else begin
                    run++;
                end
            end else begin
                emit_token(label, tokens, token_count, is_last_vec, run, dense[idx]);
                run = 0;
            end
        end
    endtask

    task automatic emit_token(
        input string label,
        ref rlc_token_t tokens [0:MAX_TOKENS-1],
        ref int token_count,
        input bit last,
        input int run,
        input rlc_vec_t payload
    );
        if (token_count >= MAX_TOKENS) begin
            $fatal(1, "[tb] %s exceeds MAX_TOKENS=%0d", label, MAX_TOKENS);
        end
        if (run < 0 || run > RLC_MAX_RUN) begin
            $fatal(1, "[tb] %s run=%0d is outside 0..%0d", label, run, RLC_MAX_RUN);
        end
        tokens[token_count] = rlc_make_token(last, run, payload);
        token_count++;
    endtask

    task automatic decompress_tokens(
        input string label,
        ref rlc_token_t tokens [0:MAX_TOKENS-1],
        input int token_count,
        input rlc_vec_t zero_vec,
        ref rlc_vec_t dense [0:MAX_VECS-1],
        output int dense_count
    );
        int token_idx;
        int run;
        int total_run;
        int i;
        bit saw_last;
        bit is_continuation;
        rlc_vec_t payload;
        int pending_run;

        dense_count = 0;
        pending_run = 0;
        saw_last = 1'b0;

        for (token_idx = 0; token_idx < token_count; token_idx++) begin
            run = rlc_token_run(tokens[token_idx]);
            payload = rlc_token_payload(tokens[token_idx]);
            is_continuation = (payload == '0) && !rlc_token_last(tokens[token_idx]);

            if (is_continuation) begin
                pending_run += run;
            end else begin
                total_run = pending_run + run;
                pending_run = 0;
                for (i = 0; i < total_run; i++) begin
                    if (dense_count >= MAX_VECS) begin
                        $fatal(1, "[tb] %s decompressed vector count exceeds MAX_VECS=%0d", label, MAX_VECS);
                    end
                    dense[dense_count] = zero_vec;
                    dense_count++;
                end

                if (payload != '0) begin
                    if (dense_count >= MAX_VECS) begin
                        $fatal(1, "[tb] %s decompressed vector count exceeds MAX_VECS=%0d", label, MAX_VECS);
                    end
                    dense[dense_count] = payload;
                    dense_count++;
                end

                if (rlc_token_last(tokens[token_idx])) begin
                    saw_last = 1'b1;
                    break;
                end
            end
        end

        if (!saw_last) begin
            $fatal(1, "[tb] %s compressed stream has no terminal token", label);
        end
    endtask

    task automatic write_vecs_to_file(
        input string path,
        ref rlc_vec_t vecs [0:MAX_VECS-1],
        input int vec_count
    );
        int fd;
        int idx;

        fd = $fopen(path, "w");
        if (fd == 0) begin
            $fatal(1, "[tb] cannot open %s for write", path);
        end

        for (idx = 0; idx < vec_count; idx++) begin
            $fdisplay(fd, "%0d 0x%014h", idx, vecs[idx]);
        end
        $fclose(fd);
        $display("[tb] wrote %0d output vector(s) to %s", vec_count, path);
    endtask

    function automatic bit compare_vecs(
        input string label,
        ref rlc_vec_t expected [0:MAX_VECS-1],
        input int expected_count,
        ref rlc_vec_t got [0:MAX_VECS-1],
        input int got_count
    );
        bit ok;
        int idx;
        int mismatch_prints;

        ok = 1'b1;
        mismatch_prints = 0;

        if (expected_count != got_count) begin
            $display("[tb] %s count mismatch: got=%0d expected=%0d", label, got_count, expected_count);
            ok = 1'b0;
        end

        for (idx = 0; idx < expected_count && idx < got_count; idx++) begin
            if (expected[idx] !== got[idx]) begin
                ok = 1'b0;
                if (mismatch_prints < 8) begin
                    $display("[tb] %s vec[%0d] mismatch: got=0x%014h expected=0x%014h",
                             label, idx, got[idx], expected[idx]);
                    mismatch_prints++;
                end
            end
        end

        if (ok) begin
            $display("[tb] %s pass", label);
        end
        return ok;
    endfunction

    function automatic bit compare_tokens(
        input string label,
        ref rlc_token_t expected [0:MAX_TOKENS-1],
        input int expected_count,
        ref rlc_token_t got [0:MAX_TOKENS-1],
        input int got_count
    );
        bit local_ok;
        int idx;
        int mismatch_prints;

        local_ok = 1'b1;
        mismatch_prints = 0;

        if (expected_count != got_count) begin
            $display("[tb] %s count mismatch: got=%0d expected=%0d", label, got_count, expected_count);
            local_ok = 1'b0;
        end

        for (idx = 0; idx < expected_count && idx < got_count; idx++) begin
            if (expected[idx] !== got[idx]) begin
                local_ok = 1'b0;
                if (mismatch_prints < 8) begin
                    $display("[tb] %s token[%0d] mismatch: got=0x%016h expected=0x%016h",
                             label, idx, got[idx], expected[idx]);
                    $display("[tb]   got      term=%0b last=%0b run=%0d payload=0x%014h",
                             rlc_token_term(got[idx]), rlc_token_last(got[idx]),
                             rlc_token_run(got[idx]), rlc_token_payload(got[idx]));
                    $display("[tb]   expected term=%0b last=%0b run=%0d payload=0x%014h",
                             rlc_token_term(expected[idx]), rlc_token_last(expected[idx]),
                             rlc_token_run(expected[idx]), rlc_token_payload(expected[idx]));
                    mismatch_prints++;
                end
            end
        end

        if (local_ok) begin
            $display("[tb] %s pass", label);
        end
        return local_ok;
    endfunction

    task automatic print_tokens(
        input string label,
        ref rlc_token_t tokens [0:MAX_TOKENS-1],
        input int token_count,
        input int limit
    );
        int idx;
        int stop;

        stop = (token_count < limit) ? token_count : limit;
        for (idx = 0; idx < stop; idx++) begin
            $display("[tb] %s token[%0d] term=%0b last=%0b run=%0d payload=0x%014h full=0x%016h",
                     label, idx, rlc_token_term(tokens[idx]), rlc_token_last(tokens[idx]),
                     rlc_token_run(tokens[idx]), rlc_token_payload(tokens[idx]), tokens[idx]);
        end
        if (token_count > limit) begin
            $display("[tb] %s ... %0d more token(s)", label, token_count - limit);
        end
    endtask
endmodule

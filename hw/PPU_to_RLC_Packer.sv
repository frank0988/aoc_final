module PPU_to_RLC_Packer (
    input  logic        clk,
    input  logic        rst,

    // PPU scalar output stream
    input  logic        scalar_valid_i,
    output logic        scalar_ready_o,
    input  logic [7:0]  scalar_data_i,
    input  logic        scalar_last_i,
    input  logic [7:0]  pad_data_i,

    // RLC vector input stream: lane0 in [7:0], lane6 in [55:48].
    output logic [55:0] rlc_data_o,
    output logic        rlc_valid_o,
    input  logic        rlc_ready_i,
    output logic        rlc_last_o
);

    logic [55:0] pack_reg;
    logic [2:0]  pack_count;
    logic [55:0] pack_with_current;

    logic scalar_fire;
    logic rlc_fire;

    assign scalar_fire = scalar_valid_i && scalar_ready_o;
    assign rlc_fire    = rlc_valid_o && rlc_ready_i;

    // A new scalar can be accepted when the vector output register is empty,
    // or when the current vector is being accepted in this cycle.
    assign scalar_ready_o = !rlc_valid_o || rlc_ready_i;

    // Place the earliest scalar in lane0, matching the RLC packet spec.
    always_comb begin
        pack_with_current = pack_reg;
        case (pack_count)
            3'd0: pack_with_current[7:0]   = scalar_data_i;
            3'd1: pack_with_current[15:8]  = scalar_data_i;
            3'd2: pack_with_current[23:16] = scalar_data_i;
            3'd3: pack_with_current[31:24] = scalar_data_i;
            3'd4: pack_with_current[39:32] = scalar_data_i;
            3'd5: pack_with_current[47:40] = scalar_data_i;
            3'd6: pack_with_current[55:48] = scalar_data_i;
            default: pack_with_current = pack_reg;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pack_reg    <= {7{pad_data_i}};
            pack_count  <= 3'd0;
            rlc_data_o  <= 56'd0;
            rlc_valid_o <= 1'b0;
            rlc_last_o  <= 1'b0;
        end else begin
            // Clear only after the encoder accepts the vector. A new vector may
            // replace it in the same cycle through the scalar_fire block below.
            if (rlc_fire) begin
                rlc_valid_o <= 1'b0;
                rlc_last_o  <= 1'b0;
            end

            if (scalar_fire) begin
                if ((pack_count == 3'd6) || scalar_last_i) begin
                    // Full vector, or final partial vector. Unused bytes keep
                    // pad_data_i so qint8 partial vectors use the output zero-point.
                    rlc_data_o  <= pack_with_current;
                    rlc_valid_o <= 1'b1;
                    rlc_last_o  <= scalar_last_i;

                    pack_reg   <= {7{pad_data_i}};
                    pack_count <= 3'd0;
                end else begin
                    pack_reg   <= pack_with_current;
                    pack_count <= pack_count + 3'd1;
                end
            end
        end
    end

endmodule

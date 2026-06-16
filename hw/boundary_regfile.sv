module boundary_regfile #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 10,
    parameter int DEPTH  = 1 << ADDR_W
)(
    input  logic                         clk,
    input  logic                         rst,  // active-high asynchronous reset

    // Synchronous read request/response.
    // Request is sampled on a rising edge. The response is available during
    // the following cycle with rd_rsp_valid asserted.
    input  logic                         rd_en,
    input  logic        [ADDR_W-1:0]     rd_addr,
    output logic                         rd_rsp_valid,
    output logic                         rd_entry_valid,
    output logic signed [DATA_W-1:0]     rd_data,

    // Synchronous write port
    input  logic                         wr_en,
    input  logic        [ADDR_W-1:0]     wr_addr,
    input  logic signed [DATA_W-1:0]     wr_data,

    // Clear only the valid bit after a stored boundary psum is consumed
    input  logic                         clear_en,
    input  logic        [ADDR_W-1:0]     clear_addr
);

    logic signed [DATA_W-1:0] mem       [0:DEPTH-1];
    logic                     valid_mem [0:DEPTH-1];

    integer i;

    // ============================================================
    // Synchronous read
    // ============================================================
    // If rd_en is high before a rising edge, rd_data/rd_entry_valid are
    // registered at that edge and rd_rsp_valid is asserted for the next cycle.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_rsp_valid   <= 1'b0;
            rd_entry_valid <= 1'b0;
            rd_data        <= '0;
        end else begin
            rd_rsp_valid <= rd_en;

            if (rd_en) begin
                rd_data        <= mem[rd_addr];
                rd_entry_valid <= valid_mem[rd_addr];
            end else begin
                rd_entry_valid <= 1'b0;
            end
        end
    end

    // ============================================================
    // Write / clear valid control
    // ============================================================
    // Different addresses may be written and cleared in the same cycle.
    // If the addresses collide, write wins so newly written data remains valid.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Data does not need reset because every read is qualified by
            // valid_mem. Clearing only valid bits reduces unnecessary reset logic.
            for (i = 0; i < DEPTH; i = i + 1) begin
                valid_mem[i] <= 1'b0;
            end
        end else begin
            // Suppress clear on a same-address write/clear collision.
            if (clear_en && !(wr_en && (wr_addr == clear_addr))) begin
                valid_mem[clear_addr] <= 1'b0;
            end

            if (wr_en) begin
                mem[wr_addr]       <= wr_data;
                valid_mem[wr_addr] <= 1'b1;
            end
        end
    end

endmodule

module ReLU_Qint8 (
    input en,
    input [7:0] data_in,
    output logic [7:0] data_out
);

    // ==========================================
    // 1. Hardware-friendly 判斷正負號
    // ==========================================
    // 在 Zero Point = 128 (8'b1000_0000) 的系統中：
    // MSB (bit 7) 為 1 代表 >= 128 (正數)
    // MSB (bit 7) 為 0 代表 < 128  (負數)
    logic is_positive;
    assign is_positive = data_in[7];

    // ==========================================
    // 2. ReLU 邏輯
    // ==========================================
    // 如果是正數，保持原數值；如果是負數，將其鉗制為 Zero Point (128)
    // 使用簡單的多工器 (MUX) 取代比較器
    logic [7:0] relu_result;
    assign relu_result = is_positive ? data_in : 8'b1000_0000;

    // ==========================================
    // 3. Enable 模組開關控制
    // ==========================================
    // 根據講義指示：*_en indicates whether the submodule is enabled.
    // 若 en 為 1，輸出 ReLU 的結果；若為 0，則 Bypass 輸出原始資料。
    assign data_out = en ? relu_result : data_in;

endmodule
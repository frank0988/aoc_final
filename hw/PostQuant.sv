`include "define.svh"
module PostQuant (
    input [`DATA_BITS-1:0] data_in,
    input [5:0] scaling_factor,
    output logic [7:0] data_out
);

    // ==========================================
    // 1. Scaling (縮放): 等效於除以 2^n
    // ==========================================
    // 使用算術右移 (>>>) 來保留符號位元
    logic signed [`DATA_BITS-1:0] scaled_data;
    assign scaled_data = $signed(data_in) >>> scaling_factor;

    // ==========================================
    // 2. 邊界偵測 (Bounds Detection)
    // ==========================================
    // 要將資料 Clamp 到 uint8 (0~255)，對應尚未加 Zero Point 的範圍是 [-128, 127]。
    // 在二進位中，一個數字若落在 [-128, 127] 內，其第 7 bit 到最高 bit 必須「全為 0」或「全為 1」。
    logic sign;
    assign sign = scaled_data[`DATA_BITS-1]; // 擷取符號位元 (0為正，1為負)

    logic all_zeros, all_ones;
    assign all_zeros = ~(|scaled_data[`DATA_BITS-1 : 7]); // Bit 31~7 全為 0
    assign all_ones  = &scaled_data[`DATA_BITS-1 : 7];  // Bit 31~7 全為 1

    logic in_bounds, out_bounds;
    assign in_bounds  = all_zeros | all_ones;
    assign out_bounds = ~in_bounds;

    // ==========================================
    // 3. Zero-Point 加法與飽和值設定 (無加法器設計)
    // ==========================================
    // 目標轉為 uint8，Zero point 為 128。
    // 對一個 [-128, 127] 的二補數加上 128，等同於直接反轉其 MSB
    logic [7:0] base_val;
    assign base_val = scaled_data[7:0] ^ 8'b1000_0000; // 使用 XOR 反轉 MSB，取代加法器

    // 如果發生溢位，正數(sign=0)要截斷成 255 (8'b1111_1111)，負數(sign=1)要截斷成 0 (8'b0)
    // 恰好可以用 ~sign 擴充成 8 bits 來達成！
    logic [7:0] sat_val;
    assign sat_val = {8{~sign}}; 

    // ==========================================
    // 4. Clamping 輸出 (無比較器/分支設計)
    // ==========================================
    // 利用 Bitwise AND/OR 來實現硬體 MUX，不使用 if-else 
    assign data_out = ({8{in_bounds}} & base_val) | ({8{out_bounds}} & sat_val);
    

endmodule

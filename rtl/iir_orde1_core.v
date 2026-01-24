`timescale 1ns/1ps

module iir_orde1_core #(
    parameter integer ACC_W = 64
)(
    input  wire clk,
    input  wire rst,
    input  wire en, 
    input  wire clear_state,

    input  wire signed [15:0] x_in,
    output reg  signed [15:0] y_out,

    input  wire signed [15:0] a0,
    input  wire signed [15:0] a1,
    input  wire signed [15:0] b1
);

    reg signed [15:0] x1;
    reg signed [15:0] y1;
    
    // Gunakan variabel sementara untuk logika kombinatorial
    reg signed [ACC_W-1:0] acc_comb;
    reg signed [15:0]      y_next;

    always @(posedge clk) begin
        if (rst) begin
            x1    <= 0;
            y1    <= 0;
            y_out <= 0;
        end else if (en) begin
            if (clear_state) begin
                x1    <= 0;
                y1    <= 0;
                y_out <= 0;
            end else begin
                // -----------------------------------------------------------
                // 1. Hitung MAC (Blocking =). Hitung SEKARANG.
                // -----------------------------------------------------------
                acc_comb = $signed(x_in) * a0 +
                           $signed(x1)   * a1 +
                           $signed(y1)   * b1; 

                // -----------------------------------------------------------
                // 2. Saturasi (Blocking =). Hitung dari hasil MAC di atas.
                // -----------------------------------------------------------
                // Cek overflow pada domain Q1.15 (setelah geser 15 bit)
                if ((acc_comb >>> 15) > 32767)
                    y_next = 16'sd32767;
                else if ((acc_comb >>> 15) < -32768)
                    y_next = -16'sd32768;
                else
                    y_next = acc_comb[30:15]; // Ambil bit data

                // -----------------------------------------------------------
                // 3. Update Output & State (Non-Blocking <=).
                //    Gunakan nilai 'y_next' yang BARU SAJA dihitung.
                // -----------------------------------------------------------
                y_out <= y_next;
                
                x1 <= x_in;
                y1 <= y_next; // Feedback sekarang sinkron & tepat waktu
            end
        end
    end

endmodule
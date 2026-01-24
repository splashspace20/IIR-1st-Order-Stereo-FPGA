`timescale 1ns/1ps

// ============================================================================
// tb_iir_orde1_core
// ---------------------------------------------------------------------------
// Testbench for the 1st-order IIR filter core (sample-by-sample processing).
//
// This testbench verifies:
// - Internal state handling and reset behavior
// - Step response of a low-pass configuration
// - Steady-state sine response at 100 Hz (fs = 48 kHz)
//
// Output samples are written to text files for offline plotting and analysis.
// ============================================================================

module tb_iir_orde1_core;

    // =========================================================================
    // Parameters
    // =========================================================================
    // Clock period corresponding to ~48 kHz sample rate
    localparam CLK_PERIOD = 20833; // ns (1 / 48 kHz ≈ 20.833 us)

    reg clk;
    reg rst;
    reg en;
    reg clear_state;

    reg  signed [15:0] x_in;
    wire signed [15:0] y_out;

    // IIR coefficients (Q1.15 format)
    reg signed [15:0] a0;
    reg signed [15:0] a1;
    reg signed [15:0] b1;

    // =========================================================================
    // DUT
    // =========================================================================
    iir_orde1_core dut (
        .clk        (clk),
        .rst        (rst),
        .en         (en),
        .clear_state(clear_state),
        .x_in       (x_in),
        .y_out      (y_out),
        .a0         (a0),
        .a1         (a1),
        .b1         (b1)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Test Sequence
    // =========================================================================
    integer i;
    real    phase;
    real    sine;
    integer fd_step;
    integer fd_sine;

    initial begin
        $display("=== TB IIR ORDE-1 START ===");

        // ---------------------------------------------------------------------
        // Initial conditions
        // ---------------------------------------------------------------------
        i           = 0;
        clk         = 0;
        rst         = 1;
        en          = 0;
        clear_state = 0;
        x_in        = 0;

        fd_step = $fopen("step_response.txt", "w");
        fd_sine = $fopen("sine_response.txt", "w");

        // ---------------------------------------------------------------------
        // Low-pass filter example (fc ≈ 100 Hz @ 48 kHz)
        //
        // y[n] = a0*x[n] + b1*y[n-1]
        // a0 = alpha
        // b1 = (1 - alpha)
        // ---------------------------------------------------------------------
        a0 = 16'sd426;     // 0.013 * 32768
        a1 = 16'sd0;
        b1 = 16'sd32342;  // (1 - 0.013) * 32768

        // Allow some time before releasing reset
        #(10 * CLK_PERIOD);

        rst = 0;
        en  = 1;

        // ---------------------------------------------------------------------
        // Clear internal state before first test
        // ---------------------------------------------------------------------
        clear_state = 1;
        #CLK_PERIOD;
        clear_state = 0;

        // =====================================================================
        // TEST 1: Step Response
        // =====================================================================
        $display("=== STEP RESPONSE ===");

        // Ensure zero input before step
        x_in = 0;
        repeat (50) @(posedge clk);

        // Apply step synchronously
        @(posedge clk);
        x_in = 16'sd16000;

        // Allow pipeline / feedback to settle
        repeat (5) @(posedge clk);

        // Log step response
        repeat (200) begin
            @(posedge clk);
            $display("STEP | x=%d | y=%d", x_in, y_out);
            $fwrite(fd_step, "%0d\n", y_out);
        end

        // ---------------------------------------------------------------------
        // Clear internal state before next test
        // ---------------------------------------------------------------------
        clear_state = 1;
        #CLK_PERIOD;
        clear_state = 0;

        // =====================================================================
        // TEST 2: Sine Response (100 Hz)
        // =====================================================================
        $display("=== SINE 100 Hz ===");

        phase = 0.0;
        for (i = 0; i < 400; i = i + 1) begin
            sine  = $sin(phase);
            x_in  = $rtoi(sine * 16000);
            phase = phase + 2.0 * 3.141592 * 100.0 / 48000.0;

            @(posedge clk);
            $display("SINE | x=%d | y=%d", x_in, y_out);
            $fwrite(fd_sine, "%0d %0d\n", x_in, y_out);
        end

        // =====================================================================
        // End of Simulation
        // =====================================================================
        $display("=== TB DONE ===");

        $fclose(fd_step);
        $fclose(fd_sine);
        $finish;
    end

endmodule

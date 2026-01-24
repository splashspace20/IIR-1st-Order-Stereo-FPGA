`timescale 1ns / 1ps

module iir_orde1_axis_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4,
    parameter integer DATA_WIDTH         = 32  // Fixed 32-bit (2x16) for Stereo
)(
    // Global Clock & Reset
    input wire  aclk,
    input wire  aresetn, // Active Low

    // ---------------------------------------------------------------------
    // AXI4-Stream Slave Interface (Input Data)
    // Format: [31:16] = Left Channel, [15:0] = Right Channel
    // ---------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    // ---------------------------------------------------------------------
    // AXI4-Stream Master Interface (Output Data)
    // ---------------------------------------------------------------------
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,
    output reg                   m_axis_tlast,

    // ---------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Control & Coefficients)
    // ---------------------------------------------------------------------
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,
    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready
);

    // =========================================================================
    // 1. Internal Parameters & Signals
    // =========================================================================
    
    // Register Map (Shared for both channels)
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_ctrl; // 0x00
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_a0;   // 0x04
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_a1;   // 0x08
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_b1;   // 0x0C

    // AXI-Lite Handshake Signals
    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg axi_rvalid;
    
    reg aw_en; 

    // I/O Connections
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = 2'b00; 
    assign s_axi_rvalid  = axi_rvalid;

    // =========================================================================
    // 2. AXI-Lite Write Logic (Independent AW/W, simplified single outstanding transaction)
    // =========================================================================
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b0;
            aw_en       <= 1'b1;
            reg_ctrl    <= 32'h0000_0001; // Default Enable=1
            reg_a0      <= 32'd0;
            reg_a1      <= 32'd0;
            reg_b1      <= 32'd0;
        end else begin
            // Address Handshake
            if (~axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0; 
            end else if (~axi_awready && s_axi_awvalid && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end

            // Data Handshake
            if (~axi_wready && s_axi_wvalid && s_axi_awvalid && aw_en) begin
                 axi_wready <= 1'b1;
            end else if (~axi_wready && s_axi_wvalid && (axi_awready || ~aw_en)) begin
                 axi_wready <= 1'b1;
            end else begin
                 axi_wready <= 1'b0;
            end

            // Register Update
            if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid && ~axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
                case (s_axi_awaddr[3:2])
                    2'h0: reg_ctrl <= s_axi_wdata;
                    2'h1: reg_a0   <= s_axi_wdata;
                    2'h2: reg_a1   <= s_axi_wdata;
                    2'h3: reg_b1   <= s_axi_wdata;
                    default: ;
                endcase
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
                if (s_axi_awvalid && axi_awready) 
                    aw_en <= 1'b0; 
                else
                    aw_en <= 1'b1;
            end else begin
                if ((axi_awready && s_axi_awvalid) && ~axi_bvalid) 
                    aw_en <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 3. AXI-Lite Read Logic
    // =========================================================================
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'd0;
        end else begin
            if (~axi_arready && s_axi_arvalid)
                axi_arready <= 1'b1;
            else
                axi_arready <= 1'b0;

            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                case (s_axi_araddr[3:2])
                    2'h0: axi_rdata <= reg_ctrl;
                    2'h1: axi_rdata <= reg_a0;
                    2'h2: axi_rdata <= reg_a1;
                    2'h3: axi_rdata <= reg_b1;
                    default: axi_rdata <= 32'd0;
                endcase
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 4. Dual Channel IIR Instantiation (STEREO)
    // =========================================================================
    wire core_reset;
    wire core_enable_signal;
    wire soft_clear;
    wire soft_enable_bit;
    
    // Control Signal Decoding
    assign soft_enable_bit = reg_ctrl[0];
    assign soft_clear      = reg_ctrl[1];
    assign core_reset      = ~aresetn; 

    // Handshake: Same as mono, since both L/R processed in lockstep
    wire axis_handshake_ok;
    assign axis_handshake_ok = s_axis_tvalid && (m_axis_tready || !m_axis_tvalid);
    
    // Core Enable
    assign core_enable_signal = axis_handshake_ok && soft_enable_bit;
    assign s_axis_tready      = (m_axis_tready || !m_axis_tvalid) && soft_enable_bit;

    // --- SPLIT DATA ---
    // Latency: 1 clock cycle from input sample to output sample (per channel)
    wire signed [15:0] data_in_L = s_axis_tdata[31:16]; // High Word
    wire signed [15:0] data_in_R = s_axis_tdata[15:0];  // Low Word

    wire signed [15:0] data_out_L;
    wire signed [15:0] data_out_R;

    // --- LEFT CHANNEL CORE ---
    iir_orde1_core #( .ACC_W(64) ) inst_core_left (
        .clk        (aclk),
        .rst        (core_reset),
        .en         (core_enable_signal),
        .clear_state(soft_clear),
        .x_in       (data_in_L),
        .y_out      (data_out_L),
        .a0         (reg_a0[15:0]),
        .a1         (reg_a1[15:0]),
        .b1         (reg_b1[15:0])
    );

    // --- RIGHT CHANNEL CORE ---
    iir_orde1_core #( .ACC_W(64) ) inst_core_right (
        .clk        (aclk),
        .rst        (core_reset),
        .en         (core_enable_signal),
        .clear_state(soft_clear),
        .x_in       (data_in_R),
        .y_out      (data_out_R),
        .a0         (reg_a0[15:0]), // Shared Coefficient
        .a1         (reg_a1[15:0]), // Shared Coefficient
        .b1         (reg_b1[15:0])  // Shared Coefficient
    );

    // =========================================================================
    // 5. Output Logic (Combine L/R)
    // =========================================================================
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            if (m_axis_tready || !m_axis_tvalid) begin
                m_axis_tvalid <= s_axis_tvalid && soft_enable_bit;
                m_axis_tlast  <= s_axis_tlast;
            end
        end
    end
    
    // Packing ulang Output: [31:16] L, [15:0] R
    assign m_axis_tdata = {data_out_L, data_out_R};

endmodule
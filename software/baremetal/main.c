#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "xil_types.h"
#include "xil_io.h"
#include "xparameters.h"
#include "xaxidma.h"
#include "xil_printf.h"
#include "xil_cache.h"

// ============================================================================
// Hardware Address Definitions
// ============================================================================
// NOTE:
// Base addresses must match the Vivado Address Editor configuration.
// Update these values according to the generated system.xsa file.

#define IIR_BASE_ADDR       0xA0010000  // Stereo IIR filter AXI-Lite base address
#define DMA_BASE_ADDR       0xA0000000  // AXI DMA base address (reserved)
#define DMA_DEV_ID          0

// IIR register offsets
#define REG_CTRL_OFFSET     0x00
#define REG_A0_OFFSET       0x04
#define REG_A1_OFFSET       0x08
#define REG_B1_OFFSET       0x0C

// DMA buffer configuration (DDR memory)
#define MEM_BASE_ADDR       0x10000000
#define RX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00100000) // RX buffer offset
#define TX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00200000) // TX buffer offset
#define TEST_LENGTH         128                          // Number of samples

XAxiDma AxiDma;

// ============================================================================
// IIR Control Functions
// ============================================================================

/**
 * @brief Configure IIR coefficients (Q1.15 format).
 *
 * @param a0 Feedforward coefficient a0 (floating-point)
 * @param a1 Feedforward coefficient a1 (floating-point)
 * @param b1 Feedback coefficient b1 (floating-point)
 */
void IIR_Set_Coefficients(float a0, float a1, float b1)
{
    // Convert floating-point to Q1.15 fixed-point
    int16_t a0_fixed = (int16_t)(a0 * 32768.0f);
    int16_t a1_fixed = (int16_t)(a1 * 32768.0f);
    int16_t b1_fixed = (int16_t)(b1 * 32768.0f);

    Xil_Out32(IIR_BASE_ADDR + REG_A0_OFFSET, a0_fixed);
    Xil_Out32(IIR_BASE_ADDR + REG_A1_OFFSET, a1_fixed);
    Xil_Out32(IIR_BASE_ADDR + REG_B1_OFFSET, b1_fixed);

    xil_printf("Coefficients updated: A0=%d, A1=%d, B1=%d\r\n",
               a0_fixed, a1_fixed, b1_fixed);
}

/**
 * @brief Enable or clear the IIR filter core.
 *
 * Control register bits:
 *  bit[0] : Enable
 *  bit[1] : Clear internal state
 *
 * @param enable Enable filter processing
 * @param clear  Clear internal state
 */
void IIR_Enable(u8 enable, u8 clear)
{
    u32 val = 0;
    if (enable) val |= 0x01;
    if (clear)  val |= 0x02;

    Xil_Out32(IIR_BASE_ADDR + REG_CTRL_OFFSET, val);
}

// ============================================================================
// Main Application
// ============================================================================

int main(void)
{
    // Enable instruction and data caches
    Xil_ICacheEnable();
    Xil_DCacheEnable();

    xil_printf("\r\n--- Stereo IIR Filter Test on Kria KV260 ---\r\n");

    // ------------------------------------------------------------------------
    // Initialize AXI DMA
    // ------------------------------------------------------------------------
    XAxiDma_Config *CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (!CfgPtr) {
        xil_printf("ERROR: DMA configuration not found\r\n");
        return XST_FAILURE;
    }

    int Status = XAxiDma_CfgInitialize(&AxiDma, CfgPtr);
    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: DMA initialization failed\r\n");
        return XST_FAILURE;
    }

    // Disable DMA interrupts (polling mode)
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK,
                        XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK,
                        XAXIDMA_DMA_TO_DEVICE);

    // ------------------------------------------------------------------------
    // Prepare test data (stereo impulse)
    // ------------------------------------------------------------------------
    u32 *TxBufferPtr = (u32 *)TX_BUFFER_BASE;
    u32 *RxBufferPtr = (u32 *)RX_BUFFER_BASE;

    // Clear RX buffer
    memset((void *)RX_BUFFER_BASE, 0, TEST_LENGTH * sizeof(u32));

    // Generate stereo impulse: {Left=10000, Right=10000}
    TxBufferPtr[0] = (10000 << 16) | (10000 & 0xFFFF);
    for (int i = 1; i < TEST_LENGTH; i++) {
        TxBufferPtr[i] = 0x00000000;
    }

    // Flush cache to ensure DMA sees latest data
    Xil_DCacheFlushRange((UINTPTR)TxBufferPtr, TEST_LENGTH * sizeof(u32));
    Xil_DCacheFlushRange((UINTPTR)RxBufferPtr, TEST_LENGTH * sizeof(u32));

    // ------------------------------------------------------------------------
    // Configure IIR filter (first-order low-pass)
    // ------------------------------------------------------------------------
    IIR_Enable(1, 1);                    // Enable + clear state
    IIR_Set_Coefficients(0.5f, 0.0f, 0.5f);
    IIR_Enable(1, 0);                    // Enable processing

    xil_printf("Filter configured via AXI-Lite\r\n");

    // ------------------------------------------------------------------------
    // Start DMA transfers
    // ------------------------------------------------------------------------
    // Start RX (S2MM) first
    Status = XAxiDma_SimpleTransfer(&AxiDma,
                (UINTPTR)RxBufferPtr,
                TEST_LENGTH * sizeof(u32),
                XAXIDMA_DEVICE_TO_DMA);
    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: DMA RX transfer failed\r\n");
        return XST_FAILURE;
    }

    // Start TX (MM2S)
    Status = XAxiDma_SimpleTransfer(&AxiDma,
                (UINTPTR)TxBufferPtr,
                TEST_LENGTH * sizeof(u32),
                XAXIDMA_DMA_TO_DEVICE);
    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: DMA TX transfer failed\r\n");
        return XST_FAILURE;
    }

    // Poll until DMA transfers complete
    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE) ||
           XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA)) {
        // Busy wait
    }

    // Invalidate RX buffer cache before CPU access
    Xil_DCacheInvalidateRange((UINTPTR)RxBufferPtr,
                              TEST_LENGTH * sizeof(u32));

    // ------------------------------------------------------------------------
    // Inspect output samples
    // ------------------------------------------------------------------------
    xil_printf("\r\n--- DMA Transfer Complete ---\r\n");
    for (int i = 0; i < 10; i++) {
        int16_t left_out  = (int16_t)(RxBufferPtr[i] >> 16);
        int16_t right_out = (int16_t)(RxBufferPtr[i] & 0xFFFF);

        xil_printf("Sample[%d]: L=%d, R=%d\r\n",
                   i, left_out, right_out);
    }

    return 0;
}

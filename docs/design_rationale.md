## Design Rationale

### AXI-Lite–Controlled Coefficients (Not Hardcoded)

Filter coefficients (`A0`, `A1`, `B1`) are intentionally exposed through **AXI-Lite registers**
instead of being hardcoded in RTL.

This design choice provides several advantages:

- **Runtime configurability**  
  Coefficients can be updated without resynthesizing or regenerating the bitstream.

- **Reuse as a generic DSP building block**  
  The same RTL can implement low-pass, high-pass, or other first-order responses
  depending on the coefficients provided by the user.

- **Clean hardware–software separation**  
  The RTL focuses purely on deterministic DSP execution, while coefficient selection
  and tuning are handled externally.

This approach makes the IP suitable for integration into larger systems where
coefficients may be loaded at boot, adjusted during calibration, or controlled by
higher-level software.

---

### No Built-In Coefficient Generator

This repository intentionally **does not include a coefficient generator**
(e.g. Python, MATLAB, or script-based tools).

The rationale is:

- **Avoid toolchain coupling**  
  Users are free to generate coefficients using any environment:
  Python, MATLAB, Octave, spreadsheets, or hand-calculated fixed-point values.

- **Keep the repository focused on RTL architecture**  
  The primary goal is to demonstrate a clean, verifiable, and reusable FPGA DSP
  implementation—not a specific DSP design workflow.

- **Maximize flexibility**  
  Different projects may require different numerical models, scaling rules, or
  design constraints. By not prescribing a coefficient-generation method, the IP
  remains adaptable to diverse use cases.

The only requirement is that coefficients are provided in **Q1.15 fixed-point format**,
which is explicitly documented.

---

### Role of the Bare-Metal Application

The included bare-metal Vitis application serves as a **minimal reference** to demonstrate:

- AXI-Lite register access
- AXI DMA data movement
- Cache flush / invalidate handling
- End-to-end connectivity between software and RTL

It is **not** the primary focus of this repository.

The core value of this project lies in:

- the **RTL architecture**,
- the **AXI integration pattern**, and
- the **deterministic DSP behavior** verified at RTL level.

Users are expected to adapt or replace the software layer according to their own
system architecture (bare-metal, RTOS, or Linux-based).

> This repository prioritizes architectural clarity and RTL correctness over
> application-level completeness.

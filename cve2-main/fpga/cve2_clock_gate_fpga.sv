// FPGA replacement for cve2_clock_gate.sv (which is a latch-based simulation model).
// Gating a clock with LUT logic is bad practice on an FPGA (skew, no global clock tree),
// so the "gate" is a plain feed-through: the core simply never stops its clock.
// Same module name and ports as the original, so cve2_core.sv needs no change.
module cve2_clock_gate (
    input  logic clk_i,
    input  logic en_i,
    input  logic scan_cg_en_i,
    output logic clk_o
);
  logic unused_en;
  assign unused_en = en_i ^ scan_cg_en_i;
  assign clk_o     = clk_i;
endmodule
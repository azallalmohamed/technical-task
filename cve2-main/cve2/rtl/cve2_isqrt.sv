// Custom-0 "isqrt" execution unit for CVE2.
//
//   isqrt rd, rs1      rd = floor(sqrt(rs1)),  rs1 unsigned 32 bit, result 0..65535
//
// Algorithm: classic digit-by-digit (restoring) square root, identical to the
// C reference model isqrt_ref() in sw/lib/isqrt.h. One result bit is produced
// per iteration, MSB first:
//
//   rem  = (rem << 2) | next two bits of the radicand
//   trial = (root << 2) | 1
//   root <<= 1
//   if (rem >= trial) { rem -= trial; root |= 1 }
//
// Only a small 18-bit subtractor, a 32-bit shift register and two short
// registers are needed; the unit does not use the main ALU adder, so it adds
// no logic to the ALU critical path.
//
// Handshake (mirrors cve2_multdiv_fast so the ID-stage multi-cycle logic can be reused):
//   * en_i is asserted by the ID stage for as long as an isqrt instruction is
//     being executed (dynamic enable: it drops on a flush, which aborts the op).
//   * valid_o is high for exactly one cycle when result_o is correct; the ID
//     stage then writes rd and retires the instruction in that very cycle.
//
// Latency seen by the ID stage = 1 (operand capture) + 16/ITER_PER_CYCLE
// (iterations) + 1 (result cycle) cycles.

module cve2_isqrt #(
  // Number of digit iterations unrolled per clock cycle: 1, 2, 4, 8 or 16.
  // 1 = smallest/fastest clock (18 cycles), larger = fewer cycles, longer path.
  parameter int unsigned ITER_PER_CYCLE = 1
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        en_i,        // dynamic enable from the ID stage
  input  logic [31:0] operand_i,   // rs1 (unsigned)

  output logic        valid_o,     // result_o is valid in this cycle
  output logic [31:0] result_o
);

  localparam int unsigned NumIter  = 16;
  localparam int unsigned NumSteps = NumIter / ITER_PER_CYCLE;

  typedef enum logic [1:0] {
    ST_IDLE,   // waiting for an isqrt instruction; operand is captured when en_i is seen
    ST_RUN,    // iterating
    ST_DONE    // result valid for one cycle
  } isqrt_state_e;

  isqrt_state_e state_q, state_d;

  logic [31:0] x_q,    x_d;      // remaining radicand bits (shifted left by 2 each iteration)
  logic [17:0] rem_q,  rem_d;    // partial remainder (< 2*root+1, fits in 18 bits)
  logic [15:0] root_q, root_d;   // partial root, final result after 16 iterations
  logic [4:0]  step_q, step_d;   // iteration-group counter

  // ---------------------------------------------------------------------------
  // Combinational: ITER_PER_CYCLE digit iterations chained
  // ---------------------------------------------------------------------------
  logic [31:0] x_it;
  logic [17:0] rem_it;
  logic [15:0] root_it;

  always_comb begin
    x_it    = x_q;
    rem_it  = rem_q;
    root_it = root_q;
    for (int unsigned i = 0; i < ITER_PER_CYCLE; i++) begin
      logic [17:0] rem_sh;
      logic [17:0] trial;
      rem_sh  = {rem_it[15:0], x_it[31:30]};
      x_it    = {x_it[29:0], 2'b00};
      trial   = {root_it[15:0], 2'b01};      // (root << 2) | 1, root < 2^16 -> 18 bits
      if (rem_sh >= trial) begin
        rem_it  = rem_sh - trial;
        root_it = {root_it[14:0], 1'b1};
      end else begin
        rem_it  = rem_sh;
        root_it = {root_it[14:0], 1'b0};
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Control FSM
  // ---------------------------------------------------------------------------
  always_comb begin
    state_d = state_q;
    x_d     = x_q;
    rem_d   = rem_q;
    root_d  = root_q;
    step_d  = step_q;

    unique case (state_q)
      ST_IDLE: begin
        if (en_i) begin
          // Capture rs1 and clear the accumulators. Capturing makes the unit
          // independent of the register-file read port during the iterations.
          x_d     = operand_i;
          rem_d   = '0;
          root_d  = '0;
          step_d  = '0;
          state_d = ST_RUN;
        end
      end

      ST_RUN: begin
        x_d    = x_it;
        rem_d  = rem_it;
        root_d = root_it;
        step_d = step_q + 5'd1;
        if (step_q == 5'(NumSteps - 1)) state_d = ST_DONE;
      end

      ST_DONE: begin
        // Result is presented this cycle; ID stage retires the instruction.
        state_d = ST_IDLE;
      end

      default: state_d = ST_IDLE;
    endcase

    // A flush/abort (en_i low) at any time returns the unit to idle.
    // (The instruction will be re-executed from scratch if it is replayed.)
    if (!en_i) state_d = ST_IDLE;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_IDLE;
      x_q     <= '0;
      rem_q   <= '0;
      root_q  <= '0;
      step_q  <= '0;
    end else begin
      state_q <= state_d;
      x_q     <= x_d;
      rem_q   <= rem_d;
      root_q  <= root_d;
      step_q  <= step_d;
    end
  end

  assign valid_o  = (state_q == ST_DONE) & en_i;
  assign result_o = {16'b0, root_q};

  logic unused_x;
  assign unused_x = ^x_q[31:0]; // keep lint quiet about trailing bits

endmodule

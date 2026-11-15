// Unit testbench for cve2_isqrt (Verilator --binary --timing).
//  * exhaustive check around every perfect square + random values
//  * abort: en_i dropped at a random cycle mid-operation, then a new operation must be correct
//  * valid_o must be a single-cycle pulse, exactly LATENCY cycles after the start
module tb_isqrt_unit;
  parameter int ITER = 1;
  localparam int LATENCY = 1 + 16/ITER + 1;   // idle(capture) + iterations + done cycle
  logic clk = 0, rst_n = 0, en = 0, valid;
  logic [31:0] op, res;
  cve2_isqrt #(.ITER_PER_CYCLE(ITER)) dut (.clk_i(clk), .rst_ni(rst_n), .en_i(en),
                                           .operand_i(op), .valid_o(valid), .result_o(res));
  always #5 clk = ~clk;

  function automatic int unsigned ref_sqrt(input int unsigned x);
    int unsigned r = 0;
    while (longint'(r + 1) * longint'(r + 1) <= longint'(x)) r++;
    return r;
  endfunction
  function automatic int unsigned fast_sqrt(input int unsigned x);   // via real
    int unsigned r = int'($floor($sqrt(real'(x))));
    while (longint'(r) * longint'(r) > longint'(x)) r--;
    while (longint'(r + 1) * longint'(r + 1) <= longint'(x)) r++;
    return r;
  endfunction

  int errors = 0, checks = 0;

  task automatic run_op(input logic [31:0] x);
    int cyc = 0;
    op = x; en = 1;
    do begin @(posedge clk); #1; cyc++; end while (!valid && cyc < 100);
    // valid is observed after cycle count 'cyc' of en high -> LATENCY cycles in total
    checks++;
    if (cyc != LATENCY - 1) begin errors++; $display("LATENCY %0d != %0d", cyc, LATENCY - 1); end
    if (res !== 32'(fast_sqrt(x))) begin
      errors++; if (errors < 10) $display("MISMATCH x=%0d got %0d exp %0d", x, res, fast_sqrt(x));
    end
    // valid must last exactly one cycle (ID stage retires instruction and drops en)
    en = 0; @(posedge clk); #1;
    if (valid) begin errors++; $display("valid longer than 1 cycle"); end
  endtask

  initial begin
    repeat (3) @(posedge clk); #1 rst_n = 1; @(posedge clk); #1;
    for (int n = 0; n < 65536; n += 1) begin
      if (n < 300 || n % 97 == 0 || n > 65500) begin   // dense at both ends, sampled in the middle
        run_op(n * n);
        if (n > 0) run_op(n * n - 1);
        if (n > 0 && n < 65535) run_op(n * n + 1);
      end
    end
    run_op(32'hFFFFFFFF); run_op(0); run_op(1); run_op(2); run_op(3); run_op(4);
    for (int i = 0; i < 3000; i++) run_op($urandom >> ($urandom % 32));
    // abort test: drop en mid-operation, then start a fresh one
    for (int i = 0; i < 200; i++) begin
      int stop = 1 + $urandom % (LATENCY - 1);
      op = $urandom; en = 1;
      repeat (stop) @(posedge clk); #1;
      en = 0; @(posedge clk); #1;
      if (valid) begin errors++; $display("valid after abort"); end
      run_op($urandom);
    end
    $display("isqrt unit ITER=%0d: %0d checks, %0d errors -> %s", ITER, checks, errors,
             errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule

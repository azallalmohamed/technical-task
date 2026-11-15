// FPGA top level for the CVE2
//
//   core (cve2_top, same configuration as tb/: MHPMCounterNum=0, RV32M=RV32MFast, RV32E=0)
//   + 16 KiB dual-port block RAM (instruction port + data port), zero-initialised
//   + one memory-mapped LED register at 0x1000_0000
//
// The memory handshake is the one used by tb/tb_mem.sv: gnt in the same cycle as req,
// rvalid/rdata one cycle later. Nothing here depends on the isqrt change, so the very
// same top is used for the "before" and "after" runs.
module cve2_fpga_top (
  input  logic       clk_i,       // board clock
  input  logic       btn_rst_i,   // push button, active high -> reset
  output logic [3:0] led_o
);
  import cve2_pkg::*;

  localparam int unsigned AW = 12;             // 4096 words = 16 KiB

  // ---- reset synchroniser (2 FF), core reset is active low ------------------
  logic [2:0] rst_sync_q = 3'b000;
  always_ff @(posedge clk_i or posedge btn_rst_i) begin
    if (btn_rst_i) rst_sync_q <= 3'b000;
    else           rst_sync_q <= {rst_sync_q[1:0], 1'b1};
  end
  logic rst_n;
  assign rst_n = rst_sync_q[2];

  // ---- core ---------------------------------------------------------------------
  logic        instr_req, instr_rvalid;
  logic [31:0] instr_addr, instr_rdata;
  logic        data_req, data_rvalid, data_we;
  logic [3:0]  data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;

  x_issue_resp_t x_issue_resp;
  x_result_t     x_result;
  assign x_issue_resp = '0;                    // CV-X-IF not used
  assign x_result     = '0;

  cve2_top #(
    .MHPMCounterNum   (0),
    .MHPMCounterWidth (40),
    .RV32E            (1'b0),
    .RV32M            (RV32MFast)
  ) u_core (
    .clk_i, .rst_ni(rst_n), .test_en_i(1'b0), .ram_cfg_i('0),
    .hart_id_i(32'h0), .boot_addr_i(32'h0000_0080),
    .instr_req_o(instr_req), .instr_gnt_i(instr_req), .instr_rvalid_i(instr_rvalid),
    .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata), .instr_err_i(1'b0),
    .data_req_o(data_req), .data_gnt_i(data_req), .data_rvalid_i(data_rvalid),
    .data_we_o(data_we), .data_be_o(data_be), .data_addr_o(data_addr),
    .data_wdata_o(data_wdata), .data_rdata_i(data_rdata), .data_err_i(1'b0),
    .x_issue_valid_o(), .x_issue_ready_i(1'b0), .x_issue_req_o(), .x_issue_resp_i(x_issue_resp),
    .x_register_o(), .x_commit_valid_o(), .x_commit_o(),
    .x_result_valid_i(1'b0), .x_result_ready_o(), .x_result_i(x_result),
    .irq_software_i(1'b0), .irq_timer_i(1'b0), .irq_external_i(1'b0),
    .irq_fast_i(16'h0), .irq_nm_i(1'b0),
    .debug_req_i(1'b0), .debug_halted_o(), .dm_halt_addr_i(32'h0),
    .dm_exception_addr_i(32'h0), .crash_dump_o(),
    .fetch_enable_i(1'b1), .core_sleep_o()
  );

  // ---- block RAM (true dual port: A = instructions, B = data) -----------------
  (* ram_style = "block" *) logic [31:0] mem [0:(1<<AW)-1];

  logic [31:0] instr_rdata_q, data_rdata_q;
  logic        instr_rvalid_q, data_rvalid_q;

  always_ff @(posedge clk_i) begin                   // port A: read only
    if (instr_req) instr_rdata_q <= mem[instr_addr[AW+1:2]];
  end

  wire mem_sel  = (data_addr[31:28] == 4'h0);       // RAM at 0x0..., LED reg at 0x1000_0000
  wire led_sel  = (data_addr[31:28] == 4'h1);
  always_ff @(posedge clk_i) begin                   // port B: byte-enable write + read
    if (data_req & mem_sel) begin
      if (data_we) begin
        for (int i = 0; i < 4; i++)
          if (data_be[i]) mem[data_addr[AW+1:2]][8*i +: 8] <= data_wdata[8*i +: 8];
      end
      data_rdata_q <= mem[data_addr[AW+1:2]];
    end
  end

  always_ff @(posedge clk_i or negedge rst_n) begin
    if (!rst_n) begin
      instr_rvalid_q <= 1'b0;
      data_rvalid_q  <= 1'b0;
      led_o          <= '0;
    end else begin
      instr_rvalid_q <= instr_req;
      data_rvalid_q  <= data_req;
      if (data_req & data_we & led_sel) led_o <= data_wdata[3:0];
    end
  end

  assign instr_rvalid = instr_rvalid_q;
  assign instr_rdata  = instr_rdata_q;
  assign data_rvalid  = data_rvalid_q;
  assign data_rdata   = data_rdata_q;
endmodule
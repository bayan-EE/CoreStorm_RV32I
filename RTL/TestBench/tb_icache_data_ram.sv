`timescale 1ns/1ps

module tb_icache_data_ram;

  timeunit 1ns;
  timeprecision 1ps;

  // -----------------------------
  // DUT signals
  // -----------------------------
  logic         clk_i;
  logic         rst_i;
  logic [9:0]   addr_i;
  logic [63:0]  data_i;
  logic         wr_i;
  logic [63:0]  data_o;

  // -----------------------------
  // Instantiate DUT
  // -----------------------------
  icache_data_ram dut (
	  .clk_i  (clk_i)
	, .rst_i  (rst_i)
	, .addr_i (addr_i)
	, .data_i (data_i)
	, .wr_i   (wr_i)
	, .data_o (data_o)
  );

  // -----------------------------
  // Clock gen
  // -----------------------------
  initial clk_i = 1'b0;
  always  #5 clk_i = ~clk_i; // 100MHz

  // -----------------------------
  // Waves
  // -----------------------------
  initial begin
`ifdef VCS
	$fsdbDumpfile("tb_icache_data_ram.fsdb");
	$fsdbDumpvars(0, tb_icache_data_ram);
`else
	$dumpfile("tb_icache_data_ram.vcd");
	$dumpvars(0, tb_icache_data_ram);
`endif
  end

  // -----------------------------
  // Scoreboard model (golden RAM)
  // -----------------------------
  logic [63:0] model_ram [0:1023];

  // We'll check synchronous read (1-cycle latency)
  logic [9:0]  addr_prev;
  logic        wr_prev;
  logic [63:0] data_prev;

  // Expected data_o in Read-First mode:
  // At cycle N posedge: output registers old model_ram[addr_i] (before write),
  // then write happens to model.
  logic [63:0] expected_q;

  // -----------------------------
  // Coverage
  // -----------------------------
  covergroup cg @(posedge clk_i);
	option.per_instance = 1;

	cp_wr   : coverpoint wr_i { bins rd = {0}; bins wr = {1}; }

	// Address coverage: low/mid/high + some random bins
	cp_addr : coverpoint addr_i {
	  bins low  = {[0:15]};
	  bins mid  = {[16:511]};
	  bins high = {[512:1023]};
	}

	// Data patterns (very rough but useful)
	cp_data_pat : coverpoint data_i {
	  bins all0   = {64'h0};
	  bins all1   = {64'hFFFF_FFFF_FFFF_FFFF};
	  bins alt01  = {64'hAAAA_AAAA_AAAA_AAAA};
	  bins alt10  = {64'h5555_5555_5555_5555};
	  bins other  = default;
	}

	// Cross write/read with address regions
	x_wr_addr : cross cp_wr, cp_addr;

	// Scenario: write same address back-to-back
	cp_same_addr : coverpoint (addr_i == addr_prev) {
	  bins same = {1};
	  bins diff = {0};
	}
	x_wr_sameaddr : cross cp_wr, cp_same_addr;

  endgroup

  cg cov = new();

  // -----------------------------
  // Random stimulus helper
  // -----------------------------
  function automatic logic [63:0] rand64();
	rand64 = { $urandom(), $urandom() };
  endfunction

  // -----------------------------
  // Reset + init
  // -----------------------------
  task automatic do_reset();
	  rst_i  = 1'b1;
	  addr_i = '0;
	  data_i = '0;
	  wr_i   = 1'b0;

	  repeat (3) @(posedge clk_i);
	  rst_i = 1'b0;
	  @(posedge clk_i);
	endtask

  // -----------------------------
  // Drive a single cycle
  // -----------------------------
  task automatic drive_cycle(input logic [9:0] a, input logic w, input logic [63:0] d);
	addr_i = a;
	wr_i   = w;
	data_i = d;
	@(posedge clk_i);
  endtask

  // -----------------------------
  // Self-checking at every clock
  // -----------------------------

  always_ff @(posedge clk_i) begin
	if (rst_i) begin
	  expected_q <= 64'h0;
	  addr_prev  <= '0;
	  wr_prev    <= 1'b0;
	  data_prev  <= 64'h0;

	  for (int i = 0; i < 1024; i++) begin
		model_ram[i] <= 64'h0;
	  end
	end
	else begin
	  // Read-first: output should reflect OLD memory contents at addr_i
	  expected_q <= model_ram[addr_i];

	  // Update golden model after taking expected
	  if (wr_i) begin
		model_ram[addr_i] <= data_i;
	  end

	  // Save previous cycle info (for coverage/debug)
	  addr_prev <= addr_i;
	  wr_prev   <= wr_i;
	  data_prev <= data_i;
	end
  end

  // data_o is ram_read_q, which updates at posedge as well.
  // Compare AFTER a tiny delay to avoid race with nonblocking updates.
  always @(posedge clk_i) begin
	if (!rst_i) begin
	  #1;
	  if (data_o !== expected_q) begin
		$error("DATA_RAM mismatch @%0t: addr=%0d wr=%0b data_i=%h | got=%h exp=%h",
			   $time, addr_i, wr_i, data_i, data_o, expected_q);
		$fatal(1);
	  end
	end
  end

  // -----------------------------
  // Directed tests + random test
  // -----------------------------
  initial begin
	  // -----------------------------
	  // Declarations MUST be first
	  // -----------------------------
	  int unsigned seed;
	  logic [9:0]  a;
	  logic        w;
	  logic [63:0] d;

	  // -----------------------------
	  // Now statements are allowed
	  // -----------------------------
	  do_reset();

	  // Directed 1
	  drive_cycle(10'd5, 1'b1, 64'h1122_3344_5566_7788);
	  drive_cycle(10'd5, 1'b0, 64'h0);

	  // Directed 2: read-first check
	  drive_cycle(10'd7, 1'b1, 64'hDEAD_BEEF_DEAD_BEEF);
	  drive_cycle(10'd7, 1'b0, 64'h0);

	  // Random test
	  seed = 32'hC0FFEE01;
	  void'($urandom(seed));

	  for (int t = 0; t < 5000; t++) begin
		a = $urandom_range(0, 1023);
		w = ($urandom_range(0, 99) < 35);
		d = { $urandom(), $urandom() };

		drive_cycle(a, w, d);
	  end

	  $display("tb_icache_data_ram: PASS");
	  $finish;
	end

endmodule
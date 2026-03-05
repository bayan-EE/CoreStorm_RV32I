`timescale 1ns/1ps
module tb_icache_tag_ram;

  timeunit 1ns;
  timeprecision 1ps;

  // -----------------------------
  // DUT signals
  // -----------------------------
  logic         clk_i;
  logic         rst_i;
  logic [7:0]   addr_i;
  logic [19:0]  data_i;
  logic         wr_i;
  logic [19:0]  data_o;

  // -----------------------------
  // Instantiate DUT
  // -----------------------------
  icache_tag_ram dut (
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
  always  #5 clk_i = ~clk_i;

  // -----------------------------
  // Waves
  // -----------------------------
  initial begin
`ifdef VCS
	$fsdbDumpfile("tb_icache_tag_ram.fsdb");
	$fsdbDumpvars(0, tb_icache_tag_ram);
`else
	$dumpfile("tb_icache_tag_ram.vcd");
	$dumpvars(0, tb_icache_tag_ram);
`endif
  end

  // -----------------------------
  // Scoreboard model
  // -----------------------------
  logic [19:0] model_ram [0:255];
  logic [7:0]  addr_prev;
  logic [19:0] expected_q;

  // -----------------------------
  // Coverage
  // -----------------------------
  covergroup cg @(posedge clk_i);
	option.per_instance = 1;

	cp_wr : coverpoint wr_i { bins rd={0}; bins wr={1}; }

	cp_addr : coverpoint addr_i {
	  bins low  = {[8'h00:8'h0F]};
	  bins mid  = {[8'h10:8'h7F]};
	  bins high = {[8'h80:8'hFF]};
	}

	cp_tag_pat : coverpoint data_i {
		bins all0  = {[20'h00000:20'h00000]};
		bins all1  = {[20'hFFFFF:20'hFFFFF]};
		bins small_bin = {[20'h00001:20'h00010]};
		bins other = default;
	  }

	x_wr_addr : cross cp_wr, cp_addr;

	cp_same_addr : coverpoint (addr_i == addr_prev) {
	  bins same = {1};
	  bins diff = {0};
	}
	x_wr_sameaddr : cross cp_wr, cp_same_addr;

  endgroup

  cg cov = new();

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

  task automatic drive_cycle(input logic [7:0] a, input logic w, input logic [19:0] d);
	addr_i = a;
	wr_i   = w;
	data_i = d;
	@(posedge clk_i);
  endtask

  // -----------------------------
  // Self-checking (Read-First)
  // -----------------------------
  always_ff @(posedge clk_i) begin
	  if (rst_i) begin
		addr_prev  <= '0;
		expected_q <= '0;

		for (int i = 0; i < 256; i++) begin
		  model_ram[i] <= '0;
		end
	  end
	  else begin
		expected_q <= model_ram[addr_i];
		if (wr_i) model_ram[addr_i] <= data_i;

		addr_prev <= addr_i;
	  end
	end
  // -----------------------------
  // Tests
  // -----------------------------
  initial begin
	  // -----------------------------
	  // Declarations MUST be first
	  // -----------------------------
	  int unsigned seed;
	  logic [7:0]  a;
	  logic        w;
	  logic [19:0] d;

	  // -----------------------------
	  // Now statements
	  // -----------------------------
	  do_reset();

	  // Directed 1: write then read
	  drive_cycle(8'h12, 1'b1, 20'hABCDE);
	  drive_cycle(8'h12, 1'b0, 20'h00000);

	  // Directed 2: read-first on same-cycle write
	  drive_cycle(8'h34, 1'b1, 20'h12345);
	  drive_cycle(8'h34, 1'b0, 20'h00000);

	  // Random test
	  seed = 32'hC0FFEE02;
	  void'($urandom(seed));

	  for (int t = 0; t < 3000; t++) begin
		a = $urandom_range(0, 255);
		w = ($urandom_range(0, 99) < 40);
		d = $urandom_range(0, (1<<20)-1);

		drive_cycle(a, w, d);
	  end

	  $display("tb_icache_tag_ram: PASS");
	  $finish;
	end

endmodule
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Testbench for RISC-V Shared Memory Interconnect
// -----------------------------------------------------------------------------
// This testbench verifies a simple multi-core interconnect that routes requests
// to a shared memory window and returns local error responses for unmapped
// addresses.
//
// Test goals:
// - Verify request acceptance and response return path
// - Verify shared-memory reads and writes
// - Verify partial-byte writes
// - Verify unmapped-address error handling
// - Verify concurrent requests from multiple ports
// - Verify random traffic across all ports
//
// Verification features:
// - Directed tests
// - Random traffic generation
// - Per-port scoreboard queues
// - Tag-based response matching (supports out-of-order completion per port)
// - Functional coverage
// - FSDB waveform dump
// -----------------------------------------------------------------------------

module tb_riscv_shared_mem_interconnect;

	localparam int NUM_PORTS   = 4;
	localparam int ADDR_WIDTH  = 32;
	localparam int DATA_WIDTH  = 32;
	localparam int STRB_WIDTH  = DATA_WIDTH / 8;
	localparam int TAG_WIDTH   = 11;
	localparam int MEM_BYTES   = 4096;
	localparam int MEM_LATENCY = 3;
	localparam logic [ADDR_WIDTH-1:0] SHARED_BASE_ADDR = 32'h1000_0000;

	logic clk;
	logic rst;

	logic [NUM_PORTS-1:0]                  req_valid;
	logic [NUM_PORTS-1:0]                  req_write;
	logic [NUM_PORTS-1:0][ADDR_WIDTH-1:0]  req_addr;
	logic [NUM_PORTS-1:0][DATA_WIDTH-1:0]  req_wdata;
	logic [NUM_PORTS-1:0][STRB_WIDTH-1:0]  req_wstrb;
	logic [NUM_PORTS-1:0][TAG_WIDTH-1:0]   req_tag;
	logic [NUM_PORTS-1:0]                  req_accept;

	logic [NUM_PORTS-1:0]                  resp_valid;
	logic [NUM_PORTS-1:0][DATA_WIDTH-1:0]  resp_rdata;
	logic [NUM_PORTS-1:0]                  resp_error;
	logic [NUM_PORTS-1:0][TAG_WIDTH-1:0]   resp_tag;
	logic [TAG_WIDTH-1:0] next_tag_q [NUM_PORTS-1:0];

	riscv_shared_mem_interconnect #(
		.NUM_PORTS        (NUM_PORTS),
		.ADDR_WIDTH       (ADDR_WIDTH),
		.DATA_WIDTH       (DATA_WIDTH),
		.STRB_WIDTH       (STRB_WIDTH),
		.TAG_WIDTH        (TAG_WIDTH),
		.MEM_BYTES        (MEM_BYTES),
		.MEM_LATENCY      (MEM_LATENCY),
		.SHARED_BASE_ADDR (SHARED_BASE_ADDR)
	) dut (
		.clk_i        (clk),
		.rst_i        (rst),
		.req_valid_i  (req_valid),
		.req_write_i  (req_write),
		.req_addr_i   (req_addr),
		.req_wdata_i  (req_wdata),
		.req_wstrb_i  (req_wstrb),
		.req_tag_i    (req_tag),
		.req_accept_o (req_accept),
		.resp_valid_o (resp_valid),
		.resp_rdata_o (resp_rdata),
		.resp_error_o (resp_error),
		.resp_tag_o   (resp_tag)
	);

	// -------------------------------------------------------------------------
	// Clock / reset
	// -------------------------------------------------------------------------
	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end

	task automatic drive_idle_all;
		begin
			req_valid = '0;
			req_write = '0;
			req_addr  = '0;
			req_wdata = '0;
			req_wstrb = '0;
			req_tag   = '0;
		end
	endtask

	task automatic reset_dut;
		begin
			rst = 1'b1;
			drive_idle_all();

			for (int p = 0; p < NUM_PORTS; p++) begin
				next_tag_q[p] = p;
			end

			repeat (5) @(posedge clk);
			rst = 1'b0;
			repeat (2) @(posedge clk);
		end
	endtask

	// -------------------------------------------------------------------------
	// Local scoreboard memory model
	// -------------------------------------------------------------------------
	logic [7:0] model_mem [0:MEM_BYTES-1];

	function automatic logic model_addr_in_shared_range(
		input logic [ADDR_WIDTH-1:0] addr
	);
		logic [ADDR_WIDTH:0] lo_addr;
		logic [ADDR_WIDTH:0] hi_addr;
		logic [ADDR_WIDTH:0] end_addr;
		begin
			lo_addr  = {1'b0, addr};
			hi_addr  = {1'b0, SHARED_BASE_ADDR};
			end_addr = {1'b0, SHARED_BASE_ADDR} + MEM_BYTES - 1;

			model_addr_in_shared_range = ((lo_addr >= hi_addr) &&
										  ((lo_addr + 3) <= end_addr));
		end
	endfunction

	function automatic int unsigned model_addr_to_index(
		input logic [ADDR_WIDTH-1:0] addr
	);
		begin
			model_addr_to_index = addr - SHARED_BASE_ADDR;
		end
	endfunction

	function automatic logic [31:0] model_read_word(
		input logic [ADDR_WIDTH-1:0] addr
	);
		int unsigned idx;
		logic [31:0] data;
		begin
			idx = model_addr_to_index(addr);
			data[7:0]   = model_mem[idx + 0];
			data[15:8]  = model_mem[idx + 1];
			data[23:16] = model_mem[idx + 2];
			data[31:24] = model_mem[idx + 3];
			model_read_word = data;
		end
	endfunction

	task automatic model_write_word(
		input logic [ADDR_WIDTH-1:0] addr,
		input logic [31:0] data,
		input logic [3:0] strb
	);
		int unsigned idx;
		begin
			idx = model_addr_to_index(addr);
			if (strb[0]) model_mem[idx + 0] = data[7:0];
			if (strb[1]) model_mem[idx + 1] = data[15:8];
			if (strb[2]) model_mem[idx + 2] = data[23:16];
			if (strb[3]) model_mem[idx + 3] = data[31:24];
		end
	endtask

	task automatic clear_model_mem;
		begin
			for (int i = 0; i < MEM_BYTES; i++) begin
				model_mem[i] = 8'h00;
			end
		end
	endtask

	// -------------------------------------------------------------------------
	// Accounting helpers
	// -------------------------------------------------------------------------
	int pass_count;
	int fail_count;

	task automatic check_equal(
		input string name,
		input logic [31:0] got,
		input logic [31:0] exp
	);
		begin
			if (got !== exp) begin
				$display("[FAIL] %s got=%08x exp=%08x t=%0t", name, got, exp, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end
		end
	endtask

	task automatic check_bit(
		input string name,
		input logic got,
		input logic exp
	);
		begin
			if (got !== exp) begin
				$display("[FAIL] %s got=%0b exp=%0b t=%0t", name, got, exp, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end
		end
	endtask

	function automatic int onehot_to_index(
		input logic [NUM_PORTS-1:0] v
	);
		int idx;
		begin
			idx = -1;
			for (int p = 0; p < NUM_PORTS; p++) begin
				if (v[p]) idx = p;
			end
			onehot_to_index = idx;
		end
	endfunction

	function automatic int count_ones(
		input logic [NUM_PORTS-1:0] v
	);
		int cnt;
		begin
			cnt = 0;
			for (int p = 0; p < NUM_PORTS; p++) begin
				if (v[p]) cnt++;
			end
			count_ones = cnt;
		end
	endfunction

	// -------------------------------------------------------------------------
	// Expected transaction storage
	// -------------------------------------------------------------------------
	typedef struct {
		int                   port;
		logic                 write;
		logic [31:0]          addr;
		logic [31:0]          wdata;
		logic [3:0]           wstrb;
		logic [TAG_WIDTH-1:0] tag;
		logic                 error;
		logic [31:0]          rdata;
	} exp_txn_t;

	exp_txn_t exp_q[NUM_PORTS][$];

	// -------------------------------------------------------------------------
	// Coverage helper signals
	// -------------------------------------------------------------------------
	logic        sample_accept;
	logic [31:0] sample_accept_port;
	logic        sample_write;
	logic        sample_valid_resp;
	logic        sample_error_resp;
	logic [1:0]  sample_path;

	always_comb begin
		sample_accept      = (req_accept != '0);
		sample_accept_port = 32'hFFFF_FFFF;
		sample_write       = 1'b0;
		sample_valid_resp  = (resp_valid != '0);
		sample_error_resp  = 1'b0;
		sample_path        = 2'd0;

		// sample_path encoding:
		// 0 = none
		// 1 = shared
		// 2 = invalid

		for (int p = 0; p < NUM_PORTS; p++) begin
			if ((sample_accept_port == 32'hFFFF_FFFF) && req_accept[p]) begin
				sample_accept_port = p;
				sample_write       = req_write[p];

				if (model_addr_in_shared_range(req_addr[p]))
					sample_path = 2'd1;
				else
					sample_path = 2'd2;
			end
		end

		for (int p = 0; p < NUM_PORTS; p++) begin
			if (resp_valid[p] && resp_error[p]) begin
				sample_error_resp = 1'b1;
			end
		end
	end

	covergroup cg_interconnect @(posedge clk);
		cp_accept : coverpoint sample_accept { bins yes = {1}; }

		cp_port : coverpoint sample_accept_port {
			bins ports[] = {[0:NUM_PORTS-1]};
		}

		cp_write : coverpoint sample_write {
			bins rd = {0};
			bins wr = {1};
		}

		cp_path : coverpoint sample_path {
			bins shared  = {2'd1};
			bins invalid = {2'd2};
		}

		cp_resp : coverpoint sample_valid_resp {
			bins yes = {1};
		}

		cp_error : coverpoint sample_error_resp {
			bins ok  = {0};
			bins err = {1};
		}

		x_port_type  : cross cp_port, cp_write;
		x_path_type  : cross cp_path, cp_write;
		x_resp_error : cross cp_write, cp_error;
	endgroup

	cg_interconnect cov = new();

	// -------------------------------------------------------------------------
	// Scoreboard monitor
	// -------------------------------------------------------------------------
	always @(posedge clk) begin
		if (rst) begin
			for (int p = 0; p < NUM_PORTS; p++) begin
				exp_q[p].delete();
			end
		end
		else begin
			// Capture all accepted requests
			for (int p = 0; p < NUM_PORTS; p++) begin
				if (req_accept[p]) begin
					exp_txn_t tx;

					tx.port  = p;
					tx.write = req_write[p];
					tx.addr  = req_addr[p];
					tx.wdata = req_wdata[p];
					tx.wstrb = req_wstrb[p];
					tx.tag   = req_tag[p];
					tx.error = !model_addr_in_shared_range(req_addr[p]);

					if (tx.error)
						tx.rdata = 32'h0000_0000;
					else if (tx.write)
						tx.rdata = 32'h0000_0000;
					else
						tx.rdata = model_read_word(req_addr[p]);

					// Update model immediately on accepted writes so later reads
					// observe the same memory ordering seen by the interconnect.
					if (tx.write && !tx.error) begin
						model_write_word(tx.addr, tx.wdata, tx.wstrb);
					end

					exp_q[p].push_back(tx);
				end
			end

			// Check all responses per port, matching by tag
			for (int p = 0; p < NUM_PORTS; p++) begin
				if (resp_valid[p]) begin
					int match_idx;
					match_idx = -1;

					for (int i = 0; i < exp_q[p].size(); i++) begin
						if (exp_q[p][i].tag == resp_tag[p]) begin
							match_idx = i;
							break;
						end
					end

					if (match_idx == -1) begin
						$display("[FAIL] response seen on port %0d with unexpected tag=%0h t=%0t",
								 p, resp_tag[p], $time);
						fail_count++;
					end
					else begin
						exp_txn_t tx;
						tx = exp_q[p][match_idx];
						exp_q[p].delete(match_idx);

						check_equal($sformatf("resp_port_p%0d", p), p, tx.port);
						check_equal($sformatf("resp_tag_p%0d", p), resp_tag[p], tx.tag);
						check_bit  ($sformatf("resp_error_p%0d", p), resp_error[p], tx.error);

						if (!tx.write && !tx.error) begin
							check_equal($sformatf("resp_rdata_p%0d", p), resp_rdata[p], tx.rdata);
						end
					end
				end
			end
		end
	end

	// -------------------------------------------------------------------------
	// Request helpers
	// -------------------------------------------------------------------------
	task automatic issue_req_single(
		input int port,
		input logic write,
		input logic [31:0] addr,
		input logic [31:0] wdata,
		input logic [3:0]  wstrb,
		input logic [TAG_WIDTH-1:0] tag
	);
		int timeout;
		begin
			req_valid[port] = 1'b1;
			req_write[port] = write;
			req_addr [port] = addr;
			req_wdata[port] = wdata;
			req_wstrb[port] = wstrb;
			req_tag  [port] = tag;

			timeout = 100;
			while (!req_accept[port] && timeout > 0) begin
				@(posedge clk);
				timeout--;
			end

			if (timeout == 0) begin
				$display("[FAIL] timeout waiting for req_accept port=%0d t=%0t", port, $time);
				fail_count++;
			end

			@(posedge clk);
			req_valid[port] <= 1'b0;
			req_write[port] <= 1'b0;
			req_addr [port] <= '0;
			req_wdata[port] <= '0;
			req_wstrb[port] <= '0;
			req_tag  [port] <= '0;
		end
	endtask

	task automatic wait_for_all_responses;
		int timeout;
		bit pending;
		begin
			timeout = 5000;
			pending = 1'b1;

			while (pending && (timeout > 0)) begin
				@(posedge clk);

				pending = 1'b0;
				for (int p = 0; p < NUM_PORTS; p++) begin
					if (exp_q[p].size() != 0)
						pending = 1'b1;
				end

				timeout--;
			end

			if (timeout == 0) begin
				$display("[FAIL] timeout waiting for expected queues to drain t=%0t", $time);
				fail_count++;
			end
		end
	endtask

	// -------------------------------------------------------------------------
	// Directed tests
	// -------------------------------------------------------------------------
	task automatic test_shared_read_zero;
		begin
			$display("[TEST] shared_read_zero");
			issue_req_single(0, 1'b0, SHARED_BASE_ADDR + 32'h0000_0000, 32'h0, 4'h0, 11'h001);
			wait_for_all_responses();
		end
	endtask

	task automatic test_shared_write_read;
		begin
			$display("[TEST] shared_write_read");

			issue_req_single(0, 1'b1, SHARED_BASE_ADDR + 32'h0000_0020, 32'hDEADBEEF, 4'hF, 11'h010);
			wait_for_all_responses();

			issue_req_single(1, 1'b0, SHARED_BASE_ADDR + 32'h0000_0020, 32'h0, 4'h0, 11'h011);
			wait_for_all_responses();
		end
	endtask

	task automatic test_partial_write;
		begin
			$display("[TEST] partial_write");

			issue_req_single(0, 1'b1, SHARED_BASE_ADDR + 32'h0000_0040, 32'h11223344, 4'hF,    11'h020);
			wait_for_all_responses();

			issue_req_single(2, 1'b1, SHARED_BASE_ADDR + 32'h0000_0040, 32'hAA00BB00, 4'b0101, 11'h021);
			wait_for_all_responses();

			issue_req_single(3, 1'b0, SHARED_BASE_ADDR + 32'h0000_0040, 32'h0,        4'h0,    11'h022);
			wait_for_all_responses();
		end
	endtask

	task automatic test_invalid_access;
		begin
			$display("[TEST] invalid_access");

			issue_req_single(0, 1'b0, 32'h0000_0010, 32'h0,         4'h0, 11'h030);
			wait_for_all_responses();

			issue_req_single(1, 1'b1, 32'h2000_0000, 32'hCAFEBABE,  4'hF, 11'h031);
			wait_for_all_responses();
		end
	endtask

	task automatic test_mixed_parallel;
		int timeout;
		begin
			$display("[TEST] mixed_parallel");

			drive_idle_all();
			@(posedge clk);

			req_valid[0] = 1'b1;
			req_write[0] = 1'b1;
			req_addr [0] = SHARED_BASE_ADDR + 32'h0000_0080;
			req_wdata[0] = 32'h12345678;
			req_wstrb[0] = 4'hF;
			req_tag  [0] = 11'h040;

			req_valid[1] = 1'b1;
			req_write[1] = 1'b0;
			req_addr [1] = 32'h0000_0100;
			req_wdata[1] = 32'h0;
			req_wstrb[1] = 4'h0;
			req_tag  [1] = 11'h041;

			req_valid[2] = 1'b1;
			req_write[2] = 1'b0;
			req_addr [2] = SHARED_BASE_ADDR + 32'h0000_0084;
			req_wdata[2] = 32'h0;
			req_wstrb[2] = 4'h0;
			req_tag  [2] = 11'h042;

			timeout = 300;
			while ((req_valid != '0) && (timeout > 0)) begin
				@(posedge clk);

				for (int p = 0; p < NUM_PORTS; p++) begin
					if (req_accept[p]) begin
						req_valid[p] <= 1'b0;
						req_write[p] <= 1'b0;
						req_addr [p] <= '0;
						req_wdata[p] <= '0;
						req_wstrb[p] <= '0;
						req_tag  [p] <= '0;
					end
				end

				timeout--;
			end

			if (timeout == 0) begin
				$display("[FAIL] mixed_parallel accept timeout t=%0t", $time);
				fail_count++;
			end

			drive_idle_all();
			wait_for_all_responses();
		end
	endtask

	task automatic test_random;
		int cycles;
		begin
			$display("[TEST] random");

			drive_idle_all();

			for (cycles = 0; cycles < 700; cycles++) begin
				@(posedge clk);

				for (int p = 0; p < NUM_PORTS; p++) begin
					if (req_accept[p]) begin
						req_valid[p] <= 1'b0;
						req_write[p] <= 1'b0;
						req_addr [p] <= '0;
						req_wdata[p] <= '0;
						req_wstrb[p] <= '0;
						req_tag  [p] <= '0;
					end
					else if (!req_valid[p] && ($urandom_range(0,99) < 35)) begin
						req_valid[p] <= 1'b1;
						req_write[p] <= $urandom_range(0,1);
						req_wdata[p] <= $urandom;
						req_wstrb[p] <= $urandom_range(1,15);
						req_tag  [p] <= next_tag_q[p];
						next_tag_q[p] = next_tag_q[p] + NUM_PORTS;

						if ($urandom_range(0,99) < 25)
							req_addr[p] <= $urandom;
						else
							req_addr[p] <= SHARED_BASE_ADDR + $urandom_range(0, MEM_BYTES-4);
					end
				end
			end

			for (int d = 0; d < 600; d++) begin
				@(posedge clk);
				for (int p = 0; p < NUM_PORTS; p++) begin
					if (req_accept[p]) begin
						req_valid[p] <= 1'b0;
						req_write[p] <= 1'b0;
						req_addr [p] <= '0;
						req_wdata[p] <= '0;
						req_wstrb[p] <= '0;
						req_tag  [p] <= '0;
					end
				end
			end

			drive_idle_all();
			wait_for_all_responses();
		end
	endtask

	// -------------------------------------------------------------------------
	// Waves
	// -------------------------------------------------------------------------
	initial begin
		$fsdbDumpfile("riscv_shared_mem_interconnect.fsdb");
		$fsdbDumpvars(0, tb_riscv_shared_mem_interconnect);
	end

	// -------------------------------------------------------------------------
	// Test sequence
	// -------------------------------------------------------------------------
	initial begin
		pass_count = 0;
		fail_count = 0;

		clear_model_mem();
		reset_dut();

		test_shared_read_zero();
		test_shared_write_read();
		test_partial_write();
		test_invalid_access();
		test_mixed_parallel();
		test_random();

		$display("==================================================");
		$display("RISCV_SHARED_MEM_INTERCONNECT TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cov.get_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		#20;
		$finish;
	end

endmodule
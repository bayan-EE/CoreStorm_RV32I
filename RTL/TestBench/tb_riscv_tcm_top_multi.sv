`timescale 1ns/1ps

module tb_riscv_tcm_top_multi;

	localparam int NUM_CORES   = 4;
	localparam int CLK_PERIOD  = 10;
	localparam logic [31:0] TCM_BASE    = 32'h0000_0000;
	localparam logic [31:0] BOOT_VECTOR = 32'h0000_0040;
	localparam int CORE_ID_BASE_P       = 0;

	logic                               clk;
	logic                               rst;
	logic [NUM_CORES-1:0]               rst_cpu;

	// External AXI initiator side
	logic [NUM_CORES-1:0]               axi_i_awready_i;
	logic [NUM_CORES-1:0]               axi_i_wready_i;
	logic [NUM_CORES-1:0]               axi_i_bvalid_i;
	logic [NUM_CORES-1:0][1:0]          axi_i_bresp_i;
	logic [NUM_CORES-1:0]               axi_i_arready_i;
	logic [NUM_CORES-1:0]               axi_i_rvalid_i;
	logic [NUM_CORES-1:0][31:0]         axi_i_rdata_i;
	logic [NUM_CORES-1:0][1:0]          axi_i_rresp_i;

	logic [NUM_CORES-1:0]               axi_i_awvalid_o;
	logic [NUM_CORES-1:0][31:0]         axi_i_awaddr_o;
	logic [NUM_CORES-1:0]               axi_i_wvalid_o;
	logic [NUM_CORES-1:0][31:0]         axi_i_wdata_o;
	logic [NUM_CORES-1:0][3:0]          axi_i_wstrb_o;
	logic [NUM_CORES-1:0]               axi_i_bready_o;
	logic [NUM_CORES-1:0]               axi_i_arvalid_o;
	logic [NUM_CORES-1:0][31:0]         axi_i_araddr_o;
	logic [NUM_CORES-1:0]               axi_i_rready_o;

	// TCM AXI target side
	logic [NUM_CORES-1:0]               axi_t_awvalid_i;
	logic [NUM_CORES-1:0][31:0]         axi_t_awaddr_i;
	logic [NUM_CORES-1:0][3:0]          axi_t_awid_i;
	logic [NUM_CORES-1:0][7:0]          axi_t_awlen_i;
	logic [NUM_CORES-1:0][1:0]          axi_t_awburst_i;
	logic [NUM_CORES-1:0]               axi_t_wvalid_i;
	logic [NUM_CORES-1:0][31:0]         axi_t_wdata_i;
	logic [NUM_CORES-1:0][3:0]          axi_t_wstrb_i;
	logic [NUM_CORES-1:0]               axi_t_wlast_i;
	logic [NUM_CORES-1:0]               axi_t_bready_i;
	logic [NUM_CORES-1:0]               axi_t_arvalid_i;
	logic [NUM_CORES-1:0][31:0]         axi_t_araddr_i;
	logic [NUM_CORES-1:0][3:0]          axi_t_arid_i;
	logic [NUM_CORES-1:0][7:0]          axi_t_arlen_i;
	logic [NUM_CORES-1:0][1:0]          axi_t_arburst_i;
	logic [NUM_CORES-1:0]               axi_t_rready_i;

	logic [NUM_CORES-1:0]               axi_t_awready_o;
	logic [NUM_CORES-1:0]               axi_t_wready_o;
	logic [NUM_CORES-1:0]               axi_t_bvalid_o;
	logic [NUM_CORES-1:0][1:0]          axi_t_bresp_o;
	logic [NUM_CORES-1:0][3:0]          axi_t_bid_o;
	logic [NUM_CORES-1:0]               axi_t_arready_o;
	logic [NUM_CORES-1:0]               axi_t_rvalid_o;
	logic [NUM_CORES-1:0][31:0]         axi_t_rdata_o;
	logic [NUM_CORES-1:0][1:0]          axi_t_rresp_o;
	logic [NUM_CORES-1:0][3:0]          axi_t_rid_o;
	logic [NUM_CORES-1:0]               axi_t_rlast_o;

	logic [NUM_CORES-1:0][31:0]         intr_i;

	int pass_count;
	int fail_count;

	bit [31:0] shadow_tcm [0:NUM_CORES-1][0:2047];

	typedef enum int {OP_READ=0, OP_WRITE=1} op_e;
	int   cov_core;
	op_e  cov_op;
	logic [3:0] cov_wstrb;

	covergroup cg_multi;
		option.per_instance = 1;

		cp_core : coverpoint cov_core {
			bins c0 = {0};
			bins c1 = {1};
			bins c2 = {2};
			bins c3 = {3};
		}

		cp_op : coverpoint cov_op {
			bins rd = {OP_READ};
			bins wr = {OP_WRITE};
		}

		cp_wstrb : coverpoint cov_wstrb iff (cov_op == OP_WRITE) {
			bins b0    = {4'b0001};
			bins b1    = {4'b0010};
			bins b2    = {4'b0100};
			bins b3    = {4'b1000};
			bins half0 = {4'b0011};
			bins half1 = {4'b1100};
			bins word  = {4'b1111};
		}

		cross cp_core, cp_op;

		x_core_op_wstrb : cross cp_core, cp_op, cp_wstrb {
			ignore_bins read_bins = binsof(cp_op.rd);
		}
	endgroup

	cg_multi cov_inst = new();

	riscv_tcm_top_multi #(
		 .NUM_CORES    (NUM_CORES),
		 .BOOT_VECTOR  (BOOT_VECTOR),
		 .CORE_ID_BASE (CORE_ID_BASE_P),
		 .TCM_MEM_BASE (TCM_BASE)
	) dut (
		 .clk_i          (clk),
		 .rst_i          (rst),
		 .rst_cpu_i      (rst_cpu),

		 .axi_i_awready_i(axi_i_awready_i),
		 .axi_i_wready_i (axi_i_wready_i),
		 .axi_i_bvalid_i (axi_i_bvalid_i),
		 .axi_i_bresp_i  (axi_i_bresp_i),
		 .axi_i_arready_i(axi_i_arready_i),
		 .axi_i_rvalid_i (axi_i_rvalid_i),
		 .axi_i_rdata_i  (axi_i_rdata_i),
		 .axi_i_rresp_i  (axi_i_rresp_i),

		 .axi_i_awvalid_o(axi_i_awvalid_o),
		 .axi_i_awaddr_o (axi_i_awaddr_o),
		 .axi_i_wvalid_o (axi_i_wvalid_o),
		 .axi_i_wdata_o  (axi_i_wdata_o),
		 .axi_i_wstrb_o  (axi_i_wstrb_o),
		 .axi_i_bready_o (axi_i_bready_o),
		 .axi_i_arvalid_o(axi_i_arvalid_o),
		 .axi_i_araddr_o (axi_i_araddr_o),
		 .axi_i_rready_o (axi_i_rready_o),

		 .axi_t_awvalid_i(axi_t_awvalid_i),
		 .axi_t_awaddr_i (axi_t_awaddr_i),
		 .axi_t_awid_i   (axi_t_awid_i),
		 .axi_t_awlen_i  (axi_t_awlen_i),
		 .axi_t_awburst_i(axi_t_awburst_i),
		 .axi_t_wvalid_i (axi_t_wvalid_i),
		 .axi_t_wdata_i  (axi_t_wdata_i),
		 .axi_t_wstrb_i  (axi_t_wstrb_i),
		 .axi_t_wlast_i  (axi_t_wlast_i),
		 .axi_t_bready_i (axi_t_bready_i),
		 .axi_t_arvalid_i(axi_t_arvalid_i),
		 .axi_t_araddr_i (axi_t_araddr_i),
		 .axi_t_arid_i   (axi_t_arid_i),
		 .axi_t_arlen_i  (axi_t_arlen_i),
		 .axi_t_arburst_i(axi_t_arburst_i),
		 .axi_t_rready_i (axi_t_rready_i),

		 .axi_t_awready_o(axi_t_awready_o),
		 .axi_t_wready_o (axi_t_wready_o),
		 .axi_t_bvalid_o (axi_t_bvalid_o),
		 .axi_t_bresp_o  (axi_t_bresp_o),
		 .axi_t_bid_o    (axi_t_bid_o),
		 .axi_t_arready_o(axi_t_arready_o),
		 .axi_t_rvalid_o (axi_t_rvalid_o),
		 .axi_t_rdata_o  (axi_t_rdata_o),
		 .axi_t_rresp_o  (axi_t_rresp_o),
		 .axi_t_rid_o    (axi_t_rid_o),
		 .axi_t_rlast_o  (axi_t_rlast_o),

		 .intr_i         (intr_i)
	);

	//============================================================
	// Clock
	//============================================================
	initial begin
		clk = 1'b0;
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

	//============================================================
	// Utility
	//============================================================
	task automatic tick(input int n = 1);
		repeat (n) @(posedge clk);
	endtask

	task automatic check_equal32(
		input string name,
		input logic [31:0] got,
		input logic [31:0] exp
	);
		if (got !== exp) begin
			$display("[FAIL] %s got=%08x exp=%08x t=%0t", name, got, exp, $time);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	task automatic check_equal4(
		input string name,
		input logic [3:0] got,
		input logic [3:0] exp
	);
		if (got !== exp) begin
			$display("[FAIL] %s got=%0h exp=%0h t=%0t", name, got, exp, $time);
			fail_count++;
		end
		else begin
			pass_count++;
		end
	endtask

	

	function automatic [31:0] apply_wstrb32(
		input [31:0] old_data,
		input [31:0] new_data,
		input [3:0]  strb
	);
		begin
			apply_wstrb32 = old_data;
			if (strb[0]) apply_wstrb32[7:0]   = new_data[7:0];
			if (strb[1]) apply_wstrb32[15:8]  = new_data[15:8];
			if (strb[2]) apply_wstrb32[23:16] = new_data[23:16];
			if (strb[3]) apply_wstrb32[31:24] = new_data[31:24];
		end
	endfunction

	task automatic sample_cov(input int core, input op_e op, input logic [3:0] wstrb);
		cov_core  = core;
		cov_op    = op;
		cov_wstrb = wstrb;
		cov_inst.sample();
	endtask

	task automatic init_shadow();
		int c, i;
		for (c = 0; c < NUM_CORES; c++) begin
			for (i = 0; i < 2048; i++) begin
				shadow_tcm[c][i] = 32'h1000_0000 + (c << 12) + i;
			end
		end
	endtask

	//============================================================
	// Reset
	//============================================================
	task automatic reset_dut();
		int c;
		begin
			rst = 1'b1;
			rst_cpu = '1; // keep cores in reset for this TB

			axi_i_awready_i = '1;
			axi_i_wready_i  = '1;
			axi_i_bvalid_i  = '0;
			axi_i_bresp_i   = '0;
			axi_i_arready_i = '1;
			axi_i_rvalid_i  = '0;
			axi_i_rdata_i   = '0;
			axi_i_rresp_i   = '0;

			axi_t_awvalid_i = '0;
			axi_t_awaddr_i  = '0;
			axi_t_awid_i    = '0;
			axi_t_awlen_i   = '0;
			axi_t_awburst_i = '0;
			axi_t_wvalid_i  = '0;
			axi_t_wdata_i   = '0;
			axi_t_wstrb_i   = '0;
			axi_t_wlast_i   = '1;
			axi_t_bready_i  = '1;
			axi_t_arvalid_i = '0;
			axi_t_araddr_i  = '0;
			axi_t_arid_i    = '0;
			axi_t_arlen_i   = '0;
			axi_t_arburst_i = '0;
			axi_t_rready_i  = '1;

			intr_i = '0;

			tick(5);
			rst = 1'b0;
			rst_cpu = '1;
			tick(8);

			init_shadow();

			for (c = 0; c < NUM_CORES; c++) begin
				check_equal32($sformatf("cpu_id_core%0d", c), dut.cpu_id_w[c], CORE_ID_BASE_P + c);
				check_equal32($sformatf("boot_vector_core%0d", c), dut.boot_vector_w[c], BOOT_VECTOR);
			end
		end
	endtask

	//============================================================
	// AXI target access into TCM
	//============================================================
	task automatic axi_tcm_write(
			input int core,
			input logic [31:0] addr,
			input logic [31:0] data,
			input logic [3:0]  strb,
			input logic [3:0]  id
		);
			int timeout;

			axi_t_awvalid_i[core] = 1'b1;
			axi_t_awaddr_i [core] = addr;
			axi_t_awid_i   [core] = id;
			axi_t_awlen_i  [core] = 8'd0;
			axi_t_awburst_i[core] = 2'b01;

			axi_t_wvalid_i [core] = 1'b1;
			axi_t_wdata_i  [core] = data;
			axi_t_wstrb_i  [core] = strb;
			axi_t_wlast_i  [core] = 1'b1;

			timeout = 0;
			while (axi_t_awready_o[core] !== 1'b1 && timeout < 60) begin
				tick(1);
				timeout++;
			end
			if (axi_t_awready_o[core] !== 1'b1) begin
				$display("[FAIL] timeout waiting for axi_t_awready_core%0d t=%0t", core, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			timeout = 0;
			while (axi_t_wready_o[core] !== 1'b1 && timeout < 60) begin
				tick(1);
				timeout++;
			end
			if (axi_t_wready_o[core] !== 1'b1) begin
				$display("[FAIL] timeout waiting for axi_t_wready_core%0d t=%0t", core, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			tick(1);

			axi_t_awvalid_i[core] = 1'b0;
			axi_t_wvalid_i [core] = 1'b0;

			timeout = 0;
			while (axi_t_bvalid_o[core] !== 1'b1 && timeout < 60) begin
				tick(1);
				timeout++;
			end
			if (axi_t_bvalid_o[core] !== 1'b1) begin
				$display("[FAIL] timeout waiting for axi_t_bvalid_core%0d t=%0t", core, $time);
				fail_count++;
			end
			else begin
				pass_count++;
			end

			#1;
			check_equal4($sformatf("axi_t_bid_core%0d", core), axi_t_bid_o[core], id);
			tick(1);
		endtask

		task automatic axi_tcm_read(
				input  int core,
				input  logic [31:0] addr,
				input  logic [3:0]  id,
				output logic [31:0] data
			);
				int timeout;

				axi_t_arvalid_i[core] = 1'b1;
				axi_t_araddr_i [core] = addr;
				axi_t_arid_i   [core] = id;
				axi_t_arlen_i  [core] = 8'd0;
				axi_t_arburst_i[core] = 2'b01;

				timeout = 0;
				while (axi_t_arready_o[core] !== 1'b1 && timeout < 60) begin
					tick(1);
					timeout++;
				end
				if (axi_t_arready_o[core] !== 1'b1) begin
					$display("[FAIL] timeout waiting for axi_t_arready_core%0d t=%0t", core, $time);
					fail_count++;
				end
				else begin
					pass_count++;
				end

				tick(1);

				axi_t_arvalid_i[core] = 1'b0;

				timeout = 0;
				while (axi_t_rvalid_o[core] !== 1'b1 && timeout < 60) begin
					tick(1);
					timeout++;
				end
				if (axi_t_rvalid_o[core] !== 1'b1) begin
					$display("[FAIL] timeout waiting for axi_t_rvalid_core%0d t=%0t", core, $time);
					fail_count++;
				end
				else begin
					pass_count++;
				end

				#1;
				check_equal4($sformatf("axi_t_rid_core%0d", core), axi_t_rid_o[core], id);
				data = axi_t_rdata_o[core];
				tick(1);
			endtask

	//============================================================
	// Tests
	//============================================================
	task automatic test_each_core_basic();
		int c;
		logic [31:0] addr;
		logic [31:0] rdata;
		logic [31:0] oldv;
		logic [31:0] newv;
		logic [3:0]  wid;
		logic [3:0]  rid;
		begin
			$display("[TEST] each_core_basic");

			for (c = 0; c < NUM_CORES; c++) begin
				addr = TCM_BASE + 32'h20 + (c * 32'h10);
				oldv = shadow_tcm[c][addr >> 2];
				newv = 32'hABCD_0000 | c;
				shadow_tcm[c][addr >> 2] = apply_wstrb32(oldv, newv, 4'b1111);

				wid = c[3:0];
				rid = (c + 4);

				sample_cov(c, OP_WRITE, 4'b1111);
				axi_tcm_write(c, addr, newv, 4'b1111, wid);

				sample_cov(c, OP_READ, 4'b0000);
				axi_tcm_read(c, addr, rid, rdata);

				check_equal32($sformatf("core%0d_tcm_readback", c), rdata, shadow_tcm[c][addr >> 2]);
			end
		end
	endtask

	task automatic test_isolation_between_cores();
		int c;
		logic [31:0] addr;
		logic [31:0] rdata;
		logic [3:0]  wid;
		logic [3:0]  rid;
		begin
			$display("[TEST] isolation_between_cores");

			addr = TCM_BASE + 32'h100;

			for (c = 0; c < NUM_CORES; c++) begin
				shadow_tcm[c][addr >> 2] = 32'h5500_0000 | c;
				wid = c[3:0];
				sample_cov(c, OP_WRITE, 4'b1111);
				axi_tcm_write(c, addr, shadow_tcm[c][addr >> 2], 4'b1111, wid);
			end

			for (c = 0; c < NUM_CORES; c++) begin
				rid = c + 8;
				sample_cov(c, OP_READ, 4'b0000);
				axi_tcm_read(c, addr, rid, rdata);
				check_equal32($sformatf("core%0d_isolated_value", c), rdata, shadow_tcm[c][addr >> 2]);
			end
		end
	endtask
	task automatic preload_tcm_from_shadow();
		int c;
		int idx;
		logic [3:0] wid;
		begin
			$display("[TEST] preload_tcm_from_shadow");

			for (c = 0; c < NUM_CORES; c++) begin
				wid = c[3:0];

				// random test uses idx 0..255, so preload that range
				for (idx = 0; idx < 256; idx++) begin
					axi_tcm_write(
						c,
						TCM_BASE + (idx << 2),
						shadow_tcm[c][idx],
						4'b1111,
						wid
					);
				end
			end
		end
	endtask

	task automatic test_wstrb_coverage();
		int c;
		int s;
		logic [31:0] addr;
		logic [31:0] rdata;
		logic [31:0] exp;
		logic [3:0]  strb;
		logic [3:0]  wid;
		logic [3:0]  rid;
		logic [31:0] wdata;
		begin
			$display("[TEST] wstrb_coverage");

			for (c = 0; c < NUM_CORES; c++) begin
				addr = TCM_BASE + 32'h200 + (c * 32'h40);
				exp  = shadow_tcm[c][addr >> 2];

				for (s = 0; s < 7; s++) begin
					case (s)
						0: strb = 4'b0001;
						1: strb = 4'b0010;
						2: strb = 4'b0100;
						3: strb = 4'b1000;
						4: strb = 4'b0011;
						5: strb = 4'b1100;
						default: strb = 4'b1111;
					endcase

					wdata = 32'hA5A50000 | (c << 8) | s;
					exp   = apply_wstrb32(exp, wdata, strb);
					shadow_tcm[c][addr >> 2] = exp;

					wid = c[3:0];
					sample_cov(c, OP_WRITE, strb);
					axi_tcm_write(c, addr, wdata, strb, wid);
				end

				rid = c + 4;
				sample_cov(c, OP_READ, 4'b0000);
				axi_tcm_read(c, addr, rid, rdata);
				check_equal32($sformatf("wstrb_cov_core%0d", c), rdata, shadow_tcm[c][addr >> 2]);
			end
		end
	endtask
	task automatic test_cross_coverage();
		int c;
		logic [31:0] addr;
		logic [31:0] rdata;
		logic [3:0]  wid;
		logic [3:0]  rid;

		begin
			$display("[TEST] cross_coverage");

			// outside random range (random uses only 0x000..0x3FC)
			addr = TCM_BASE + 32'h800;

			for (c = 0; c < NUM_CORES; c++) begin
				wid = c[3:0];
				rid = c + 4;

				// WRITE full
				sample_cov(c, OP_WRITE, 4'b1111);
				axi_tcm_write(c, addr, 32'h11110000 | c, 4'b1111, wid);

				// WRITE partial
				sample_cov(c, OP_WRITE, 4'b0011);
				axi_tcm_write(c, addr, 32'hAAAA0000 | c, 4'b0011, wid);

				// READ
				sample_cov(c, OP_READ, 4'b0000);
				axi_tcm_read(c, addr, rid, rdata);
			end
		end
	endtask

	task automatic test_random();
		int c;
		int idx;
		logic [31:0] addr;
		logic [31:0] wdata;
		logic [31:0] rdata;
		logic [3:0]  strb;
		logic [3:0]  id;
		begin
			$display("[TEST] random");

			repeat (800) begin
				c     = $urandom_range(0, NUM_CORES-1);
				idx   = $urandom_range(0, 255);
				addr  = TCM_BASE + (idx << 2);
				wdata = $urandom();
				id    = $urandom_range(0, 15);

				case ($urandom_range(0,6))
					0: strb = 4'b0001;
					1: strb = 4'b0010;
					2: strb = 4'b0100;
					3: strb = 4'b1000;
					4: strb = 4'b0011;
					5: strb = 4'b1100;
					default: strb = 4'b1111;
				endcase

				if ($urandom_range(0,1)) begin
					shadow_tcm[c][addr >> 2] = apply_wstrb32(shadow_tcm[c][addr >> 2], wdata, strb);
					sample_cov(c, OP_WRITE, strb);
					axi_tcm_write(c, addr, wdata, strb, id);
				end
				else begin
					sample_cov(c, OP_READ, 4'b0000);
					axi_tcm_read(c, addr, id, rdata);
					check_equal32($sformatf("random_core%0d", c), rdata, shadow_tcm[c][addr >> 2]);
				end
			end
		end
	endtask

	//============================================================
	// Main
	//============================================================
	initial begin
		pass_count = 0;
		fail_count = 0;

		$fsdbDumpfile("novas_multicore.fsdb");
		$fsdbDumpvars(0, tb_riscv_tcm_top_multi);

		reset_dut();
		preload_tcm_from_shadow();
		test_each_core_basic();
		test_isolation_between_cores();
		test_wstrb_coverage();
		test_cross_coverage();
		test_cross_coverage();
		test_random();

		$display("==================================================");
		$display("RISCV_TCM_TOP_MULTI TB SUMMARY");
		$display("  pass_count = %0d", pass_count);
		$display("  fail_count = %0d", fail_count);
		$display("  coverage   = %0.2f %%", cov_inst.get_inst_coverage());
		$display("==================================================");

		if (fail_count == 0)
			$display("TB PASSED");
		else
			$display("TB FAILED");

		$finish;
	end
	

endmodule
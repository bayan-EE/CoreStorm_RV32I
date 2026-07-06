
//---------------------------------------------------------------------
// Module: tcm_mem
// Type  : Tightly Coupled Memory wrapper
//
// Description:
// This module implements a simple tightly coupled memory (TCM) subsystem
// that serves three roles at once:
//
//   1. Instruction memory interface for the CPU
//      - Receives instruction fetch requests from the core.
//      - Returns a 64-bit instruction line from internal RAM.
//
//   2. Data memory interface for the CPU
//      - Receives load/store style accesses from the core.
//      - Returns read data, accept/ack signals, and response tags.
//
//   3. External AXI memory access interface
//      - Accepts AXI read/write transactions from an external master.
//      - Converts AXI protocol activity into a simple internal RAM-style
//        interface using the tcm_mem_pmem converter.
//
// Internally, the design uses a dual-port RAM:
//
//   - Port 0 is dedicated to instruction fetches.
//   - Port 1 is shared between:
//       a) CPU data memory accesses
//       b) external AXI accesses
//
// Arbitration policy:
// - External accesses have priority on RAM port 1.
// - When an external access is active, CPU data accesses are temporarily
//   not accepted.
//
// Additional notes:
// - Instruction fetches are always accepted immediately.
// - Data accesses return an acknowledge pulse together with the request tag.
// - Flush / invalidate / writeback requests are acknowledged, but since
//   this is a simple TCM and not a real cache, these operations do not
//   perform cache-state handling.
// - Under verilator, helper byte-level read/write functions are exposed
//   for simulation/debug purposes.
//
// This is mainly a structural + control wrapper around:
//   - tcm_mem_pmem  : AXI-to-simple-memory bridge
//   - tcm_mem_ram   : dual-port internal RAM
//---------------------------------------------------------------------
`timescale 1ns/1ps

module tcm_mem
(
	// Inputs
	input  logic        clk_i,
	input  logic        rst_i,
	input  logic        mem_i_rd_i,
	input  logic        mem_i_flush_i,
	input  logic        mem_i_invalidate_i,
	input  logic [31:0] mem_i_pc_i,
	input  logic [31:0] mem_d_addr_i,
	input  logic [31:0] mem_d_data_wr_i,
	input  logic        mem_d_rd_i,
	input  logic [3:0]  mem_d_wr_i,
	input  logic        mem_d_cacheable_i,
	input  logic [10:0] mem_d_req_tag_i,
	input  logic        mem_d_invalidate_i,
	input  logic        mem_d_writeback_i,
	input  logic        mem_d_flush_i,
	input  logic        axi_awvalid_i,
	input  logic [31:0] axi_awaddr_i,
	input  logic [3:0]  axi_awid_i,
	input  logic [7:0]  axi_awlen_i,
	input  logic [1:0]  axi_awburst_i,
	input  logic        axi_wvalid_i,
	input  logic [31:0] axi_wdata_i,
	input  logic [3:0]  axi_wstrb_i,
	input  logic        axi_wlast_i,
	input  logic        axi_bready_i,
	input  logic        axi_arvalid_i,
	input  logic [31:0] axi_araddr_i,
	input  logic [3:0]  axi_arid_i,
	input  logic [7:0]  axi_arlen_i,
	input  logic [1:0]  axi_arburst_i,
	input  logic        axi_rready_i,

	// Outputs
	output logic        mem_i_accept_o,
	output logic        mem_i_valid_o,
	output logic        mem_i_error_o,
	output logic [63:0] mem_i_inst_o,
	output logic [31:0] mem_d_data_rd_o,
	output logic        mem_d_accept_o,
	output logic        mem_d_ack_o,
	output logic        mem_d_error_o,
	output logic [10:0] mem_d_resp_tag_o,
	output logic        axi_awready_o,
	output logic        axi_wready_o,
	output logic        axi_bvalid_o,
	output logic [1:0]  axi_bresp_o,
	output logic [3:0]  axi_bid_o,
	output logic        axi_arready_o,
	output logic        axi_rvalid_o,
	output logic [31:0] axi_rdata_o,
	output logic [1:0]  axi_rresp_o,
	output logic [3:0]  axi_rid_o,
	output logic        axi_rlast_o
);

//---------------------------------------------------------------------
// AXI <-> Internal Physical Memory Style Interface
//---------------------------------------------------------------------
// These signals connect the AXI bridge (tcm_mem_pmem) to the shared RAM
// side of the TCM.
logic        ext_accept_w;
logic        ext_ack_w;
logic [31:0] ext_read_data_w;
logic [3:0]  ext_wr_w;
logic        ext_rd_w;
logic [7:0]  ext_len_w;
logic [31:0] ext_addr_w;
logic [31:0] ext_write_data_w;

tcm_mem_pmem
u_conv
(
	// Inputs
	.clk_i          (clk_i),
	.rst_i          (rst_i),
	.axi_awvalid_i  (axi_awvalid_i),
	.axi_awaddr_i   (axi_awaddr_i),
	.axi_awid_i     (axi_awid_i),
	.axi_awlen_i    (axi_awlen_i),
	.axi_awburst_i  (axi_awburst_i),
	.axi_wvalid_i   (axi_wvalid_i),
	.axi_wdata_i    (axi_wdata_i),
	.axi_wstrb_i    (axi_wstrb_i),
	.axi_wlast_i    (axi_wlast_i),
	.axi_bready_i   (axi_bready_i),
	.axi_arvalid_i  (axi_arvalid_i),
	.axi_araddr_i   (axi_araddr_i),
	.axi_arid_i     (axi_arid_i),
	.axi_arlen_i    (axi_arlen_i),
	.axi_arburst_i  (axi_arburst_i),
	.axi_rready_i   (axi_rready_i),
	.ram_accept_i   (ext_accept_w),
	.ram_ack_i      (ext_ack_w),
	.ram_error_i    (1'b0),
	.ram_read_data_i(ext_read_data_w),

	// Outputs
	.axi_awready_o  (axi_awready_o),
	.axi_wready_o   (axi_wready_o),
	.axi_bvalid_o   (axi_bvalid_o),
	.axi_bresp_o    (axi_bresp_o),
	.axi_bid_o      (axi_bid_o),
	.axi_arready_o  (axi_arready_o),
	.axi_rvalid_o   (axi_rvalid_o),
	.axi_rdata_o    (axi_rdata_o),
	.axi_rresp_o    (axi_rresp_o),
	.axi_rid_o      (axi_rid_o),
	.axi_rlast_o    (axi_rlast_o),
	.ram_wr_o       (ext_wr_w),
	.ram_rd_o       (ext_rd_w),
	.ram_len_o      (ext_len_w),
	.ram_addr_o     (ext_addr_w),
	.ram_write_data_o(ext_write_data_w)
);

//---------------------------------------------------------------------
// Shared Dual-Port RAM Access Mux
//---------------------------------------------------------------------
// RAM port 0 is used for instruction fetches.
// RAM port 1 is shared between:
//   - external AXI accesses
//   - CPU data accesses
//
// External accesses have priority over CPU data accesses.
logic        muxed_hi_w;
logic [12:0] muxed_addr_w;
logic [31:0] muxed_data_w;
logic [3:0]  muxed_wr_w;
logic [63:0] data_r_w;

assign muxed_hi_w   = ext_accept_w ? ext_addr_w[2]   : mem_d_addr_i[2];
assign muxed_addr_w = ext_accept_w ? ext_addr_w[15:3]: mem_d_addr_i[15:3];
assign muxed_data_w = ext_accept_w ? ext_write_data_w: mem_d_data_wr_i;
assign muxed_wr_w   = ext_accept_w ? ext_wr_w        : mem_d_wr_i;

tcm_mem_ram
u_ram
(
	// Port 0: Instruction fetch
	.clk0_i  (clk_i),
	.rst0_i  (rst_i),
	.addr0_i (mem_i_pc_i[15:3]),
	.data0_i (64'b0),
	.wr0_i   (8'b0),

	// Port 1: External AXI access or CPU data access
	.clk1_i  (clk_i),
	.rst1_i  (rst_i),
	.addr1_i (muxed_addr_w),
	.data1_i (muxed_hi_w ? {muxed_data_w, 32'b0} : {32'b0, muxed_data_w}),
	.wr1_i   (muxed_hi_w ? {muxed_wr_w, 4'b0}    : {4'b0, muxed_wr_w}),

	// Outputs
	.data0_o (mem_i_inst_o),
	.data1_o (data_r_w)
);

//---------------------------------------------------------------------
// Read Half Selector Pipeline Register
//---------------------------------------------------------------------
// The RAM returns 64 bits, but data accesses read only one 32-bit half.
// This register keeps track of whether the upper or lower half was
// selected in the request cycle.
logic muxed_hi_q;

always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		muxed_hi_q <= 1'b0;
	else
		muxed_hi_q <= muxed_hi_w;
end

assign ext_read_data_w = muxed_hi_q ? data_r_w[63:32] : data_r_w[31:0];

//---------------------------------------------------------------------
// Instruction Fetch Interface
//---------------------------------------------------------------------
// Instruction requests are always accepted. A valid pulse is generated
// one cycle after mem_i_rd_i.
logic mem_i_valid_q;

always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		mem_i_valid_q <= 1'b0;
	else
		mem_i_valid_q <= mem_i_rd_i;
end

assign mem_i_accept_o = 1'b1;
assign mem_i_valid_o  = mem_i_valid_q;
assign mem_i_error_o  = 1'b0;

//---------------------------------------------------------------------
// Data Access / External Access Arbitration
//---------------------------------------------------------------------
// CPU data requests are accepted unless an external access is currently
// using the shared RAM port.
//
// mem_d_accept_q behavior:
// - After reset: internal CPU data port is accepted.
// - If an external read/write request is active, internal CPU data
//   requests are blocked in the next cycle.
// - Otherwise, CPU data requests are accepted.
logic        mem_d_accept_q;
logic [10:0] mem_d_tag_q;
logic        mem_d_ack_q;
logic        ext_ack_q;

always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		mem_d_accept_q <= 1'b1;
	else if (ext_rd_w || (ext_wr_w != 4'b0))
		mem_d_accept_q <= 1'b0;
	else
		mem_d_accept_q <= 1'b1;
end

//---------------------------------------------------------------------
// CPU Data Request Acknowledge
//---------------------------------------------------------------------
// Any internal data request or maintenance request is acknowledged with
// its tag when accepted.
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i) begin
		mem_d_ack_q <= 1'b0;
		mem_d_tag_q <= 11'b0;
	end
	else if ((mem_d_rd_i || (mem_d_wr_i != 4'b0) || mem_d_flush_i ||
			  mem_d_invalidate_i || mem_d_writeback_i) && mem_d_accept_o) begin
		mem_d_ack_q <= 1'b1;
		mem_d_tag_q <= mem_d_req_tag_i;
	end
	else begin
		mem_d_ack_q <= 1'b0;
	end
end

//---------------------------------------------------------------------
// External Access Acknowledge
//---------------------------------------------------------------------
// An external request is acknowledged if it is active and the external
// interface was granted the shared RAM port.
always_ff @(posedge clk_i or posedge rst_i) begin
	if (rst_i)
		ext_ack_q <= 1'b0;
	else if ((ext_rd_w || (ext_wr_w != 4'b0)) && ext_accept_w)
		ext_ack_q <= 1'b1;
	else
		ext_ack_q <= 1'b0;
end

assign mem_d_ack_o      = mem_d_ack_q;
assign mem_d_resp_tag_o = mem_d_tag_q;
assign mem_d_data_rd_o  = muxed_hi_q ? data_r_w[63:32] : data_r_w[31:0];
assign mem_d_error_o    = 1'b0;

assign mem_d_accept_o   = mem_d_accept_q;
assign ext_accept_w     = !mem_d_accept_q;
assign ext_ack_w        = ext_ack_q;

`ifdef verilator
//---------------------------------------------------------------------
// Verilator Debug Helper: write
//
// Writes a single byte into the internal RAM at the specified byte
// address. This is useful for testbench preload or memory patching.
//---------------------------------------------------------------------
function void write; /*verilator public*/
	input [31:0] addr;
	input [7:0]  data;
begin
	case (addr[2:0])
		3'd0: u_ram.ram[addr/8][7:0]   = data;
		3'd1: u_ram.ram[addr/8][15:8]  = data;
		3'd2: u_ram.ram[addr/8][23:16] = data;
		3'd3: u_ram.ram[addr/8][31:24] = data;
		3'd4: u_ram.ram[addr/8][39:32] = data;
		3'd5: u_ram.ram[addr/8][47:40] = data;
		3'd6: u_ram.ram[addr/8][55:48] = data;
		3'd7: u_ram.ram[addr/8][63:56] = data;
		default: ;
	endcase
end
endfunction

//---------------------------------------------------------------------
// Verilator Debug Helper: read
//
// Reads a single byte from the internal RAM at the specified byte
// address. This is useful for testbench checking and debug.
//---------------------------------------------------------------------
function automatic [7:0] read; /*verilator public*/
	input [31:0] addr;
begin
	case (addr[2:0])
		3'd0: read = u_ram.ram[addr/8][7:0];
		3'd1: read = u_ram.ram[addr/8][15:8];
		3'd2: read = u_ram.ram[addr/8][23:16];
		3'd3: read = u_ram.ram[addr/8][31:24];
		3'd4: read = u_ram.ram[addr/8][39:32];
		3'd5: read = u_ram.ram[addr/8][47:40];
		3'd6: read = u_ram.ram[addr/8][55:48];
		3'd7: read = u_ram.ram[addr/8][63:56];
		default: read = 8'h00;
	endcase
end
endfunction
`endif

endmodule
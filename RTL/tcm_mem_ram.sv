
//---------------------------------------------------------------------
// Module: tcm_mem_ram
// Type  : Dual-port synchronous RAM
//
// Description:
// This module implements a dual-port 64-bit wide RAM with 8192 entries,
// which corresponds to 64 KB total storage:
//
//     8192 entries × 8 bytes = 65536 bytes = 64 KB
//
// Each port has:
//   - its own clock
//   - its own address
//   - its own write data
//   - its own byte write enable mask
//   - its own registered read output
//
// Memory behavior:
// - Synchronous read
// - Synchronous write
// - Read-first mode
//
// Read-first means that on a clock edge, the read data returned for a
// given address reflects the memory contents before any write updates
// performed in that same clock edge become visible.
//
// Notes:
// - The RAM is modeled as a shared memory array accessed by two ports.
// - Because both ports can write the same array, some simulators/lint
//   tools may warn about multiple drivers; the original verilator lint
//   pragmas are preserved.
// - rst0_i and rst1_i exist in the interface for compatibility, but
//   they are not used internally in this implementation.
//---------------------------------------------------------------------
`timescale 1ns/1ps


module tcm_mem_ram
(
	// Inputs
	input  logic        clk0_i,
	input  logic        rst0_i,
	input  logic [12:0] addr0_i,
	input  logic [63:0] data0_i,
	input  logic [7:0]  wr0_i,
	input  logic        clk1_i,
	input  logic        rst1_i,
	input  logic [12:0] addr1_i,
	input  logic [63:0] data1_i,
	input  logic [7:0]  wr1_i,

	// Outputs
	output logic [63:0] data0_o,
	output logic [63:0] data1_o
);

	//-----------------------------------------------------------------
	// Dual-Port RAM Storage
	//-----------------------------------------------------------------
	// 8192 x 64-bit memory array
	/* verilator lint_off MULTIDRIVEN */
	reg [63:0] ram [0:8191] /*verilator public*/;
	/* verilator lint_on MULTIDRIVEN */

	//-----------------------------------------------------------------
	// Registered Read Data Per Port
	//-----------------------------------------------------------------
	logic [63:0] ram_read0_q;
	logic [63:0] ram_read1_q;

	//-----------------------------------------------------------------
	// Port 0
	//-----------------------------------------------------------------
	// Synchronous byte-write and synchronous registered read.
	// Read-first behavior is preserved by reading ram[addr0_i] into the
	// output register in the same always_ff block after the write tests,
	// matching the original model behavior.
	always @(posedge clk0_i) begin
		if (wr0_i[0])
			ram[addr0_i][7:0]   <= data0_i[7:0];
		if (wr0_i[1])
			ram[addr0_i][15:8]  <= data0_i[15:8];
		if (wr0_i[2])
			ram[addr0_i][23:16] <= data0_i[23:16];
		if (wr0_i[3])
			ram[addr0_i][31:24] <= data0_i[31:24];
		if (wr0_i[4])
			ram[addr0_i][39:32] <= data0_i[39:32];
		if (wr0_i[5])
			ram[addr0_i][47:40] <= data0_i[47:40];
		if (wr0_i[6])
			ram[addr0_i][55:48] <= data0_i[55:48];
		if (wr0_i[7])
			ram[addr0_i][63:56] <= data0_i[63:56];

		ram_read0_q <= ram[addr0_i];
	end

	//-----------------------------------------------------------------
	// Port 1
	//-----------------------------------------------------------------
	// Same behavior as port 0, but independent clock/address/data path.
	always @(posedge clk1_i) begin
		if (wr1_i[0])
			ram[addr1_i][7:0]   <= data1_i[7:0];
		if (wr1_i[1])
			ram[addr1_i][15:8]  <= data1_i[15:8];
		if (wr1_i[2])
			ram[addr1_i][23:16] <= data1_i[23:16];
		if (wr1_i[3])
			ram[addr1_i][31:24] <= data1_i[31:24];
		if (wr1_i[4])
			ram[addr1_i][39:32] <= data1_i[39:32];
		if (wr1_i[5])
			ram[addr1_i][47:40] <= data1_i[47:40];
		if (wr1_i[6])
			ram[addr1_i][55:48] <= data1_i[55:48];
		if (wr1_i[7])
			ram[addr1_i][63:56] <= data1_i[63:56];

		ram_read1_q <= ram[addr1_i];
	end

	//-----------------------------------------------------------------
	// Outputs
	//-----------------------------------------------------------------
	assign data0_o = ram_read0_q;
	assign data1_o = ram_read1_q;

endmodule
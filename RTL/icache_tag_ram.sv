//==============================================================
// Instruction Cache Tag RAM
// Single-Port RAM
// Read-First Mode
//==============================================================
`timescale 1ns/1ps
module icache_tag_ram
(
	// ---------------------------------------------------------
	// Inputs
	// ---------------------------------------------------------
	input  logic        clk_i,      // Clock signal
	input  logic        rst_i,      // Reset (not used internally)
	input  logic [7:0]  addr_i,     // Address input (8 bits -> 256 entries)
	input  logic [19:0] data_i,     // Tag data input (written to RAM)
	input  logic        wr_i,       // Write enable

	// ---------------------------------------------------------
	// Outputs
	// ---------------------------------------------------------
	output logic [19:0] data_o      // Tag data output
);


//-----------------------------------------------------------------
// Single Port Tag RAM Declaration
//-----------------------------------------------------------------
// Memory structure:
// 256 entries × 20 bits
//-----------------------------------------------------------------
logic [19:0] ram [255:0];    // Tag memory array
logic [19:0] ram_read_q;     // Registered read data


//-----------------------------------------------------------------
// Memory Access Logic
//-----------------------------------------------------------------
// Behaviour:
// - Write occurs synchronously on the clock edge
// - Read is synchronous (data available next cycle)
// - Mode: Read-First
//-----------------------------------------------------------------
always_ff @(posedge clk_i)
begin
	// Write operation
	if (wr_i)
		ram[addr_i] <= data_i;

	// Read operation
	ram_read_q <= ram[addr_i];
end


//-----------------------------------------------------------------
// Output assignment
//-----------------------------------------------------------------
assign data_o = ram_read_q;


endmodule
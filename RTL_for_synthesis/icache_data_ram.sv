//==============================================================
// Instruction Cache Data RAM
// 8KB Single-Port RAM
// Read-First Mode
//==============================================================
`timescale 1ns/1ps
module icache_data_ram
(
	// ---------------------------------------------------------
	// Inputs
	// ---------------------------------------------------------
	input  logic         clk_i,      // Clock signal
	input  logic         rst_i,      // Reset (not used internally here)
	input  logic [9:0]   addr_i,     // Address input (10 bits -> 1024 locations)
	input  logic [63:0]  data_i,     // Data input for write
	input  logic         wr_i,       // Write enable

	// ---------------------------------------------------------
	// Outputs
	// ---------------------------------------------------------
	output logic [63:0]  data_o      // Data output (read data)
);


//-----------------------------------------------------------------
// Single Port RAM Declaration
//-----------------------------------------------------------------
// Memory array:
// 1024 entries * 64 bits = 8192 bytes = 8KB
//-----------------------------------------------------------------
logic [63:0] ram [1023:0];     // Main memory array
logic [63:0] ram_read_q;       // Registered read data

//-----------------------------------------------------------------
// Memory Access Logic
//-----------------------------------------------------------------
// Behaviour:
// - Write is synchronous to the clock
// - Read is also synchronous (data returned next cycle)
// - Mode: Read-First
//-----------------------------------------------------------------
integer i;

always_ff @(posedge clk_i) begin
  if (rst_i) begin
	ram_read_q <= 64'h0;
	for (i = 0; i < 1024; i++) begin
	  ram[i] <= 64'h0;
	end
  end
  else begin
	if (wr_i)
	  ram[addr_i] <= data_i;
	ram_read_q <= ram[addr_i];
  end
end

//-----------------------------------------------------------------
// Output assignment
//-----------------------------------------------------------------
assign data_o = ram_read_q;

endmodule
`timescale 1ns/1ps
`ifndef COHERENCE_DEFS_SV
`define COHERENCE_DEFS_SV

package coherence_pkg;

	typedef enum logic [1:0] {
		SNOOP_BUSRD   = 2'b00,
		SNOOP_BUSRDX  = 2'b01,
		SNOOP_BUSUPGR = 2'b10,
		SNOOP_NONE    = 2'b11
	} snoop_cmd_t;

	typedef enum logic [1:0] {
		CTRL_IDLE = 2'b00,
		CTRL_WAIT = 2'b01,
		CTRL_DONE = 2'b10
	} coh_ctrl_state_t;

endpackage

`endif
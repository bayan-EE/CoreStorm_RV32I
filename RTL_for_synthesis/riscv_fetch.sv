//==============================================================
// riscv_fetch - TWO-WAY SUPERSCALAR FETCH STAGE (RV32)
//
// This module fetches TWO instructions per cycle (a bundle),
// assuming ILEN=32, so each bundle is 64 bits: {inst1, inst0}.
//
// Handshakes:
// - With ID stage: fetch_valid_o / fetch_accept_i
// - With Instruction Cache:
//     * Request: icache_rd_o / icache_accept_i
//     * Response: icache_valid_i / icache_bundle_i
//
//==============================================================
module riscv_fetch #(
  // ------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------

  // Width of program counter and addresses
  parameter int unsigned XLEN = 32,

  // Width of a single instruction (RV32I = 32 bits)
  parameter int unsigned ILEN = 32,

  // Initial PC value after reset
  parameter logic [XLEN-1:0] RESET_PC = 32'h0000_0000
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,            // Active-low reset

  // ------------------------------------------------------------
  // Interface to ID stage
  // ------------------------------------------------------------
  input  logic                 fetch_accept_i,   // ID is ready to accept a bundle

  // ------------------------------------------------------------
  // Redirect interface (branch / jump / exception)
  // ------------------------------------------------------------
  input  logic                 branch_request_i, // Request to redirect PC
  input  logic [XLEN-1:0]       branch_pc_i,      // New PC value after redirect

  // ------------------------------------------------------------
  // Instruction cache interface
  // ------------------------------------------------------------
  input  logic                 icache_accept_i,  // Cache accepted the request
  input  logic                 icache_valid_i,   // Cache response is valid
  input  logic [2*ILEN-1:0]     icache_bundle_i,  // {inst1, inst0}

  output logic                 icache_rd_o,      // Read request to I$
  output logic [XLEN-1:0]       icache_pc_o,      // Base PC of the bundle

  // ------------------------------------------------------------
  // Output to ID stage
  // ------------------------------------------------------------
  output logic                 fetch_valid_o,    // Bundle is valid
  output logic [XLEN-1:0]       fetch_pc_o,       // PC of inst0
  output logic [2*ILEN-1:0]     fetch_bundle_o    // {inst1, inst0}
);

  // ------------------------------------------------------------
  // Derived constants
  // ------------------------------------------------------------

  // Number of bytes per instruction (32 bits = 4 bytes)
  localparam int unsigned INSTR_BYTES  = ILEN / 8;

  // Number of bytes per bundle (2 instructions)
  localparam int unsigned BUNDLE_BYTES = 2 * INSTR_BYTES;

  // ------------------------------------------------------------
  // Internal state
  // ------------------------------------------------------------

  // Current fetch PC (points to inst0 of the next bundle)
  logic [XLEN-1:0] pc_q;

  // PC associated with the outstanding cache request (latched when request is issued)
  logic [XLEN-1:0] req_pc_q;

  // One-entry response buffer (skid buffer) for ID stalls
  logic            buf_valid_q;        // Buffer contains a valid bundle
  logic [XLEN-1:0] buf_pc_q;           // PC of the buffered bundle
  logic [2*ILEN-1:0] buf_bundle_q;     // Buffered instructions

  // ID consumes the bundle when valid && accept
  wire consume_to_id = fetch_valid_o && fetch_accept_i;

  // ------------------------------------------------------------
  // Outputs to ID stage (driven from the buffer)
  // ------------------------------------------------------------
  assign fetch_valid_o  = buf_valid_q;
  assign fetch_pc_o     = buf_pc_q;
  assign fetch_bundle_o = buf_bundle_q;

  // ------------------------------------------------------------
  // Cache request logic
  // ------------------------------------------------------------
  // IMPORTANT:
  // We must not issue multiple requests for the same PC while waiting
  // for a response. Therefore we keep a small FSM that tracks:
  //   IDLE -> WAIT_ACCEPT -> WAIT_RESP -> IDLE
  //
  // - WAIT_ACCEPT: assert icache_rd_o until icache_accept_i
  // - WAIT_RESP  : wait for icache_valid_i, then fill buffer
  // ------------------------------------------------------------

  typedef enum logic [1:0] {
	REQ_IDLE       = 2'd0,
	REQ_WAIT_ACCEPT= 2'd1,
	REQ_WAIT_RESP  = 2'd2
  } req_state_t;

  req_state_t req_state_q;

  // We need to fetch only if the response buffer is empty
  wire need_fetch = !buf_valid_q;

  // Issue a new request only if:
  // - we need a fetch (buffer empty)
  // - AND we are not already handling a request (REQ_IDLE)
  wire issue_req = need_fetch && (req_state_q == REQ_IDLE);

  // Read request to instruction cache:
  // - In WAIT_ACCEPT we keep rd asserted (level) until accept arrives
  // - When issuing a fresh request, rd is asserted as well
  assign icache_rd_o = (req_state_q == REQ_WAIT_ACCEPT) || issue_req;

  // Cache PC output:
  // - While a request is in progress, keep PC stable (req_pc_q)
  // - Otherwise, present the current fetch PC (pc_q)
  assign icache_pc_o = (req_state_q != REQ_IDLE) ? req_pc_q : pc_q;

  // ------------------------------------------------------------
  // Sequential logic
  // ------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
	if (!rst_ni) begin
	  // Reset state
	  pc_q         <= RESET_PC;

	  req_pc_q     <= RESET_PC;
	  req_state_q  <= REQ_IDLE;

	  buf_valid_q  <= 1'b0;
	  buf_pc_q     <= '0;
	  buf_bundle_q <= '0;

	end else begin
	  // --------------------------------------------------------
	  // Redirect handling (flush pipeline and jump to new PC)
	  // --------------------------------------------------------
	  if (branch_request_i) begin
		pc_q        <= branch_pc_i;

		// Flush outstanding request and buffered response
		req_state_q <= REQ_IDLE;
		req_pc_q    <= branch_pc_i;

		buf_valid_q <= 1'b0;
		buf_pc_q    <= '0;
		buf_bundle_q<= '0;

	  end else begin
		// ------------------------------------------------------
		// Cache request management
		// ------------------------------------------------------

		// Start a new request (latch PC and move to WAIT_ACCEPT)
		if (issue_req) begin
		  req_pc_q    <= pc_q;
		  req_state_q <= REQ_WAIT_ACCEPT;
		end

		// If cache accepted the request, move to WAIT_RESP
		if (req_state_q == REQ_WAIT_ACCEPT) begin
		  if (icache_accept_i) begin
			req_state_q <= REQ_WAIT_RESP;
		  end
		end

		// ------------------------------------------------------
		// Cache response handling
		// ------------------------------------------------------
		// When response arrives, capture it into buffer and go back to IDLE.
		// Note: response is associated with req_pc_q (stable while request active).
		if (req_state_q == REQ_WAIT_RESP) begin
		  if (icache_valid_i) begin
			buf_valid_q  <= 1'b1;
			buf_pc_q     <= req_pc_q;
			buf_bundle_q <= icache_bundle_i;

			req_state_q  <= REQ_IDLE;
		  end
		end

		// ------------------------------------------------------
		// ID stage consumption
		// ------------------------------------------------------
		// Once ID accepts the bundle, advance PC by one bundle
		if (consume_to_id) begin
		  buf_valid_q <= 1'b0;
		  pc_q        <= pc_q + BUNDLE_BYTES[XLEN-1:0];
		end
	  end
	end
  end

endmodule

module riscv_regfile
#(
	parameter bit SUPPORT_REGFILE_XILINX = 1'b0,
	parameter bit SUPPORT_DUAL_ISSUE     = 1'b1
)
(
	input  logic        clk_i,
	input  logic        rst_i,
	input  logic [4:0]  rd0_i,
	input  logic [4:0]  rd1_i,
	input  logic [31:0] rd0_value_i,
	input  logic [31:0] rd1_value_i,
	input  logic [4:0]  ra0_i,
	input  logic [4:0]  rb0_i,
	input  logic [4:0]  ra1_i,
	input  logic [4:0]  rb1_i,

	output logic [31:0] ra0_value_o,
	output logic [31:0] rb0_value_o,
	output logic [31:0] ra1_value_o,
	output logic [31:0] rb1_value_o
);


generate

//-----------------------------------------------------------------
// Xilinx specific register file (dual issue)
//-----------------------------------------------------------------
if (SUPPORT_REGFILE_XILINX && SUPPORT_DUAL_ISSUE) begin : REGFILE_XILINX

	logic [31:0] ra0_value_w [0:1];
	logic [31:0] rb0_value_w [0:1];
	logic [31:0] ra1_value_w [0:1];
	logic [31:0] rb1_value_w [0:1];

	logic [31:0] reg_src_q;
	logic [31:0] reg_src_r;

	riscv_xilinx_2r1w u_a_0 (
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.rd0_i      (rd0_i),
		.rd0_value_i(rd0_value_i),
		.ra_i       (ra0_i),
		.rb_i       (rb0_i),
		.ra_value_o (ra0_value_w[0]),
		.rb_value_o (rb0_value_w[0])
	);

	riscv_xilinx_2r1w u_a_1 (
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.rd0_i      (rd1_i),
		.rd0_value_i(rd1_value_i),
		.ra_i       (ra0_i),
		.rb_i       (rb0_i),
		.ra_value_o (ra0_value_w[1]),
		.rb_value_o (rb0_value_w[1])
	);

	riscv_xilinx_2r1w u_b_0 (
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.rd0_i      (rd0_i),
		.rd0_value_i(rd0_value_i),
		.ra_i       (ra1_i),
		.rb_i       (rb1_i),
		.ra_value_o (ra1_value_w[0]),
		.rb_value_o (rb1_value_w[0])
	);

	riscv_xilinx_2r1w u_b_1 (
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.rd0_i      (rd1_i),
		.rd0_value_i(rd1_value_i),
		.ra_i       (ra1_i),
		.rb_i       (rb1_i),
		.ra_value_o (ra1_value_w[1]),
		.rb_value_o (rb1_value_w[1])
	);

	always_comb begin
		reg_src_r = reg_src_q;

		reg_src_r[rd0_i] = 1'b0;
		reg_src_r[rd1_i] = 1'b1;
		reg_src_r[5'd0]  = 1'b0;
	end

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i)
			reg_src_q <= 32'b0;
		else
			reg_src_q <= reg_src_r;
	end

	assign ra0_value_o = reg_src_q[ra0_i] ? ra0_value_w[1] : ra0_value_w[0];
	assign rb0_value_o = reg_src_q[rb0_i] ? rb0_value_w[1] : rb0_value_w[0];
	assign ra1_value_o = reg_src_q[ra1_i] ? ra1_value_w[1] : ra1_value_w[0];
	assign rb1_value_o = reg_src_q[rb1_i] ? rb1_value_w[1] : rb1_value_w[0];

end

//-----------------------------------------------------------------
// Xilinx specific register file (single issue)
//-----------------------------------------------------------------
else if (SUPPORT_REGFILE_XILINX && !SUPPORT_DUAL_ISSUE) begin : REGFILE_XILINX_SINGLE

	riscv_xilinx_2r1w u_reg (
		.clk_i      (clk_i),
		.rst_i      (rst_i),
		.rd0_i      (rd0_i),
		.rd0_value_i(rd0_value_i),
		.ra_i       (ra0_i),
		.rb_i       (rb0_i),
		.ra_value_o (ra0_value_o),
		.rb_value_o (rb0_value_o)
	);

	assign ra1_value_o = 32'h00000000;
	assign rb1_value_o = 32'h00000000;

end

//-----------------------------------------------------------------
// Flop based register file
//-----------------------------------------------------------------
else begin : REGFILE

	logic [31:0] regs_q [0:31];
	integer i;

	// simulation friendly names
	wire [31:0] x0_zero_w = 32'h00000000;
	wire [31:0] x1_ra_w   = regs_q[1];
	wire [31:0] x2_sp_w   = regs_q[2];
	wire [31:0] x3_gp_w   = regs_q[3];
	wire [31:0] x4_tp_w   = regs_q[4];
	wire [31:0] x5_t0_w   = regs_q[5];
	wire [31:0] x6_t1_w   = regs_q[6];
	wire [31:0] x7_t2_w   = regs_q[7];
	wire [31:0] x8_s0_w   = regs_q[8];
	wire [31:0] x9_s1_w   = regs_q[9];
	wire [31:0] x10_a0_w  = regs_q[10];
	wire [31:0] x11_a1_w  = regs_q[11];
	wire [31:0] x12_a2_w  = regs_q[12];
	wire [31:0] x13_a3_w  = regs_q[13];
	wire [31:0] x14_a4_w  = regs_q[14];
	wire [31:0] x15_a5_w  = regs_q[15];
	wire [31:0] x16_a6_w  = regs_q[16];
	wire [31:0] x17_a7_w  = regs_q[17];
	wire [31:0] x18_s2_w  = regs_q[18];
	wire [31:0] x19_s3_w  = regs_q[19];
	wire [31:0] x20_s4_w  = regs_q[20];
	wire [31:0] x21_s5_w  = regs_q[21];
	wire [31:0] x22_s6_w  = regs_q[22];
	wire [31:0] x23_s7_w  = regs_q[23];
	wire [31:0] x24_s8_w  = regs_q[24];
	wire [31:0] x25_s9_w  = regs_q[25];
	wire [31:0] x26_s10_w = regs_q[26];
	wire [31:0] x27_s11_w = regs_q[27];
	wire [31:0] x28_t3_w  = regs_q[28];
	wire [31:0] x29_t4_w  = regs_q[29];
	wire [31:0] x30_t5_w  = regs_q[30];
	wire [31:0] x31_t6_w  = regs_q[31];

	//-----------------------------------------------------------------
	// synchronous writes
	//-----------------------------------------------------------------
	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			for (i = 0; i < 32; i = i + 1)
				regs_q[i] <= 32'h00000000;
		end
		else begin
			regs_q[0] <= 32'h00000000;

			for (i = 1; i < 32; i = i + 1) begin
				if (rd0_i == i[4:0])
					regs_q[i] <= rd0_value_i;
				else if (rd1_i == i[4:0])
					regs_q[i] <= rd1_value_i;
			end
		end
	end

	//-----------------------------------------------------------------
	// asynchronous reads
	//-----------------------------------------------------------------
	always_comb begin
		ra0_value_o = (ra0_i == 5'd0) ? 32'h00000000 : regs_q[ra0_i];
		rb0_value_o = (rb0_i == 5'd0) ? 32'h00000000 : regs_q[rb0_i];
		ra1_value_o = (ra1_i == 5'd0) ? 32'h00000000 : regs_q[ra1_i];
		rb1_value_o = (rb1_i == 5'd0) ? 32'h00000000 : regs_q[rb1_i];
	end

`ifdef verilator
	function automatic [31:0] get_register(input logic [4:0] r); /*verilator public*/
		if (r == 5'd0)
			get_register = 32'h00000000;
		else
			get_register = regs_q[r];
	endfunction

	function automatic void set_register(input logic [4:0] r, input logic [31:0] value); /*verilator public*/
	endfunction
`endif

end

endgenerate

endmodule
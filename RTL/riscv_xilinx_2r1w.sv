module riscv_xilinx_2r1w
(
	input  logic        clk_i,
	input  logic        rst_i,
	input  logic [4:0]  rd0_i,
	input  logic [31:0] rd0_value_i,
	input  logic [4:0]  ra_i,
	input  logic [4:0]  rb_i,
	output logic [31:0] ra_value_o,
	output logic [31:0] rb_value_o
);
	logic [31:0] reg_rs1_w;
	logic [31:0] reg_rs2_w;
	logic [31:0] rs1_0_15_w;
	logic [31:0] rs1_16_31_w;
	logic [31:0] rs2_0_15_w;
	logic [31:0] rs2_16_31_w;
	logic        write_enable_w;
	logic        write_banka_w;
	logic        write_bankb_w;

	logic [31:0] bank_a_q [0:15];
	logic [31:0] bank_b_q [0:15];

	integer i;

	assign write_enable_w = (rd0_i != 5'b00000);
	assign write_banka_w  = write_enable_w & ~rd0_i[4];
	assign write_bankb_w  = write_enable_w &  rd0_i[4];

	always_ff @(posedge clk_i or posedge rst_i) begin
		if (rst_i) begin
			for (i = 0; i < 16; i = i + 1) begin
				bank_a_q[i] <= 32'h00000000;
				bank_b_q[i] <= 32'h00000000;
			end
		end
		else begin
			bank_a_q[0] <= 32'h00000000;

			if (write_banka_w)
				bank_a_q[rd0_i[3:0]] <= rd0_value_i;

			if (write_bankb_w)
				bank_b_q[rd0_i[3:0]] <= rd0_value_i;
		end
	end

	assign rs1_0_15_w  = bank_a_q[ra_i[3:0]];
	assign rs1_16_31_w = bank_b_q[ra_i[3:0]];
	assign rs2_0_15_w  = bank_a_q[rb_i[3:0]];
	assign rs2_16_31_w = bank_b_q[rb_i[3:0]];

	assign reg_rs1_w = (ra_i[4] == 1'b0) ? rs1_0_15_w  : rs1_16_31_w;
	assign reg_rs2_w = (rb_i[4] == 1'b0) ? rs2_0_15_w  : rs2_16_31_w;

	always_comb begin
		if (ra_i == 5'b00000)
			ra_value_o = 32'h00000000;
		else
			ra_value_o = reg_rs1_w;

		if (rb_i == 5'b00000)
			rb_value_o = 32'h00000000;
		else
			rb_value_o = reg_rs2_w;
	end

endmodule
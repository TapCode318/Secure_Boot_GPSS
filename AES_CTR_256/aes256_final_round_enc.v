module aes256_final_round_enc(
	input [127:0] state_in,
	input [127:0] round_key,
	output [127:0] state_out
);

wire [127:0] sb_out;
wire [127:0] sr_out;

SubBytes u_subytes(
	.oriBytes (state_in),
	.subBytes (sb_out)
);

ShiftRows u_shiftrows(
	.in (sb_out),
	.out (sr_out)
);

AddRoundKey u_addroundkey (
	.state (sr_out),
	.roundKey (round_key),
	.stateOut (state_out)
);

endmodule
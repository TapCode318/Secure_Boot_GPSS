module aes256_round_enc (
    input  [127:0] state_in,
    input  [127:0] round_key,
    output [127:0] state_out
);

    wire [127:0] sb_out;
    wire [127:0] sr_out;
    wire [127:0] mc_out;

    SubBytes u_subbytes (
        .oriBytes (state_in),
        .subBytes (sb_out)
    );

    ShiftRows u_shiftrows (
        .in  (sb_out),
        .out (sr_out)
    );

    MixColumns u_mixcolumns (
        .stateIn  (sr_out),
        .stateOut (mc_out)
    );

    AddRoundKey u_addroundkey (
        .state    (mc_out),
        .roundKey (round_key),
        .stateOut (state_out)
    );

endmodule
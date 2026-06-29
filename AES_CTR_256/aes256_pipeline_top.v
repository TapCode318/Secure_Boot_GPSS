module aes256_pipeline_top (
    input              clk,
    input              rst,

    input              key_load,
    input      [255:0] key_in,

    input              valid_in,
    input      [127:0] data_in,

    output             valid_out,
    output     [127:0] data_out
);

    localparam Nk = 8;
    localparam Nr = 14;
	 
    wire [1919:0] all_keys_wire;
    reg  [1919:0] all_keys_reg;

    KeyExpansion #(Nk, Nr) u_keyexp (
        .keyIn   (key_in),
        .keysOut (all_keys_wire)
    );

    always @(posedge clk or posedge rst) begin
        if (rst)
            all_keys_reg <= 1920'd0;
        else if (key_load)
            all_keys_reg <= all_keys_wire;
    end

    wire [127:0] rk0;
    wire [127:0] rk1;
    wire [127:0] rk2;
    wire [127:0] rk3;
    wire [127:0] rk4;
    wire [127:0] rk5;
    wire [127:0] rk6;
    wire [127:0] rk7;
    wire [127:0] rk8;
    wire [127:0] rk9;
    wire [127:0] rk10;
    wire [127:0] rk11;
    wire [127:0] rk12;
    wire [127:0] rk13;
    wire [127:0] rk14;

    assign rk0  = all_keys_reg[1919:1792];
    assign rk1  = all_keys_reg[1791:1664];
    assign rk2  = all_keys_reg[1663:1536];
    assign rk3  = all_keys_reg[1535:1408];
    assign rk4  = all_keys_reg[1407:1280];
    assign rk5  = all_keys_reg[1279:1152];
    assign rk6  = all_keys_reg[1151:1024];
    assign rk7  = all_keys_reg[1023:896];
    assign rk8  = all_keys_reg[895:768];
    assign rk9  = all_keys_reg[767:640];
    assign rk10 = all_keys_reg[639:512];
    assign rk11 = all_keys_reg[511:384];
    assign rk12 = all_keys_reg[383:256];
    assign rk13 = all_keys_reg[255:128];
    assign rk14 = all_keys_reg[127:0];

    reg [14:0] valid_pipe;

    reg [127:0] stage0_reg;
    reg [127:0] stage1_reg;
    reg [127:0] stage2_reg;
    reg [127:0] stage3_reg;
    reg [127:0] stage4_reg;
    reg [127:0] stage5_reg;
    reg [127:0] stage6_reg;
    reg [127:0] stage7_reg;
    reg [127:0] stage8_reg;
    reg [127:0] stage9_reg;
    reg [127:0] stage10_reg;
    reg [127:0] stage11_reg;
    reg [127:0] stage12_reg;
    reg [127:0] stage13_reg;
    reg [127:0] stage14_reg;

    wire [127:0] stage0_next;
    wire [127:0] stage1_next;
    wire [127:0] stage2_next;
    wire [127:0] stage3_next;
    wire [127:0] stage4_next;
    wire [127:0] stage5_next;
    wire [127:0] stage6_next;
    wire [127:0] stage7_next;
    wire [127:0] stage8_next;
    wire [127:0] stage9_next;
    wire [127:0] stage10_next;
    wire [127:0] stage11_next;
    wire [127:0] stage12_next;
    wire [127:0] stage13_next;
    wire [127:0] stage14_next;

    AddRoundKey u_ark0 (
        .state    (data_in),
        .roundKey (rk0),
        .stateOut (stage0_next)
    );

    aes256_round_enc u_round1 (
        .state_in  (stage0_reg),
        .round_key (rk1),
        .state_out (stage1_next)
    );

    aes256_round_enc u_round2 (
        .state_in  (stage1_reg),
        .round_key (rk2),
        .state_out (stage2_next)
    );

    aes256_round_enc u_round3 (
        .state_in  (stage2_reg),
        .round_key (rk3),
        .state_out (stage3_next)
    );

    aes256_round_enc u_round4 (
        .state_in  (stage3_reg),
        .round_key (rk4),
        .state_out (stage4_next)
    );

    aes256_round_enc u_round5 (
        .state_in  (stage4_reg),
        .round_key (rk5),
        .state_out (stage5_next)
    );

    aes256_round_enc u_round6 (
        .state_in  (stage5_reg),
        .round_key (rk6),
        .state_out (stage6_next)
    );

    aes256_round_enc u_round7 (
        .state_in  (stage6_reg),
        .round_key (rk7),
        .state_out (stage7_next)
    );

    aes256_round_enc u_round8 (
        .state_in  (stage7_reg),
        .round_key (rk8),
        .state_out (stage8_next)
    );

    aes256_round_enc u_round9 (
        .state_in  (stage8_reg),
        .round_key (rk9),
        .state_out (stage9_next)
    );

    aes256_round_enc u_round10 (
        .state_in  (stage9_reg),
        .round_key (rk10),
        .state_out (stage10_next)
    );

    aes256_round_enc u_round11 (
        .state_in  (stage10_reg),
        .round_key (rk11),
        .state_out (stage11_next)
    );

    aes256_round_enc u_round12 (
        .state_in  (stage11_reg),
        .round_key (rk12),
        .state_out (stage12_next)
    );

    aes256_round_enc u_round13 (
        .state_in  (stage12_reg),
        .round_key (rk13),
        .state_out (stage13_next)
    );

    aes256_final_round_enc u_final_round (
        .state_in  (stage13_reg),
        .round_key (rk14),
        .state_out (stage14_next)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            stage0_reg  <= 128'd0;
            stage1_reg  <= 128'd0;
            stage2_reg  <= 128'd0;
            stage3_reg  <= 128'd0;
            stage4_reg  <= 128'd0;
            stage5_reg  <= 128'd0;
            stage6_reg  <= 128'd0;
            stage7_reg  <= 128'd0;
            stage8_reg  <= 128'd0;
            stage9_reg  <= 128'd0;
            stage10_reg <= 128'd0;
            stage11_reg <= 128'd0;
            stage12_reg <= 128'd0;
            stage13_reg <= 128'd0;
            stage14_reg <= 128'd0;
            valid_pipe  <= 15'd0;
        end
        else begin
            // Shift valid
            valid_pipe[0]  <= valid_in;
            valid_pipe[1]  <= valid_pipe[0];
            valid_pipe[2]  <= valid_pipe[1];
            valid_pipe[3]  <= valid_pipe[2];
            valid_pipe[4]  <= valid_pipe[3];
            valid_pipe[5]  <= valid_pipe[4];
            valid_pipe[6]  <= valid_pipe[5];
            valid_pipe[7]  <= valid_pipe[6];
            valid_pipe[8]  <= valid_pipe[7];
            valid_pipe[9]  <= valid_pipe[8];
            valid_pipe[10] <= valid_pipe[9];
            valid_pipe[11] <= valid_pipe[10];
            valid_pipe[12] <= valid_pipe[11];
            valid_pipe[13] <= valid_pipe[12];
            valid_pipe[14] <= valid_pipe[13];

            // Shift data
            if (valid_in)
                stage0_reg <= stage0_next;

            if (valid_pipe[0])
                stage1_reg <= stage1_next;

            if (valid_pipe[1])
                stage2_reg <= stage2_next;

            if (valid_pipe[2])
                stage3_reg <= stage3_next;

            if (valid_pipe[3])
                stage4_reg <= stage4_next;

            if (valid_pipe[4])
                stage5_reg <= stage5_next;

            if (valid_pipe[5])
                stage6_reg <= stage6_next;

            if (valid_pipe[6])
                stage7_reg <= stage7_next;

            if (valid_pipe[7])
                stage8_reg <= stage8_next;

            if (valid_pipe[8])
                stage9_reg <= stage9_next;

            if (valid_pipe[9])
                stage10_reg <= stage10_next;

            if (valid_pipe[10])
                stage11_reg <= stage11_next;

            if (valid_pipe[11])
                stage12_reg <= stage12_next;

            if (valid_pipe[12])
                stage13_reg <= stage13_next;

            if (valid_pipe[13])
                stage14_reg <= stage14_next;
        end
    end

    assign data_out  = stage14_reg;
    assign valid_out = valid_pipe[14];

endmodule
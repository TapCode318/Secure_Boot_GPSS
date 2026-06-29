`timescale 1ns/1ps

module rsa2048_modmul (
    input  wire          clk_i,
    input  wire          rst_i,
    input  wire          start_i,
    input  wire [2047:0] a_i,
    input  wire [2047:0] b_i,
    input  wire [2047:0] n_i,
    output reg           busy_o,
    output reg           done_o,
    output reg  [2047:0] result_o
);

    reg [2048:0] res_q;
    reg [2048:0] a_q;
    reg [2047:0] b_q;
    reg [2047:0] n_q;
    reg [11:0]   bit_cnt_q;

    reg [2048:0] tmp_res;
    reg [2048:0] tmp_a;

    always @(posedge clk_i) begin
        if (rst_i) begin
            res_q     <= 2049'd0;
            a_q       <= 2049'd0;
            b_q       <= 2048'd0;
            n_q       <= 2048'd0;
            bit_cnt_q <= 12'd0;
            busy_o    <= 1'b0;
            done_o    <= 1'b0;
            result_o  <= 2048'd0;
        end else begin
            done_o <= 1'b0;

            if (start_i && !busy_o) begin
                res_q     <= 2049'd0;
                a_q       <= {1'b0, a_i};
                b_q       <= b_i;
                n_q       <= n_i;
                bit_cnt_q <= 12'd0;
                busy_o    <= 1'b1;
            end else if (busy_o) begin
                tmp_res = res_q;

                if (b_q[0])
                    tmp_res = res_q + a_q;

                if (tmp_res >= {1'b0, n_q})
                    tmp_res = tmp_res - {1'b0, n_q};

                tmp_a = a_q << 1;

                if (tmp_a >= {1'b0, n_q})
                    tmp_a = tmp_a - {1'b0, n_q};

                res_q <= tmp_res;
                a_q   <= tmp_a;
                b_q   <= {1'b0, b_q[2047:1]};

                if (bit_cnt_q == 12'd2047) begin
                    busy_o   <= 1'b0;
                    done_o   <= 1'b1;
                    result_o <= tmp_res[2047:0];
                end else begin
                    bit_cnt_q <= bit_cnt_q + 12'd1;
                end
            end
        end
    end

endmodule
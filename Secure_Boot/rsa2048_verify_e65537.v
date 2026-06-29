`timescale 1ns/1ps

module rsa2048_verify_e65537 (
    input  wire          clk_i,
    input  wire          rst_i,
    input  wire          start_i,
    input  wire [2047:0] signature_i,
    input  wire [2047:0] modulus_n_i,
    output reg           busy_o,
    output reg           done_o,
    output reg  [2047:0] message_o
);

    localparam ST_IDLE       = 3'd0;
    localparam ST_SQ_START   = 3'd1;
    localparam ST_SQ_WAIT    = 3'd2;
    localparam ST_MUL_START  = 3'd3;
    localparam ST_MUL_WAIT   = 3'd4;
    localparam ST_DONE       = 3'd5;

    reg [2:0] state_q;

    reg [2047:0] base_q;
    reg [2047:0] result_q;
    reg [2047:0] n_q;
    reg [4:0]    square_count_q;

    reg          mul_start_q;
    reg [2047:0] mul_a_q;
    reg [2047:0] mul_b_q;

    wire         mul_busy_w;
    wire         mul_done_w;
    wire [2047:0] mul_result_w;

    rsa2048_modmul u_modmul (
        .clk_i    (clk_i),
        .rst_i    (rst_i),
        .start_i  (mul_start_q),
        .a_i      (mul_a_q),
        .b_i      (mul_b_q),
        .n_i      (n_q),
        .busy_o   (mul_busy_w),
        .done_o   (mul_done_w),
        .result_o (mul_result_w)
    );

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q        <= ST_IDLE;
            base_q         <= 2048'd0;
            result_q       <= 2048'd0;
            n_q            <= 2048'd0;
            square_count_q <= 5'd0;

            mul_start_q    <= 1'b0;
            mul_a_q        <= 2048'd0;
            mul_b_q        <= 2048'd0;

            busy_o         <= 1'b0;
            done_o         <= 1'b0;
            message_o      <= 2048'd0;
        end else begin
            done_o      <= 1'b0;
            mul_start_q <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    busy_o <= 1'b0;

                    if (start_i) begin
                        base_q         <= signature_i;
                        result_q       <= signature_i;
                        n_q            <= modulus_n_i;
                        square_count_q <= 5'd0;
                        busy_o         <= 1'b1;
                        state_q        <= ST_SQ_START;
                    end
                end

                ST_SQ_START: begin
                    mul_a_q     <= result_q;
                    mul_b_q     <= result_q;
                    mul_start_q <= 1'b1;
                    state_q     <= ST_SQ_WAIT;
                end

                ST_SQ_WAIT: begin
                    if (mul_done_w) begin
                        result_q <= mul_result_w;

                        if (square_count_q == 5'd15) begin
                            state_q <= ST_MUL_START;
                        end else begin
                            square_count_q <= square_count_q + 5'd1;
                            state_q <= ST_SQ_START;
                        end
                    end
                end

                ST_MUL_START: begin
                    mul_a_q     <= result_q;
                    mul_b_q     <= base_q;
                    mul_start_q <= 1'b1;
                    state_q     <= ST_MUL_WAIT;
                end

                ST_MUL_WAIT: begin
                    if (mul_done_w) begin
                        message_o <= mul_result_w;
                        done_o    <= 1'b1;
                        busy_o    <= 1'b0;
                        state_q   <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    state_q <= ST_IDLE;
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
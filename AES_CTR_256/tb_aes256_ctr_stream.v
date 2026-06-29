`timescale 1ns / 1ps

module tb_aes256_ctr_stream;

reg          tb_clk;
reg          tb_rst;
reg          tb_key_load;
reg  [255:0] tb_key_in;

reg          tb_ctr_load;
reg  [127:0] tb_ctr_init;

reg          tb_valid_in;
reg  [127:0] tb_data_in;
reg          tb_last_in;
reg  [15:0]  tb_keep_in;

wire         tb_ready_in;
wire         tb_valid_out;
wire [127:0] tb_data_out;
wire         tb_last_out;
wire [15:0]  tb_keep_out;
wire [127:0] tb_ctr_dbg;
wire [127:0] tb_keystream_dbg;

aes256_ctr_stream dut (
    .clk           (tb_clk),
    .rst           (tb_rst),
    .key_load      (tb_key_load),
    .key_in        (tb_key_in),
    .ctr_load      (tb_ctr_load),
    .ctr_init      (tb_ctr_init),
    .valid_in      (tb_valid_in),
    .data_in       (tb_data_in),     // ciphertext input
    .last_in       (tb_last_in),
    .keep_in       (tb_keep_in),
    .ready_in      (tb_ready_in),
    .valid_out     (tb_valid_out),
    .data_out      (tb_data_out),    // plaintext output
    .last_out      (tb_last_out),
    .keep_out      (tb_keep_out),
    .ctr_dbg       (tb_ctr_dbg),
    .keystream_dbg (tb_keystream_dbg)
);

initial begin
    tb_clk = 1'b0;
    forever #10 tb_clk = ~tb_clk;
end

task load_key;
    input [255:0] key;
    begin
        @(negedge tb_clk);
        tb_key_in   = key;
        tb_key_load = 1'b1;

        @(negedge tb_clk);
        tb_key_load = 1'b0;
    end
endtask

task load_ctr;
    input [127:0] ctr0;
    begin
        @(negedge tb_clk);
        tb_ctr_init = ctr0;
        tb_ctr_load = 1'b1;

        @(negedge tb_clk);
        tb_ctr_load = 1'b0;
    end
endtask

task send_block;
    input [127:0] block_in;
    input         is_last;
    input [15:0]  keep_mask;
    begin
        @(negedge tb_clk);
        tb_valid_in = 1'b1;
        tb_data_in  = block_in;   // ciphertext block
        tb_last_in  = is_last;
        tb_keep_in  = keep_mask;
    end
endtask

task stop_in;
    begin
        @(negedge tb_clk);
        tb_valid_in = 1'b0;
        tb_data_in  = 128'b0;
        tb_last_in  = 1'b0;
        tb_keep_in  = 16'h0000;
    end
endtask

initial begin
    tb_rst      = 1'b1;
    tb_key_load = 1'b0;
    tb_key_in   = 256'd0;

    tb_ctr_load = 1'b0;
    tb_ctr_init = 128'd0;

    tb_valid_in = 1'b0;
    tb_data_in  = 128'd0;
    tb_last_in  = 1'b0;
    tb_keep_in  = 16'd0;

    #25;
    tb_rst = 1'b0;

    // =========================
    // THAY KEY VA CTR O DAY
    // =========================
    load_key(256'h603deb1015ca71be2b73aef0857d7781_1f352c073b6108d72d9810a30914dff4);
    load_ctr(128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff);

    // =========================
    // THAY CAC BLOCK CIPHERTEXT O DAY
    // data_out se la PLAINTEXT
    // =========================
    send_block(128'h601ec313775789a5b7a7f504bbf3d228, 1'b0, 16'hFFFF);
    send_block(128'hf443e3ca4d62b59aca84e990cacaf5c5, 1'b0, 16'hFFFF);
    send_block(128'h2b0930daa23de94ce87017ba2d84988d, 1'b0, 16'hFFFF);
    send_block(128'hdfc9c58db67aada613c2dd08457941a6, 1'b1, 16'hFFFF);

    stop_in;

    #1000;
    $finish;
end

always @(posedge tb_clk) begin
    if (tb_valid_out) begin
        $display("Time = %0t | plaintext_out = %h | last=%0d | keep=%h | ctr=%h | keystream=%h",
                 $time, tb_data_out, tb_last_out, tb_keep_out, tb_ctr_dbg, tb_keystream_dbg);
    end
end

endmodule
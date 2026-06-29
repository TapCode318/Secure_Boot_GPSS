`timescale 1ns / 1ps

module tb_aes256_pipeline_top;

reg         tb_clk;
reg         tb_rst;
reg         tb_key_load;
reg [255:0] tb_key_in;
reg         tb_valid_in;
reg [127:0] tb_data_in;

wire        tb_valid_out;
wire [127:0] tb_data_out;

aes256_pipeline_top dut (
    .clk      (tb_clk),
    .rst      (tb_rst),
    .key_load (tb_key_load),
    .key_in   (tb_key_in),
    .valid_in (tb_valid_in),
    .data_in  (tb_data_in),
    .valid_out(tb_valid_out),
    .data_out (tb_data_out)
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

task send_block;
    input [127:0] block_in;
    begin
        @(negedge tb_clk);
        tb_valid_in = 1'b1;
        tb_data_in  = block_in;
    end
endtask

task stop_in;
    begin
        @(negedge tb_clk);
        tb_valid_in = 1'b0;
        tb_data_in  = 128'b0;
    end
endtask

initial begin
    tb_rst      = 1'b1;
    tb_key_load = 1'b0;
    tb_key_in   = 256'd0;
    tb_valid_in = 1'b0;
    tb_data_in  = 128'd0;

    #15;
    tb_rst = 1'b0;

    load_key(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f);

    send_block(128'h00112233445566778899aabbccddeeff);
    send_block(128'h31082006120219522452099029082002);

    stop_in;

    #500;
    $finish;
end

always @(posedge tb_clk) begin
    if (tb_valid_out) begin
        $display("Time = %0t | data_out = %h", $time, tb_data_out);
    end
end

endmodule
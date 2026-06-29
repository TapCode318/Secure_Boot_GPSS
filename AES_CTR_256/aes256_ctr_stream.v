module aes256_ctr_stream (
    input              clk,
    input              rst,

    // Load round keys into aes256_pipeline_top.
    // IMPORTANT: assert key_load at least 1 clock before the first valid_in.
    input              key_load,
    input      [255:0] key_in,

    // Initial counter block for CTR mode.
    // Common mapping: ctr_init[127:32] = nonce, ctr_init[31:0] = block counter.
    input              ctr_load,
    input      [127:0] ctr_init,

    // Streaming payload input.
    // For secure boot, data_in is ciphertext from SPI/QSPI flash.
    input              valid_in,
    input      [127:0] data_in,
    input              last_in,
    input      [15:0]  keep_in,

    // Pipeline can accept 1 block every clock once key is already loaded.
    output             ready_in,

    // Streaming payload output.
    // For secure boot, data_out is plaintext that will be fed into SHA.
    output             valid_out,
    output     [127:0] data_out,
    output             last_out,
    output     [15:0]  keep_out,

    // Optional debug/visibility.
    output     [127:0] ctr_dbg,
    output     [127:0] keystream_dbg
);

    localparam LATENCY = 15;

    reg  [127:0] ctr_reg;
    wire [127:0] ctr_for_aes;

    // If ctr_load and valid_in happen in the same cycle,
    // the first AES input block uses ctr_init.
    assign ctr_for_aes = ctr_load ? ctr_init : ctr_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ctr_reg <= 128'd0;
        end
        else begin
            if (ctr_load && valid_in)
                ctr_reg <= ctr_init + 128'd1;
            else if (ctr_load)
                ctr_reg <= ctr_init;
            else if (valid_in)
                ctr_reg <= ctr_reg + 128'd1;
        end
    end

    wire        ks_valid;
    wire [127:0] ks_data;

    aes256_pipeline_top u_aes256_ctr_core (
        .clk      (clk),
        .rst      (rst),
        .key_load (key_load),
        .key_in   (key_in),
        .valid_in (valid_in),
        .data_in  (ctr_for_aes),
        .valid_out(ks_valid),
        .data_out (ks_data)
    );

    reg [127:0] data_pipe_0;
    reg [127:0] data_pipe_1;
    reg [127:0] data_pipe_2;
    reg [127:0] data_pipe_3;
    reg [127:0] data_pipe_4;
    reg [127:0] data_pipe_5;
    reg [127:0] data_pipe_6;
    reg [127:0] data_pipe_7;
    reg [127:0] data_pipe_8;
    reg [127:0] data_pipe_9;
    reg [127:0] data_pipe_10;
    reg [127:0] data_pipe_11;
    reg [127:0] data_pipe_12;
    reg [127:0] data_pipe_13;
    reg [127:0] data_pipe_14;

    reg         last_pipe_0;
    reg         last_pipe_1;
    reg         last_pipe_2;
    reg         last_pipe_3;
    reg         last_pipe_4;
    reg         last_pipe_5;
    reg         last_pipe_6;
    reg         last_pipe_7;
    reg         last_pipe_8;
    reg         last_pipe_9;
    reg         last_pipe_10;
    reg         last_pipe_11;
    reg         last_pipe_12;
    reg         last_pipe_13;
    reg         last_pipe_14;

    reg [15:0]  keep_pipe_0;
    reg [15:0]  keep_pipe_1;
    reg [15:0]  keep_pipe_2;
    reg [15:0]  keep_pipe_3;
    reg [15:0]  keep_pipe_4;
    reg [15:0]  keep_pipe_5;
    reg [15:0]  keep_pipe_6;
    reg [15:0]  keep_pipe_7;
    reg [15:0]  keep_pipe_8;
    reg [15:0]  keep_pipe_9;
    reg [15:0]  keep_pipe_10;
    reg [15:0]  keep_pipe_11;
    reg [15:0]  keep_pipe_12;
    reg [15:0]  keep_pipe_13;
    reg [15:0]  keep_pipe_14;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_pipe_0  <= 128'd0;
            data_pipe_1  <= 128'd0;
            data_pipe_2  <= 128'd0;
            data_pipe_3  <= 128'd0;
            data_pipe_4  <= 128'd0;
            data_pipe_5  <= 128'd0;
            data_pipe_6  <= 128'd0;
            data_pipe_7  <= 128'd0;
            data_pipe_8  <= 128'd0;
            data_pipe_9  <= 128'd0;
            data_pipe_10 <= 128'd0;
            data_pipe_11 <= 128'd0;
            data_pipe_12 <= 128'd0;
            data_pipe_13 <= 128'd0;
            data_pipe_14 <= 128'd0;

            last_pipe_0  <= 1'b0;
            last_pipe_1  <= 1'b0;
            last_pipe_2  <= 1'b0;
            last_pipe_3  <= 1'b0;
            last_pipe_4  <= 1'b0;
            last_pipe_5  <= 1'b0;
            last_pipe_6  <= 1'b0;
            last_pipe_7  <= 1'b0;
            last_pipe_8  <= 1'b0;
            last_pipe_9  <= 1'b0;
            last_pipe_10 <= 1'b0;
            last_pipe_11 <= 1'b0;
            last_pipe_12 <= 1'b0;
            last_pipe_13 <= 1'b0;
            last_pipe_14 <= 1'b0;

            keep_pipe_0  <= 16'd0;
            keep_pipe_1  <= 16'd0;
            keep_pipe_2  <= 16'd0;
            keep_pipe_3  <= 16'd0;
            keep_pipe_4  <= 16'd0;
            keep_pipe_5  <= 16'd0;
            keep_pipe_6  <= 16'd0;
            keep_pipe_7  <= 16'd0;
            keep_pipe_8  <= 16'd0;
            keep_pipe_9  <= 16'd0;
            keep_pipe_10 <= 16'd0;
            keep_pipe_11 <= 16'd0;
            keep_pipe_12 <= 16'd0;
            keep_pipe_13 <= 16'd0;
            keep_pipe_14 <= 16'd0;
        end
        else begin
            data_pipe_0  <= data_in;
            data_pipe_1  <= data_pipe_0;
            data_pipe_2  <= data_pipe_1;
            data_pipe_3  <= data_pipe_2;
            data_pipe_4  <= data_pipe_3;
            data_pipe_5  <= data_pipe_4;
            data_pipe_6  <= data_pipe_5;
            data_pipe_7  <= data_pipe_6;
            data_pipe_8  <= data_pipe_7;
            data_pipe_9  <= data_pipe_8;
            data_pipe_10 <= data_pipe_9;
            data_pipe_11 <= data_pipe_10;
            data_pipe_12 <= data_pipe_11;
            data_pipe_13 <= data_pipe_12;
            data_pipe_14 <= data_pipe_13;

            last_pipe_0  <= last_in;
            last_pipe_1  <= last_pipe_0;
            last_pipe_2  <= last_pipe_1;
            last_pipe_3  <= last_pipe_2;
            last_pipe_4  <= last_pipe_3;
            last_pipe_5  <= last_pipe_4;
            last_pipe_6  <= last_pipe_5;
            last_pipe_7  <= last_pipe_6;
            last_pipe_8  <= last_pipe_7;
            last_pipe_9  <= last_pipe_8;
            last_pipe_10 <= last_pipe_9;
            last_pipe_11 <= last_pipe_10;
            last_pipe_12 <= last_pipe_11;
            last_pipe_13 <= last_pipe_12;
            last_pipe_14 <= last_pipe_13;

            keep_pipe_0  <= keep_in;
            keep_pipe_1  <= keep_pipe_0;
            keep_pipe_2  <= keep_pipe_1;
            keep_pipe_3  <= keep_pipe_2;
            keep_pipe_4  <= keep_pipe_3;
            keep_pipe_5  <= keep_pipe_4;
            keep_pipe_6  <= keep_pipe_5;
            keep_pipe_7  <= keep_pipe_6;
            keep_pipe_8  <= keep_pipe_7;
            keep_pipe_9  <= keep_pipe_8;
            keep_pipe_10 <= keep_pipe_9;
            keep_pipe_11 <= keep_pipe_10;
            keep_pipe_12 <= keep_pipe_11;
            keep_pipe_13 <= keep_pipe_12;
            keep_pipe_14 <= keep_pipe_13;
        end
    end

    assign ready_in      = 1'b1;
    assign valid_out     = ks_valid;
    assign data_out      = data_pipe_14 ^ ks_data;
    assign last_out      = last_pipe_14;
    assign keep_out      = keep_pipe_14;
    assign ctr_dbg       = ctr_for_aes;
    assign keystream_dbg = ks_data;

endmodule

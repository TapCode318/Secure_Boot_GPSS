`timescale 1ns/1ps
`include "rsa_public_key.vh"

module axi_signature_verify_stub #(
    parameter BASE_ADDR     = 32'h70000000,
    parameter ROM_INIT_FILE = "firmware_cipher.hex",
    parameter ROM_WORDS     = 1024,
    parameter FIFO_DEPTH    = 8
)
(
    input  wire         clk_i,
    input  wire         rst_i,

    input  wire         axi_awvalid_i,
    input  wire [31:0]  axi_awaddr_i,
    input  wire [3:0]   axi_awid_i,
    input  wire [7:0]   axi_awlen_i,
    input  wire [1:0]   axi_awburst_i,

    input  wire         axi_wvalid_i,
    input  wire [31:0]  axi_wdata_i,
    input  wire [3:0]   axi_wstrb_i,
    input  wire         axi_wlast_i,

    input  wire         axi_bready_i,
    output reg          axi_awready_o,
    output reg          axi_wready_o,
    output reg          axi_bvalid_o,
    output reg  [1:0]   axi_bresp_o,
    output reg  [3:0]   axi_bid_o,

    input  wire         axi_arvalid_i,
    input  wire [31:0]  axi_araddr_i,
    input  wire [3:0]   axi_arid_i,
    input  wire [7:0]   axi_arlen_i,
    input  wire [1:0]   axi_arburst_i,
    input  wire         axi_rready_i,

    output reg          axi_arready_o,
    output reg          axi_rvalid_o,
    output reg  [31:0]  axi_rdata_o,
    output reg  [1:0]   axi_rresp_o,
    output reg  [3:0]   axi_rid_o,
    output reg          axi_rlast_o
);

    localparam ST_IDLE       = 5'd0;
    localparam ST_SHA_INIT   = 5'd1;
    localparam ST_SHA_START  = 5'd2;
    localparam ST_SHA_FEED   = 5'd3;
    localparam ST_SHA_WAIT   = 5'd4;
    localparam ST_LOAD_SIG   = 5'd5;
    localparam ST_RSA_START  = 5'd6;
    localparam ST_RSA_WAIT   = 5'd7;
    localparam ST_CHECK      = 5'd8;
    localparam ST_DONE       = 5'd9;

    // SHA3-512 DigestInfo prefix for RSA PKCS#1 v1.5:
    // DER = 30 4f 30 0b 06 09 60 86 48 01 65 03 04 02 0a 04 40
    localparam [135:0] SHA3_512_DIGESTINFO_PREFIX =
        136'h304f300b060960864801650304020a0440;

    reg [4:0] state_q;

    reg [31:0] manifest_word_offset_q;
    reg [31:0] manifest_word_count_q;
    reg [31:0] signature_word_offset_q;
    reg [31:0] signature_word_count_q;

    reg busy_q;
    reg done_q;
    reg error_q;
    reg sig_ok_q;

    reg [6:0] load_idx_q;

    reg [511:0]  manifest_hash_q;
    reg [2047:0] signature_q;

    wire [2047:0] pkcs1_expected_em_w =
        {16'h0001,
         {172{8'hff}},
         8'h00,
         SHA3_512_DIGESTINFO_PREFIX,
         manifest_hash_q};

    reg rsa_start_q;
    wire rsa_busy_w;
    wire rsa_done_w;
    wire [2047:0] rsa_message_w;

    reg sha_init_q;
    reg sha_start_q;
    reg sha_valid_q;
    reg [31:0] sha_data_q;
    reg sha_last_q;
    reg [1:0] sha_byte_num_q;

    wire sha_busy_w;
    wire sha_done_w;
    wire [511:0] sha_digest_w;

    reg [31:0] rom [0:ROM_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < ROM_WORDS; i = i + 1)
            rom[i] = 32'd0;

        $readmemh(ROM_INIT_FILE, rom);
    end

    sha3_real_wrapper #(
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_manifest_sha3 (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .init_i          (sha_init_q),
        .start_i         (sha_start_q),
        .data_valid_i    (sha_valid_q),
        .data_i          (sha_data_q),
        .data_is_last_i  (sha_last_q),
        .data_byte_num_i (sha_byte_num_q),
        .busy_o          (sha_busy_w),
        .done_o          (sha_done_w),
        .digest_o        (sha_digest_w)
    );

    rsa2048_verify_e65537 u_rsa_verify (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .start_i     (rsa_start_q),
        .signature_i (signature_q),
        .modulus_n_i (`RSA_PUBLIC_N),
        .busy_o      (rsa_busy_w),
        .done_o      (rsa_done_w),
        .message_o   (rsa_message_w)
    );

    reg        wr_active_q;
    reg [31:0] wr_addr_q;
    reg [7:0]  wr_len_q;
    reg [7:0]  wr_beat_q;
    reg [3:0]  wr_id_q;

    reg [31:0] rd_addr_q;
    reg [7:0]  rd_len_q;
    reg [7:0]  rd_beat_q;
    reg [3:0]  rd_id_q;

    wire [31:0] rd_next_addr_w = rd_addr_q + 32'd4;

    function [31:0] read_reg;
        input [7:0] off;
        begin
            case (off)
                8'h00: read_reg = 32'd0;
                8'h04: read_reg = {28'd0, sig_ok_q, error_q, done_q, busy_q};
                8'h08: read_reg = manifest_word_offset_q;
                8'h0C: read_reg = manifest_word_count_q;
                8'h10: read_reg = signature_word_offset_q;
                8'h14: read_reg = signature_word_count_q;
                default: read_reg = 32'h7000_BAD0;
            endcase
        end
    endfunction

    task write_reg;
        input [7:0]  off;
        input [31:0] data;
        begin
            case (off)
                8'h00: begin
                    if (data[1]) begin
                        state_q         <= ST_IDLE;
                        busy_q          <= 1'b0;
                        done_q          <= 1'b0;
                        error_q         <= 1'b0;
                        sig_ok_q        <= 1'b0;
                        load_idx_q      <= 7'd0;
                        manifest_hash_q <= 512'd0;
                        signature_q     <= 2048'd0;
                    end

                    if (data[0]) begin
                        state_q         <= ST_SHA_INIT;
                        busy_q          <= 1'b1;
                        done_q          <= 1'b0;
                        error_q         <= 1'b0;
                        sig_ok_q        <= 1'b0;
                        load_idx_q      <= 7'd0;
                        manifest_hash_q <= 512'd0;
                        signature_q     <= 2048'd0;
                    end
                end

                8'h08: manifest_word_offset_q  <= data;
                8'h0C: manifest_word_count_q   <= data;
                8'h10: signature_word_offset_q <= data;
                8'h14: signature_word_count_q  <= data;

                default: begin
                end
            endcase
        end
    endtask

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= ST_IDLE;

            manifest_word_offset_q  <= 32'd0;
            manifest_word_count_q   <= 32'd0;
            signature_word_offset_q <= 32'd0;
            signature_word_count_q  <= 32'd0;

            busy_q          <= 1'b0;
            done_q          <= 1'b0;
            error_q         <= 1'b0;
            sig_ok_q        <= 1'b0;
            load_idx_q      <= 7'd0;
            manifest_hash_q <= 512'd0;
            signature_q     <= 2048'd0;

            rsa_start_q <= 1'b0;

            sha_init_q      <= 1'b0;
            sha_start_q     <= 1'b0;
            sha_valid_q     <= 1'b0;
            sha_data_q      <= 32'd0;
            sha_last_q      <= 1'b0;
            sha_byte_num_q  <= 2'd0;

            wr_active_q <= 1'b0;
            wr_addr_q   <= 32'd0;
            wr_len_q    <= 8'd0;
            wr_beat_q   <= 8'd0;
            wr_id_q     <= 4'd0;

            rd_addr_q   <= 32'd0;
            rd_len_q    <= 8'd0;
            rd_beat_q   <= 8'd0;
            rd_id_q     <= 4'd0;

            axi_awready_o <= 1'b1;
            axi_wready_o  <= 1'b0;
            axi_bvalid_o  <= 1'b0;
            axi_bresp_o   <= 2'b00;
            axi_bid_o     <= 4'd0;

            axi_arready_o <= 1'b1;
            axi_rvalid_o  <= 1'b0;
            axi_rdata_o   <= 32'd0;
            axi_rresp_o   <= 2'b00;
            axi_rid_o     <= 4'd0;
            axi_rlast_o   <= 1'b0;
        end else begin
            rsa_start_q <= 1'b0;

            sha_init_q      <= 1'b0;
            sha_start_q     <= 1'b0;
            sha_valid_q     <= 1'b0;
            sha_data_q      <= 32'd0;
            sha_last_q      <= 1'b0;
            sha_byte_num_q  <= 2'd0;

            case (state_q)
                ST_IDLE: begin
                end

                ST_SHA_INIT: begin
                    if ((manifest_word_count_q == 32'd0) ||
                        (manifest_word_count_q > 32'd64) ||
                        (signature_word_count_q != 32'd64)) begin
                        busy_q   <= 1'b0;
                        done_q   <= 1'b1;
                        error_q  <= 1'b1;
                        sig_ok_q <= 1'b0;
                        state_q  <= ST_DONE;
                    end else begin
                        sha_init_q <= 1'b1;
                        load_idx_q <= 7'd0;
                        state_q    <= ST_SHA_START;
                    end
                end

                ST_SHA_START: begin
                    sha_start_q <= 1'b1;
                    load_idx_q  <= 7'd0;
                    state_q     <= ST_SHA_FEED;
                end

                ST_SHA_FEED: begin
                    sha_valid_q <= 1'b1;

                    if (load_idx_q < manifest_word_count_q[6:0]) begin
                        // Feed full manifest words FW[0..FW[manifest_word_count-1]]
                        // Important: do NOT mark this full word as last with byte_num=0.
                        // In this SHA wrapper, last=1 and byte_num=0 means 0 valid bytes in this word.
                        sha_data_q      <= rom[manifest_word_offset_q + load_idx_q];
                        sha_last_q      <= 1'b0;
                        sha_byte_num_q  <= 2'd0;
                        load_idx_q      <= load_idx_q + 7'd1;
                    end else begin
                        // Dummy empty final word:
                        // This terminates the message exactly after the previous full word.
                        sha_data_q      <= 32'd0;
                        sha_last_q      <= 1'b1;
                        sha_byte_num_q  <= 2'd0;
                        load_idx_q      <= 7'd0;
                        state_q         <= ST_SHA_WAIT;
                    end
                end

                ST_SHA_WAIT: begin
                    if (sha_done_w) begin
                        manifest_hash_q <= sha_digest_w;
                        load_idx_q      <= 7'd0;
                        state_q         <= ST_LOAD_SIG;
                    end
                end

                ST_LOAD_SIG: begin
                    signature_q <= {
                        signature_q[2015:0],
                        rom[signature_word_offset_q + load_idx_q]
                    };

                    if (load_idx_q == 7'd63) begin
                        load_idx_q <= 7'd0;
                        state_q    <= ST_RSA_START;
                    end else begin
                        load_idx_q <= load_idx_q + 7'd1;
                    end
                end

                ST_RSA_START: begin
                    rsa_start_q <= 1'b1;
                    state_q     <= ST_RSA_WAIT;
                end

                ST_RSA_WAIT: begin
                    if (rsa_done_w) begin
                        state_q <= ST_CHECK;
                    end
                end

                ST_CHECK: begin
                    busy_q <= 1'b0;
                    done_q <= 1'b1;

                    if (rsa_message_w == pkcs1_expected_em_w) begin
                        sig_ok_q <= 1'b1;
                        error_q  <= 1'b0;
                    end else begin
                        sig_ok_q <= 1'b0;
                        error_q  <= 1'b1;
                    end

                    state_q <= ST_DONE;
                end

                ST_DONE: begin
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase

            // ---------------- AXI WRITE ADDRESS ----------------
            if (axi_awready_o && axi_awvalid_i) begin
                wr_active_q   <= 1'b1;
                wr_addr_q     <= axi_awaddr_i;
                wr_len_q      <= axi_awlen_i;
                wr_beat_q     <= 8'd0;
                wr_id_q       <= axi_awid_i;

                axi_awready_o <= 1'b0;
                axi_wready_o  <= 1'b1;
            end

            // ---------------- AXI WRITE DATA ----------------
            if (wr_active_q && axi_wready_o && axi_wvalid_i) begin
                if (axi_wstrb_i != 4'b0000)
                    write_reg(wr_addr_q[7:0], axi_wdata_i);

                if (axi_wlast_i || (wr_beat_q == wr_len_q)) begin
                    wr_active_q  <= 1'b0;
                    axi_wready_o <= 1'b0;
                    axi_bvalid_o <= 1'b1;
                    axi_bresp_o  <= 2'b00;
                    axi_bid_o    <= wr_id_q;
                end else begin
                    wr_addr_q <= wr_addr_q + 32'd4;
                    wr_beat_q <= wr_beat_q + 8'd1;
                end
            end

            if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o  <= 1'b0;
                axi_awready_o <= 1'b1;
            end

            // ---------------- AXI READ ADDRESS ----------------
            if (axi_arready_o && axi_arvalid_i) begin
                rd_addr_q     <= axi_araddr_i;
                rd_len_q      <= axi_arlen_i;
                rd_beat_q     <= 8'd0;
                rd_id_q       <= axi_arid_i;

                axi_arready_o <= 1'b0;
                axi_rvalid_o  <= 1'b1;
                axi_rdata_o   <= read_reg(axi_araddr_i[7:0]);
                axi_rresp_o   <= 2'b00;
                axi_rid_o     <= axi_arid_i;
                axi_rlast_o   <= (axi_arlen_i == 8'd0);
            end else if (axi_rvalid_o && axi_rready_i) begin
                if (axi_rlast_o) begin
                    axi_rvalid_o  <= 1'b0;
                    axi_rlast_o   <= 1'b0;
                    axi_arready_o <= 1'b1;
                end else begin
                    rd_addr_q    <= rd_next_addr_w;
                    rd_beat_q    <= rd_beat_q + 8'd1;
                    axi_rdata_o  <= read_reg(rd_next_addr_w[7:0]);
                    axi_rlast_o  <= ((rd_beat_q + 8'd1) == rd_len_q);
                end
            end
        end
    end

endmodule
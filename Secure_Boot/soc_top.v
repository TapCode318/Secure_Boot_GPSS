`timescale 1ns/1ps

module soc_top #(
    parameter BOOT_ROM_FILE      = "boot_rom.hex",
    parameter BOOT_ROM_WORDS     = 1024,
    parameter FIRMWARE_ROM_FILE  = "firmware_cipher.hex",
    parameter FIRMWARE_ROM_WORDS = 128,
    parameter BOOT_BASE_ADDR     = 32'h00000000,
    parameter FW_BASE_ADDR       = 32'h10000000,
    parameter SRAM_BASE_ADDR     = 32'h20000000,
    parameter SHA_BASE_ADDR      = 32'h40000000,
    parameter AES_BASE_ADDR      = 32'h50000000,
    parameter AES_ALLOW_KEY_WRITE = 1,
    parameter [255:0] AES_FIXED_KEY = 256'h0000000000000000000000000000000000000000000000000000000000000000
)
(
    input  wire clk_i,
    input  wire rst_i,
    input  wire intr_i
);

    // -----------------------------
    // Instruction AXI bus
    // -----------------------------
    wire        axi_i_awvalid;
    wire [31:0] axi_i_awaddr;
    wire [3:0]  axi_i_awid;
    wire [7:0]  axi_i_awlen;
    wire [1:0]  axi_i_awburst;
    wire        axi_i_wvalid;
    wire [31:0] axi_i_wdata;
    wire [3:0]  axi_i_wstrb;
    wire        axi_i_wlast;
    wire        axi_i_bready;
    wire        axi_i_arvalid;
    wire [31:0] axi_i_araddr;
    wire [3:0]  axi_i_arid;
    wire [7:0]  axi_i_arlen;
    wire [1:0]  axi_i_arburst;
    wire        axi_i_rready;

    wire        axi_i_awready;
    wire        axi_i_wready;
    wire        axi_i_bvalid;
    wire [1:0]  axi_i_bresp;
    wire [3:0]  axi_i_bid;
    wire        axi_i_arready;
    wire        axi_i_rvalid;
    wire [31:0] axi_i_rdata;
    wire [1:0]  axi_i_rresp;
    wire [3:0]  axi_i_rid;
    wire        axi_i_rlast;

    // -----------------------------
    // Data AXI bus
    // -----------------------------
    wire        axi_d_awvalid;
    wire [31:0] axi_d_awaddr;
    wire [3:0]  axi_d_awid;
    wire [7:0]  axi_d_awlen;
    wire [1:0]  axi_d_awburst;
    wire        axi_d_wvalid;
    wire [31:0] axi_d_wdata;
    wire [3:0]  axi_d_wstrb;
    wire        axi_d_wlast;
    wire        axi_d_bready;
    wire        axi_d_arvalid;
    wire [31:0] axi_d_araddr;
    wire [3:0]  axi_d_arid;
    wire [7:0]  axi_d_arlen;
    wire [1:0]  axi_d_arburst;
    wire        axi_d_rready;

    wire        axi_d_awready;
    wire        axi_d_wready;
    wire        axi_d_bvalid;
    wire [1:0]  axi_d_bresp;
    wire [3:0]  axi_d_bid;
    wire        axi_d_arready;
    wire        axi_d_rvalid;
    wire [31:0] axi_d_rdata;
    wire [1:0]  axi_d_rresp;
    wire [3:0]  axi_d_rid;
    wire        axi_d_rlast;

    // -----------------------------
    // SHA sideband signals
    // -----------------------------
    wire         sha_init;
    wire         sha_start;
    wire         sha_data_valid;
    wire [31:0]  sha_data;
    wire         sha_is_last;
    wire [1:0]   sha_byte_num;
    wire         sha_busy;
    wire         sha_done;
    wire [511:0] sha_digest;

    // -----------------------------
    // AES-CTR sideband signals
    // -----------------------------
    wire         aes_key_load;
    wire         aes_ctr_load;
    wire         aes_valid_in;
    wire [255:0] aes_key;
    wire [127:0] aes_ctr_init;
    wire [127:0] aes_data_in;
    wire         aes_last_in;
    wire [15:0]  aes_keep_in;
    wire         aes_ready_in;
    wire         aes_valid_out;
    wire [127:0] aes_data_out;
    wire         aes_last_out;
    wire [15:0]  aes_keep_out;
    wire [127:0] aes_ctr_dbg;
    wire [127:0] aes_keystream_dbg;

    // -----------------------------
    // RISC-V CPU Core
    // -----------------------------
    riscv_top #(
        .CORE_ID(0),
        .MEM_CACHE_ADDR_MIN(32'h1000_0000),
        .MEM_CACHE_ADDR_MAX(32'h1000_FFFF)
    )
    u_riscv_top (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .axi_i_awready_i(axi_i_awready),
        .axi_i_wready_i (axi_i_wready),
        .axi_i_bvalid_i (axi_i_bvalid),
        .axi_i_bresp_i  (axi_i_bresp),
        .axi_i_bid_i    (axi_i_bid),
        .axi_i_arready_i(axi_i_arready),
        .axi_i_rvalid_i (axi_i_rvalid),
        .axi_i_rdata_i  (axi_i_rdata),
        .axi_i_rresp_i  (axi_i_rresp),
        .axi_i_rid_i    (axi_i_rid),
        .axi_i_rlast_i  (axi_i_rlast),

        .axi_d_awready_i(axi_d_awready),
        .axi_d_wready_i (axi_d_wready),
        .axi_d_bvalid_i (axi_d_bvalid),
        .axi_d_bresp_i  (axi_d_bresp),
        .axi_d_bid_i    (axi_d_bid),
        .axi_d_arready_i(axi_d_arready),
        .axi_d_rvalid_i (axi_d_rvalid),
        .axi_d_rdata_i  (axi_d_rdata),
        .axi_d_rresp_i  (axi_d_rresp),
        .axi_d_rid_i    (axi_d_rid),
        .axi_d_rlast_i  (axi_d_rlast),

        .intr_i(intr_i),
        .reset_vector_i(BOOT_BASE_ADDR),

        .axi_i_awvalid_o(axi_i_awvalid),
        .axi_i_awaddr_o (axi_i_awaddr),
        .axi_i_awid_o   (axi_i_awid),
        .axi_i_awlen_o  (axi_i_awlen),
        .axi_i_awburst_o(axi_i_awburst),
        .axi_i_wvalid_o (axi_i_wvalid),
        .axi_i_wdata_o  (axi_i_wdata),
        .axi_i_wstrb_o  (axi_i_wstrb),
        .axi_i_wlast_o  (axi_i_wlast),
        .axi_i_bready_o (axi_i_bready),
        .axi_i_arvalid_o(axi_i_arvalid),
        .axi_i_araddr_o (axi_i_araddr),
        .axi_i_arid_o   (axi_i_arid),
        .axi_i_arlen_o  (axi_i_arlen),
        .axi_i_arburst_o(axi_i_arburst),
        .axi_i_rready_o (axi_i_rready),

        .axi_d_awvalid_o(axi_d_awvalid),
        .axi_d_awaddr_o (axi_d_awaddr),
        .axi_d_awid_o   (axi_d_awid),
        .axi_d_awlen_o  (axi_d_awlen),
        .axi_d_awburst_o(axi_d_awburst),
        .axi_d_wvalid_o (axi_d_wvalid),
        .axi_d_wdata_o  (axi_d_wdata),
        .axi_d_wstrb_o  (axi_d_wstrb),
        .axi_d_wlast_o  (axi_d_wlast),
        .axi_d_bready_o (axi_d_bready),
        .axi_d_arvalid_o(axi_d_arvalid),
        .axi_d_araddr_o (axi_d_araddr),
        .axi_d_arid_o   (axi_d_arid),
        .axi_d_arlen_o  (axi_d_arlen),
        .axi_d_arburst_o(axi_d_arburst),
        .axi_d_rready_o (axi_d_rready)
    );

    // -----------------------------
    // Instruction boot ROM
    // -----------------------------
    axi_simple_rom #(
        .BASE_ADDR(BOOT_BASE_ADDR),
        .MEM_WORDS(BOOT_ROM_WORDS),
        .INIT_FILE(BOOT_ROM_FILE)
    ) u_boot_rom (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .axi_awvalid_i(axi_i_awvalid),
        .axi_awaddr_i (axi_i_awaddr),
        .axi_awid_i   (axi_i_awid),
        .axi_awlen_i  (axi_i_awlen),
        .axi_awburst_i(axi_i_awburst),
        .axi_wvalid_i (axi_i_wvalid),
        .axi_wdata_i  (axi_i_wdata),
        .axi_wstrb_i  (axi_i_wstrb),
        .axi_wlast_i  (axi_i_wlast),
        .axi_bready_i (axi_i_bready),
        .axi_arvalid_i(axi_i_arvalid),
        .axi_araddr_i (axi_i_araddr),
        .axi_arid_i   (axi_i_arid),
        .axi_arlen_i  (axi_i_arlen),
        .axi_arburst_i(axi_i_arburst),
        .axi_rready_i (axi_i_rready),
        .axi_awready_o(axi_i_awready),
        .axi_wready_o (axi_i_wready),
        .axi_bvalid_o (axi_i_bvalid),
        .axi_bresp_o  (axi_i_bresp),
        .axi_bid_o    (axi_i_bid),
        .axi_arready_o(axi_i_arready),
        .axi_rvalid_o (axi_i_rvalid),
        .axi_rdata_o  (axi_i_rdata),
        .axi_rresp_o  (axi_i_rresp),
        .axi_rid_o    (axi_i_rid),
        .axi_rlast_o  (axi_i_rlast)
    );

    // -----------------------------
    // Data path: Decoder
    // -----------------------------
    axi_d_simple_decoder_secureboot #(
        .ROM_BASE_ADDR(FW_BASE_ADDR),
        .ROM_HIGH_ADDR(FW_BASE_ADDR + (FIRMWARE_ROM_WORDS * 4) - 1),
        .ROM_INIT_FILE(FIRMWARE_ROM_FILE),
        .SRAM_BASE_ADDR(SRAM_BASE_ADDR),
        .SRAM_HIGH_ADDR(SRAM_BASE_ADDR + 32'h00000FFF),
        .SHA_BASE_ADDR(SHA_BASE_ADDR),
        .SHA_HIGH_ADDR(SHA_BASE_ADDR + 32'h000000FF),
        .AES_BASE_ADDR(AES_BASE_ADDR),
        .AES_HIGH_ADDR(AES_BASE_ADDR + 32'h000000FF),
        .AES_ALLOW_KEY_WRITE(AES_ALLOW_KEY_WRITE),
        .AES_FIXED_KEY(AES_FIXED_KEY)
    ) u_axi_d_simple_decoder_secureboot (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .m_awvalid_i(axi_d_awvalid),
        .m_awaddr_i (axi_d_awaddr),
        .m_awid_i   (axi_d_awid),
        .m_awlen_i  (axi_d_awlen),
        .m_awburst_i(axi_d_awburst),
        .m_wvalid_i (axi_d_wvalid),
        .m_wdata_i  (axi_d_wdata),
        .m_wstrb_i  (axi_d_wstrb),
        .m_wlast_i  (axi_d_wlast),
        .m_bready_i (axi_d_bready),
        .m_arvalid_i(axi_d_arvalid),
        .m_araddr_i (axi_d_araddr),
        .m_arid_i   (axi_d_arid),
        .m_arlen_i  (axi_d_arlen),
        .m_arburst_i(axi_d_arburst),
        .m_rready_i (axi_d_rready),
        .m_awready_o(axi_d_awready),
        .m_wready_o (axi_d_wready),
        .m_bvalid_o (axi_d_bvalid),
        .m_bresp_o  (axi_d_bresp),
        .m_bid_o    (axi_d_bid),
        .m_arready_o(axi_d_arready),
        .m_rvalid_o (axi_d_rvalid),
        .m_rdata_o  (axi_d_rdata),
        .m_rresp_o  (axi_d_rresp),
        .m_rid_o    (axi_d_rid),
        .m_rlast_o  (axi_d_rlast),

        .sha_init_o      (sha_init),
        .sha_start_o     (sha_start),
        .sha_data_valid_o(sha_data_valid),
        .sha_data_o      (sha_data),
        .sha_is_last_o   (sha_is_last),
        .sha_byte_num_o  (sha_byte_num),
        .sha_busy_i      (sha_busy),
        .sha_done_i      (sha_done),
        .sha_digest_i    (sha_digest),

        .aes_key_load_o  (aes_key_load),
        .aes_ctr_load_o  (aes_ctr_load),
        .aes_valid_in_o  (aes_valid_in),
        .aes_key_o       (aes_key),
        .aes_ctr_init_o  (aes_ctr_init),
        .aes_data_in_o   (aes_data_in),
        .aes_last_in_o   (aes_last_in),
        .aes_keep_in_o   (aes_keep_in),
        .aes_ready_in_i  (aes_ready_in),
        .aes_valid_out_i (aes_valid_out),
        .aes_data_out_i  (aes_data_out),
        .aes_last_out_i  (aes_last_out),
        .aes_keep_out_i  (aes_keep_out)
    );

    // -----------------------------
    // SHA3 Accelerator Core
    // -----------------------------
    sha3_real_wrapper #(
        .FIFO_DEPTH(8)
    ) u_sha3_real_wrapper (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .init_i          (sha_init),
        .start_i         (sha_start),
        .data_valid_i    (sha_data_valid),
        .data_i          (sha_data),
        .data_is_last_i  (sha_is_last),
        .data_byte_num_i (sha_byte_num),
        .busy_o          (sha_busy),
        .done_o          (sha_done),
        .digest_o        (sha_digest)
    );

    // -----------------------------
    // AES-256 CTR core
    // -----------------------------
    aes256_ctr_stream u_aes256_ctr (
        .clk          (clk_i),
        .rst          (rst_i),
        .key_load     (aes_key_load),
        .key_in       (aes_key),
        .ctr_load     (aes_ctr_load),
        .ctr_init     (aes_ctr_init),
        .valid_in     (aes_valid_in),
        .data_in      (aes_data_in),
        .last_in      (aes_last_in),
        .keep_in      (aes_keep_in),
        .ready_in     (aes_ready_in),
        .valid_out    (aes_valid_out),
        .data_out     (aes_data_out),
        .last_out     (aes_last_out),
        .keep_out     (aes_keep_out),
        .ctr_dbg      (aes_ctr_dbg),
        .keystream_dbg(aes_keystream_dbg)
    );

endmodule
module axi_d_simple_decoder_secureboot #(
    parameter ROM_BASE_ADDR       = 32'h10000000,
    parameter ROM_HIGH_ADDR       = 32'h1000FFFF,
    parameter ROM_INIT_FILE       = "firmware_rom.hex",

    parameter SRAM_BASE_ADDR      = 32'h20000000,
    parameter SRAM_HIGH_ADDR      = 32'h2000FFFF,

    parameter SHA_BASE_ADDR       = 32'h40000000,
    parameter SHA_HIGH_ADDR       = 32'h400000FF,

    parameter AES_BASE_ADDR       = 32'h50000000,
    parameter AES_HIGH_ADDR       = 32'h500000FF,

    parameter SEC_BASE_ADDR       = 32'h60000000,
    parameter SEC_HIGH_ADDR       = 32'h600000FF,

    parameter SIG_BASE_ADDR       = 32'h70000000,
    parameter SIG_HIGH_ADDR       = 32'h700000FF,

    parameter AES_ALLOW_KEY_WRITE = 1,
    parameter [255:0] AES_FIXED_KEY =
        256'h0000000000000000000000000000000000000000000000000000000000000000
)
(
    input  wire         clk_i,
    input  wire         rst_i,

    input  wire         m_awvalid_i,
    input  wire [31:0]  m_awaddr_i,
    input  wire [3:0]   m_awid_i,
    input  wire [7:0]   m_awlen_i,
    input  wire [1:0]   m_awburst_i,
    input  wire         m_wvalid_i,
    input  wire [31:0]  m_wdata_i,
    input  wire [3:0]   m_wstrb_i,
    input  wire         m_wlast_i,
    input  wire         m_bready_i,

    input  wire         m_arvalid_i,
    input  wire [31:0]  m_araddr_i,
    input  wire [3:0]   m_arid_i,
    input  wire [7:0]   m_arlen_i,
    input  wire [1:0]   m_arburst_i,
    input  wire         m_rready_i,

    output wire         m_awready_o,
    output wire         m_wready_o,
    output wire         m_bvalid_o,
    output wire [1:0]   m_bresp_o,
    output wire [3:0]   m_bid_o,
    output wire         m_arready_o,
    output wire         m_rvalid_o,
    output wire [31:0]  m_rdata_o,
    output wire [1:0]   m_rresp_o,
    output wire [3:0]   m_rid_o,
    output wire         m_rlast_o,

    output wire         sha_init_o,
    output wire         sha_start_o,
    output wire         sha_data_valid_o,
    output wire [31:0]  sha_data_o,
    output wire         sha_is_last_o,
    output wire [1:0]   sha_byte_num_o,
    input  wire         sha_busy_i,
    input  wire         sha_done_i,
    input  wire [511:0] sha_digest_i,

    output wire         aes_key_load_o,
    output wire         aes_ctr_load_o,
    output wire         aes_valid_in_o,
    output wire [255:0] aes_key_o,
    output wire [127:0] aes_ctr_init_o,
    output wire [127:0] aes_data_in_o,
    output wire         aes_last_in_o,
    output wire [15:0]  aes_keep_in_o,
    input  wire         aes_ready_in_i,
    input  wire         aes_valid_out_i,
    input  wire [127:0] aes_data_out_i,
    input  wire         aes_last_out_i,
    input  wire [15:0]  aes_keep_out_i
);

    wire aw_to_rom_w = (m_awaddr_i >= ROM_BASE_ADDR)  && (m_awaddr_i <= ROM_HIGH_ADDR);
    wire aw_to_ram_w = (m_awaddr_i >= SRAM_BASE_ADDR) && (m_awaddr_i <= SRAM_HIGH_ADDR);
    wire aw_to_sha_w = (m_awaddr_i >= SHA_BASE_ADDR)  && (m_awaddr_i <= SHA_HIGH_ADDR);
    wire aw_to_aes_w = (m_awaddr_i >= AES_BASE_ADDR)  && (m_awaddr_i <= AES_HIGH_ADDR);
    wire aw_to_sec_w = (m_awaddr_i >= SEC_BASE_ADDR)  && (m_awaddr_i <= SEC_HIGH_ADDR);
    wire aw_to_sig_w = (m_awaddr_i >= SIG_BASE_ADDR)  && (m_awaddr_i <= SIG_HIGH_ADDR);

    wire ar_to_rom_w = (m_araddr_i >= ROM_BASE_ADDR)  && (m_araddr_i <= ROM_HIGH_ADDR);
    wire ar_to_ram_w = (m_araddr_i >= SRAM_BASE_ADDR) && (m_araddr_i <= SRAM_HIGH_ADDR);
    wire ar_to_sha_w = (m_araddr_i >= SHA_BASE_ADDR)  && (m_araddr_i <= SHA_HIGH_ADDR);
    wire ar_to_aes_w = (m_araddr_i >= AES_BASE_ADDR)  && (m_araddr_i <= AES_HIGH_ADDR);
    wire ar_to_sec_w = (m_araddr_i >= SEC_BASE_ADDR)  && (m_araddr_i <= SEC_HIGH_ADDR);
    wire ar_to_sig_w = (m_araddr_i >= SIG_BASE_ADDR)  && (m_araddr_i <= SIG_HIGH_ADDR);

    reg wr_sel_rom_q, wr_sel_ram_q, wr_sel_sha_q, wr_sel_aes_q, wr_sel_sec_q, wr_sel_sig_q, wr_sel_err_q;
    reg rd_sel_rom_q, rd_sel_ram_q, rd_sel_sha_q, rd_sel_aes_q, rd_sel_sec_q, rd_sel_sig_q, rd_sel_err_q;

    wire wr_idle_w = !wr_sel_rom_q && !wr_sel_ram_q && !wr_sel_sha_q &&
                     !wr_sel_aes_q && !wr_sel_sec_q && !wr_sel_sig_q && !wr_sel_err_q;

    wire rd_idle_w = !rd_sel_rom_q && !rd_sel_ram_q && !rd_sel_sha_q &&
                     !rd_sel_aes_q && !rd_sel_sec_q && !rd_sel_sig_q && !rd_sel_err_q;

    wire wr_to_rom_now_w = wr_sel_rom_q || (wr_idle_w && aw_to_rom_w);
    wire wr_to_ram_now_w = wr_sel_ram_q || (wr_idle_w && aw_to_ram_w);
    wire wr_to_sha_now_w = wr_sel_sha_q || (wr_idle_w && aw_to_sha_w);
    wire wr_to_aes_now_w = wr_sel_aes_q || (wr_idle_w && aw_to_aes_w);
    wire wr_to_sec_now_w = wr_sel_sec_q || (wr_idle_w && aw_to_sec_w);
    wire wr_to_sig_now_w = wr_sel_sig_q || (wr_idle_w && aw_to_sig_w);

    wire        rom_awready_w, rom_wready_w, rom_bvalid_w;
    wire [1:0]  rom_bresp_w;
    wire [3:0]  rom_bid_w;
    wire        rom_arready_w, rom_rvalid_w, rom_rlast_w;
    wire [31:0] rom_rdata_w;
    wire [1:0]  rom_rresp_w;
    wire [3:0]  rom_rid_w;

    wire        ram_awready_w, ram_wready_w, ram_bvalid_w;
    wire [1:0]  ram_bresp_w;
    wire        ram_arready_w, ram_rvalid_w, ram_rlast_w;
    wire [31:0] ram_rdata_w;
    wire [1:0]  ram_rresp_w;
    wire [3:0]  ram_bid_w = 4'd0;
    wire [3:0]  ram_rid_w = 4'd0;

    wire        sha_awready_w, sha_wready_w, sha_bvalid_w;
    wire [1:0]  sha_bresp_w;
    wire [3:0]  sha_bid_w;
    wire        sha_arready_w, sha_rvalid_w, sha_rlast_w;
    wire [31:0] sha_rdata_w;
    wire [1:0]  sha_rresp_w;
    wire [3:0]  sha_rid_w;

    wire        aes_awready_w, aes_wready_w, aes_bvalid_w;
    wire [1:0]  aes_bresp_w;
    wire [3:0]  aes_bid_w;
    wire        aes_arready_w, aes_rvalid_w, aes_rlast_w;
    wire [31:0] aes_rdata_w;
    wire [1:0]  aes_rresp_w;
    wire [3:0]  aes_rid_w;

    wire        sec_awready_w, sec_wready_w, sec_bvalid_w;
    wire [1:0]  sec_bresp_w;
    wire [3:0]  sec_bid_w;
    wire        sec_arready_w, sec_rvalid_w, sec_rlast_w;
    wire [31:0] sec_rdata_w;
    wire [1:0]  sec_rresp_w;
    wire [3:0]  sec_rid_w;

    wire        sig_awready_w, sig_wready_w, sig_bvalid_w;
    wire [1:0]  sig_bresp_w;
    wire [3:0]  sig_bid_w;
    wire        sig_arready_w, sig_rvalid_w, sig_rlast_w;
    wire [31:0] sig_rdata_w;
    wire [1:0]  sig_rresp_w;
    wire [3:0]  sig_rid_w;

    reg         err_bvalid_q;
    reg [3:0]   err_bid_q;
    reg         err_rvalid_q;
    reg [3:0]   err_rid_q;

    axi_simple_rom #(
        .BASE_ADDR(ROM_BASE_ADDR),
        .MEM_WORDS(((ROM_HIGH_ADDR - ROM_BASE_ADDR) >> 2) + 1),
        .INIT_FILE(ROM_INIT_FILE)
    ) u_firmware_rom (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .axi_awvalid_i(m_awvalid_i && wr_idle_w && aw_to_rom_w),
        .axi_awaddr_i (m_awaddr_i),
        .axi_awid_i   (m_awid_i),
        .axi_awlen_i  (m_awlen_i),
        .axi_awburst_i(m_awburst_i),
        .axi_wvalid_i (m_wvalid_i && wr_to_rom_now_w),
        .axi_wdata_i  (m_wdata_i),
        .axi_wstrb_i  (m_wstrb_i),
        .axi_wlast_i  (m_wlast_i),
        .axi_bready_i (m_bready_i),
        .axi_arvalid_i(m_arvalid_i && rd_idle_w && ar_to_rom_w),
        .axi_araddr_i (m_araddr_i),
        .axi_arid_i   (m_arid_i),
        .axi_arlen_i  (m_arlen_i),
        .axi_arburst_i(m_arburst_i),
        .axi_rready_i (m_rready_i),

        .axi_awready_o(rom_awready_w),
        .axi_wready_o (rom_wready_w),
        .axi_bvalid_o (rom_bvalid_w),
        .axi_bresp_o  (rom_bresp_w),
        .axi_bid_o    (rom_bid_w),
        .axi_arready_o(rom_arready_w),
        .axi_rvalid_o (rom_rvalid_w),
        .axi_rdata_o  (rom_rdata_w),
        .axi_rresp_o  (rom_rresp_w),
        .axi_rid_o    (rom_rid_w),
        .axi_rlast_o  (rom_rlast_w)
    );

    axi_simple_ram #(
        .BASE_ADDR(SRAM_BASE_ADDR),
        .MEM_WORDS(((SRAM_HIGH_ADDR - SRAM_BASE_ADDR) >> 2) + 1)
    ) u_sram (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .axi_awvalid_i(m_awvalid_i && wr_idle_w && aw_to_ram_w),
        .axi_awaddr_i (m_awaddr_i),
        .axi_wvalid_i (m_wvalid_i && wr_to_ram_now_w),
        .axi_wdata_i  (m_wdata_i),
        .axi_wstrb_i  (m_wstrb_i),
        .axi_bready_i (m_bready_i),

        .axi_arvalid_i(m_arvalid_i && rd_idle_w && ar_to_ram_w),
        .axi_araddr_i (m_araddr_i),
        .axi_rready_i (m_rready_i),

        .axi_awready_o(ram_awready_w),
        .axi_wready_o (ram_wready_w),
        .axi_bvalid_o (ram_bvalid_w),
        .axi_bresp_o  (ram_bresp_w),
        .axi_arready_o(ram_arready_w),
        .axi_rvalid_o (ram_rvalid_w),
        .axi_rdata_o  (ram_rdata_w),
        .axi_rresp_o  (ram_rresp_w),
        .axi_rlast_o  (ram_rlast_w)
    );

    axi_sha3_regs #(
        .BASE_ADDR(SHA_BASE_ADDR)
    ) u_axi_sha3_regs (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .axi_awvalid_i(m_awvalid_i && wr_idle_w && aw_to_sha_w),
        .axi_awaddr_i (m_awaddr_i),
        .axi_awid_i   (m_awid_i),
        .axi_awlen_i  (m_awlen_i),
        .axi_awburst_i(m_awburst_i),
        .axi_wvalid_i (m_wvalid_i && wr_to_sha_now_w),
        .axi_wdata_i  (m_wdata_i),
        .axi_wstrb_i  (m_wstrb_i),
        .axi_wlast_i  (m_wlast_i),
        .axi_bready_i (m_bready_i),
        .axi_arvalid_i(m_arvalid_i && rd_idle_w && ar_to_sha_w),
        .axi_araddr_i (m_araddr_i),
        .axi_arid_i   (m_arid_i),
        .axi_arlen_i  (m_arlen_i),
        .axi_arburst_i(m_arburst_i),
        .axi_rready_i (m_rready_i),

        .axi_awready_o(sha_awready_w),
        .axi_wready_o (sha_wready_w),
        .axi_bvalid_o (sha_bvalid_w),
        .axi_bresp_o  (sha_bresp_w),
        .axi_bid_o    (sha_bid_w),
        .axi_arready_o(sha_arready_w),
        .axi_rvalid_o (sha_rvalid_w),
        .axi_rdata_o  (sha_rdata_w),
        .axi_rresp_o  (sha_rresp_w),
        .axi_rid_o    (sha_rid_w),
        .axi_rlast_o  (sha_rlast_w),

        .sha_init_o      (sha_init_o),
        .sha_start_o     (sha_start_o),
        .sha_data_valid_o(sha_data_valid_o),
        .sha_data_o      (sha_data_o),
        .sha_is_last_o   (sha_is_last_o),
        .sha_byte_num_o  (sha_byte_num_o),
        .sha_busy_i      (sha_busy_i),
        .sha_done_i      (sha_done_i),
        .sha_digest_i    (sha_digest_i)
    );

    axi_aes256_ctr_regs #(
        .BASE_ADDR      (AES_BASE_ADDR),
        .ALLOW_KEY_WRITE(AES_ALLOW_KEY_WRITE),
        .FIXED_KEY      (AES_FIXED_KEY)
    ) u_axi_aes256_ctr_regs (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .axi_awvalid_i(m_awvalid_i && wr_idle_w && aw_to_aes_w),
        .axi_awaddr_i (m_awaddr_i),
        .axi_awid_i   (m_awid_i),
        .axi_awlen_i  (m_awlen_i),
        .axi_awburst_i(m_awburst_i),
        .axi_wvalid_i (m_wvalid_i && wr_to_aes_now_w),
        .axi_wdata_i  (m_wdata_i),
        .axi_wstrb_i  (m_wstrb_i),
        .axi_wlast_i  (m_wlast_i),
        .axi_bready_i (m_bready_i),
        .axi_arvalid_i(m_arvalid_i && rd_idle_w && ar_to_aes_w),
        .axi_araddr_i (m_araddr_i),
        .axi_arid_i   (m_arid_i),
        .axi_arlen_i  (m_arlen_i),
        .axi_arburst_i(m_arburst_i),
        .axi_rready_i (m_rready_i),

        .axi_awready_o(aes_awready_w),
        .axi_wready_o (aes_wready_w),
        .axi_bvalid_o (aes_bvalid_w),
        .axi_bresp_o  (aes_bresp_w),
        .axi_bid_o    (aes_bid_w),
        .axi_arready_o(aes_arready_w),
        .axi_rvalid_o (aes_rvalid_w),
        .axi_rdata_o  (aes_rdata_w),
        .axi_rresp_o  (aes_rresp_w),
        .axi_rid_o    (aes_rid_w),
        .axi_rlast_o  (aes_rlast_w),

        .aes_key_load_o (aes_key_load_o),
        .aes_ctr_load_o (aes_ctr_load_o),
        .aes_valid_in_o (aes_valid_in_o),
        .aes_key_o      (aes_key_o),
        .aes_ctr_init_o (aes_ctr_init_o),
        .aes_data_in_o  (aes_data_in_o),
        .aes_last_in_o  (aes_last_in_o),
        .aes_keep_in_o  (aes_keep_in_o),
        .aes_ready_in_i (aes_ready_in_i),
        .aes_valid_out_i(aes_valid_out_i),
        .aes_data_out_i (aes_data_out_i),
        .aes_last_out_i (aes_last_out_i),
        .aes_keep_out_i (aes_keep_out_i)
    );

    axi4_secureboot_crypto_engine #(
        .BASE_ADDR       (SEC_BASE_ADDR),
        .ROM_INIT_FILE   (ROM_INIT_FILE),
        .ROM_WORDS       (((ROM_HIGH_ADDR - ROM_BASE_ADDR) >> 2) + 1),
        .FIFO_DEPTH      (8),
        .ALLOW_KEY_WRITE (AES_ALLOW_KEY_WRITE),
        .FIXED_KEY       (AES_FIXED_KEY)
    ) u_axi4_secureboot_crypto_engine (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .axi_awvalid_i(m_awvalid_i && wr_idle_w && aw_to_sec_w),
        .axi_awaddr_i (m_awaddr_i),
        .axi_awid_i   (m_awid_i),
        .axi_awlen_i  (m_awlen_i),
        .axi_awburst_i(m_awburst_i),

        .axi_wvalid_i (m_wvalid_i && wr_to_sec_now_w),
        .axi_wdata_i  (m_wdata_i),
        .axi_wstrb_i  (m_wstrb_i),
        .axi_wlast_i  (m_wlast_i),

        .axi_bready_i (m_bready_i),
        .axi_awready_o(sec_awready_w),
        .axi_wready_o (sec_wready_w),
        .axi_bvalid_o (sec_bvalid_w),
        .axi_bresp_o  (sec_bresp_w),
        .axi_bid_o    (sec_bid_w),

        .axi_arvalid_i(m_arvalid_i && rd_idle_w && ar_to_sec_w),
        .axi_araddr_i (m_araddr_i),
        .axi_arid_i   (m_arid_i),
        .axi_arlen_i  (m_arlen_i),
        .axi_arburst_i(m_arburst_i),
        .axi_rready_i (m_rready_i),

        .axi_arready_o(sec_arready_w),
        .axi_rvalid_o (sec_rvalid_w),
        .axi_rdata_o  (sec_rdata_w),
        .axi_rresp_o  (sec_rresp_w),
        .axi_rid_o    (sec_rid_w),
        .axi_rlast_o  (sec_rlast_w)
    );

axi_signature_verify_stub #(
    .BASE_ADDR     (SIG_BASE_ADDR),
    .ROM_INIT_FILE (ROM_INIT_FILE),
    .ROM_WORDS     (((ROM_HIGH_ADDR - ROM_BASE_ADDR) >> 2) + 1)
) u_axi_signature_verify_stub (
    .clk_i(clk_i),
    .rst_i(rst_i),

    .axi_awvalid_i(m_awvalid_i && wr_idle_w && aw_to_sig_w),
    .axi_awaddr_i (m_awaddr_i),
    .axi_awid_i   (m_awid_i),
    .axi_awlen_i  (m_awlen_i),
    .axi_awburst_i(m_awburst_i),

    .axi_wvalid_i (m_wvalid_i && wr_to_sig_now_w),
    .axi_wdata_i  (m_wdata_i),
    .axi_wstrb_i  (m_wstrb_i),
    .axi_wlast_i  (m_wlast_i),

    .axi_bready_i (m_bready_i),
    .axi_awready_o(sig_awready_w),
    .axi_wready_o (sig_wready_w),
    .axi_bvalid_o (sig_bvalid_w),
    .axi_bresp_o  (sig_bresp_w),
    .axi_bid_o    (sig_bid_w),

    .axi_arvalid_i(m_arvalid_i && rd_idle_w && ar_to_sig_w),
    .axi_araddr_i (m_araddr_i),
    .axi_arid_i   (m_arid_i),
    .axi_arlen_i  (m_arlen_i),
    .axi_arburst_i(m_arburst_i),
    .axi_rready_i (m_rready_i),

    .axi_arready_o(sig_arready_w),
    .axi_rvalid_o (sig_rvalid_w),
    .axi_rdata_o  (sig_rdata_w),
    .axi_rresp_o  (sig_rresp_w),
    .axi_rid_o    (sig_rid_w),
    .axi_rlast_o  (sig_rlast_w)
);
    always @(posedge clk_i) begin
        if (rst_i) begin
            wr_sel_rom_q <= 1'b0;
            wr_sel_ram_q <= 1'b0;
            wr_sel_sha_q <= 1'b0;
            wr_sel_aes_q <= 1'b0;
            wr_sel_sec_q <= 1'b0;
            wr_sel_sig_q <= 1'b0;
            wr_sel_err_q <= 1'b0;

            rd_sel_rom_q <= 1'b0;
            rd_sel_ram_q <= 1'b0;
            rd_sel_sha_q <= 1'b0;
            rd_sel_aes_q <= 1'b0;
            rd_sel_sec_q <= 1'b0;
            rd_sel_sig_q <= 1'b0;
            rd_sel_err_q <= 1'b0;

            err_bvalid_q <= 1'b0;
            err_bid_q    <= 4'd0;
            err_rvalid_q <= 1'b0;
            err_rid_q    <= 4'd0;
        end else begin
            if (wr_idle_w && m_awvalid_i) begin
                if (aw_to_rom_w)       wr_sel_rom_q <= 1'b1;
                else if (aw_to_ram_w)  wr_sel_ram_q <= 1'b1;
                else if (aw_to_sha_w)  wr_sel_sha_q <= 1'b1;
                else if (aw_to_aes_w)  wr_sel_aes_q <= 1'b1;
                else if (aw_to_sec_w)  wr_sel_sec_q <= 1'b1;
                else if (aw_to_sig_w)  wr_sel_sig_q <= 1'b1;
                else                   wr_sel_err_q <= 1'b1;
            end

            if (wr_sel_err_q && !err_bvalid_q && m_awvalid_i && m_wvalid_i) begin
                err_bvalid_q <= 1'b1;
                err_bid_q    <= m_awid_i;
            end else if (err_bvalid_q && m_bready_i) begin
                err_bvalid_q <= 1'b0;
                wr_sel_err_q <= 1'b0;
            end

            if ((wr_sel_rom_q && rom_bvalid_w && m_bready_i) ||
                (wr_sel_ram_q && ram_bvalid_w && m_bready_i) ||
                (wr_sel_sha_q && sha_bvalid_w && m_bready_i) ||
                (wr_sel_aes_q && aes_bvalid_w && m_bready_i) ||
                (wr_sel_sec_q && sec_bvalid_w && m_bready_i) ||
                (wr_sel_sig_q && sig_bvalid_w && m_bready_i)) begin
                wr_sel_rom_q <= 1'b0;
                wr_sel_ram_q <= 1'b0;
                wr_sel_sha_q <= 1'b0;
                wr_sel_aes_q <= 1'b0;
                wr_sel_sec_q <= 1'b0;
                wr_sel_sig_q <= 1'b0;
            end

            if (rd_idle_w && m_arvalid_i) begin
                if (ar_to_rom_w)       rd_sel_rom_q <= 1'b1;
                else if (ar_to_ram_w)  rd_sel_ram_q <= 1'b1;
                else if (ar_to_sha_w)  rd_sel_sha_q <= 1'b1;
                else if (ar_to_aes_w)  rd_sel_aes_q <= 1'b1;
                else if (ar_to_sec_w)  rd_sel_sec_q <= 1'b1;
                else if (ar_to_sig_w)  rd_sel_sig_q <= 1'b1;
                else                   rd_sel_err_q <= 1'b1;
            end

            if (rd_sel_err_q && !err_rvalid_q && m_arvalid_i) begin
                err_rvalid_q <= 1'b1;
                err_rid_q    <= m_arid_i;
            end else if (err_rvalid_q && m_rready_i) begin
                err_rvalid_q <= 1'b0;
                rd_sel_err_q <= 1'b0;
            end

            if ((rd_sel_rom_q && rom_rvalid_w && m_rready_i && rom_rlast_w) ||
                (rd_sel_ram_q && ram_rvalid_w && m_rready_i && ram_rlast_w) ||
                (rd_sel_sha_q && sha_rvalid_w && m_rready_i && sha_rlast_w) ||
                (rd_sel_aes_q && aes_rvalid_w && m_rready_i && aes_rlast_w) ||
                (rd_sel_sec_q && sec_rvalid_w && m_rready_i && sec_rlast_w) ||
                (rd_sel_sig_q && sig_rvalid_w && m_rready_i && sig_rlast_w)) begin
                rd_sel_rom_q <= 1'b0;
                rd_sel_ram_q <= 1'b0;
                rd_sel_sha_q <= 1'b0;
                rd_sel_aes_q <= 1'b0;
                rd_sel_sec_q <= 1'b0;
                rd_sel_sig_q <= 1'b0;
            end
        end
    end

    assign m_awready_o = aw_to_rom_w ? rom_awready_w :
                         aw_to_ram_w ? ram_awready_w :
                         aw_to_sha_w ? sha_awready_w :
                         aw_to_aes_w ? aes_awready_w :
                         aw_to_sec_w ? sec_awready_w :
                         aw_to_sig_w ? sig_awready_w :
                         wr_sel_err_q ? 1'b1 : 1'b0;

    assign m_wready_o  = wr_to_rom_now_w ? rom_wready_w :
                         wr_to_ram_now_w ? ram_wready_w :
                         wr_to_sha_now_w ? sha_wready_w :
                         wr_to_aes_now_w ? aes_wready_w :
                         wr_to_sec_now_w ? sec_wready_w :
                         wr_to_sig_now_w ? sig_wready_w :
                         wr_sel_err_q ? 1'b1 : 1'b0;

    assign m_bvalid_o  = wr_sel_rom_q ? rom_bvalid_w :
                         wr_sel_ram_q ? ram_bvalid_w :
                         wr_sel_sha_q ? sha_bvalid_w :
                         wr_sel_aes_q ? aes_bvalid_w :
                         wr_sel_sec_q ? sec_bvalid_w :
                         wr_sel_sig_q ? sig_bvalid_w :
                         wr_sel_err_q ? err_bvalid_q : 1'b0;

    assign m_bresp_o   = wr_sel_rom_q ? rom_bresp_w :
                         wr_sel_ram_q ? ram_bresp_w :
                         wr_sel_sha_q ? sha_bresp_w :
                         wr_sel_aes_q ? aes_bresp_w :
                         wr_sel_sec_q ? sec_bresp_w :
                         wr_sel_sig_q ? sig_bresp_w :
                         wr_sel_err_q ? 2'b11 : 2'b00;

    assign m_bid_o     = wr_sel_rom_q ? rom_bid_w :
                         wr_sel_ram_q ? ram_bid_w :
                         wr_sel_sha_q ? sha_bid_w :
                         wr_sel_aes_q ? aes_bid_w :
                         wr_sel_sec_q ? sec_bid_w :
                         wr_sel_sig_q ? sig_bid_w :
                         wr_sel_err_q ? err_bid_q : 4'd0;

    assign m_arready_o = ar_to_rom_w ? rom_arready_w :
                         ar_to_ram_w ? ram_arready_w :
                         ar_to_sha_w ? sha_arready_w :
                         ar_to_aes_w ? aes_arready_w :
                         ar_to_sec_w ? sec_arready_w :
                         ar_to_sig_w ? sig_arready_w :
                         rd_sel_err_q ? 1'b1 : 1'b0;

    assign m_rvalid_o  = rd_sel_rom_q ? rom_rvalid_w :
                         rd_sel_ram_q ? ram_rvalid_w :
                         rd_sel_sha_q ? sha_rvalid_w :
                         rd_sel_aes_q ? aes_rvalid_w :
                         rd_sel_sec_q ? sec_rvalid_w :
                         rd_sel_sig_q ? sig_rvalid_w :
                         rd_sel_err_q ? err_rvalid_q : 1'b0;

    assign m_rdata_o   = rd_sel_rom_q ? rom_rdata_w :
                         rd_sel_ram_q ? ram_rdata_w :
                         rd_sel_sha_q ? sha_rdata_w :
                         rd_sel_aes_q ? aes_rdata_w :
                         rd_sel_sec_q ? sec_rdata_w :
                         rd_sel_sig_q ? sig_rdata_w :
                         rd_sel_err_q ? 32'hDEADC0DE : 32'h0;

    assign m_rresp_o   = rd_sel_rom_q ? rom_rresp_w :
                         rd_sel_ram_q ? ram_rresp_w :
                         rd_sel_sha_q ? sha_rresp_w :
                         rd_sel_aes_q ? aes_rresp_w :
                         rd_sel_sec_q ? sec_rresp_w :
                         rd_sel_sig_q ? sig_rresp_w :
                         rd_sel_err_q ? 2'b11 : 2'b00;

    assign m_rid_o     = rd_sel_rom_q ? rom_rid_w :
                         rd_sel_ram_q ? ram_rid_w :
                         rd_sel_sha_q ? sha_rid_w :
                         rd_sel_aes_q ? aes_rid_w :
                         rd_sel_sec_q ? sec_rid_w :
                         rd_sel_sig_q ? sig_rid_w :
                         rd_sel_err_q ? err_rid_q : 4'd0;

    assign m_rlast_o   = rd_sel_rom_q ? rom_rlast_w :
                         rd_sel_ram_q ? ram_rlast_w :
                         rd_sel_sha_q ? sha_rlast_w :
                         rd_sel_aes_q ? aes_rlast_w :
                         rd_sel_sec_q ? sec_rlast_w :
                         rd_sel_sig_q ? sig_rlast_w :
                         rd_sel_err_q ? err_rvalid_q : 1'b0;

endmodule
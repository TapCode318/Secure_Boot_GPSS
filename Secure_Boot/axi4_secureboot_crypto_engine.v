`timescale 1ns/1ps

module axi4_secureboot_crypto_engine #(
    parameter BASE_ADDR       = 32'h60000000,
    parameter ROM_INIT_FILE   = "firmware_cipher.hex",
    parameter ROM_WORDS       = 128,
    parameter FIFO_DEPTH      = 16,
    parameter ALLOW_KEY_WRITE = 1,
    parameter [255:0] FIXED_KEY = 256'h0
)(
    input  wire         clk_i,
    input  wire         rst_i,

    // AXI4 write address channel, 32-bit subset used by current SoC bus
    input  wire         axi_awvalid_i,
    input  wire [31:0]  axi_awaddr_i,
    input  wire [3:0]   axi_awid_i,
    input  wire [7:0]   axi_awlen_i,
    input  wire [1:0]   axi_awburst_i,
    output reg          axi_awready_o,

    // AXI4 write data channel
    input  wire         axi_wvalid_i,
    input  wire [31:0]  axi_wdata_i,
    input  wire [3:0]   axi_wstrb_i,
    input  wire         axi_wlast_i,
    output reg          axi_wready_o,

    // AXI4 write response channel
    input  wire         axi_bready_i,
    output reg          axi_bvalid_o,
    output reg  [1:0]   axi_bresp_o,
    output reg  [3:0]   axi_bid_o,

    // AXI4 read address channel
    input  wire         axi_arvalid_i,
    input  wire [31:0]  axi_araddr_i,
    input  wire [3:0]   axi_arid_i,
    input  wire [7:0]   axi_arlen_i,
    input  wire [1:0]   axi_arburst_i,
    output reg          axi_arready_o,

    // AXI4 read data channel
    input  wire         axi_rready_i,
    output reg          axi_rvalid_o,
    output reg  [31:0]  axi_rdata_o,
    output reg  [1:0]   axi_rresp_o,
    output reg  [3:0]   axi_rid_o,
    output reg          axi_rlast_o
);

    localparam AXI_RESP_OKAY   = 2'b00;
    localparam AXI_RESP_SLVERR = 2'b10;

    localparam AXI_BURST_FIXED = 2'b00;
    localparam AXI_BURST_INCR  = 2'b01;

    // Register map
    localparam REG_CTRL        = 8'h00; // W: bit0 start, bit1 clear
    localparam REG_STATUS      = 8'h04; // R: bit0 busy, bit1 done, bit2 error, bit3 sha_overflow
    localparam REG_FW_SIZE     = 8'h08; // firmware plaintext size in bytes
    localparam REG_FW_OFFSET   = 8'h0C; // ciphertext start word offset inside ROM_INIT_FILE
    localparam REG_CTR0        = 8'h10; // ctr_init[127:96]
    localparam REG_CTR1        = 8'h14;
    localparam REG_CTR2        = 8'h18;
    localparam REG_CTR3        = 8'h1C;
    localparam REG_KEY0        = 8'h20; // key[255:224]
    localparam REG_KEY7        = 8'h3C; // key[31:0]
    localparam REG_DIGEST0     = 8'h80; // digest[31:0]
    localparam REG_DIGEST15    = 8'hBC; // digest[511:480]

    // ============================================================
    // Local firmware ciphertext ROM. Each line in ROM_INIT_FILE is 1 word.
    // ============================================================
    reg [31:0] fw_rom [0:ROM_WORDS-1];
    integer init_i;
    initial begin
        for (init_i = 0; init_i < ROM_WORDS; init_i = init_i + 1)
            fw_rom[init_i] = 32'd0;
        if (ROM_INIT_FILE != "")
            $readmemh(ROM_INIT_FILE, fw_rom);
    end

    // ============================================================
    // AXI-visible configuration registers
    // ============================================================
    reg [31:0]  fw_size_bytes_q;
    reg [31:0]  fw_word_offset_q;
    reg [127:0] ctr_init_q;
    reg [255:0] key_q;

    reg         start_pulse_q;
    reg         clear_pulse_q;

    // Captured run-time configuration. CPU may rewrite config while busy,
    // but engine keeps using captured values until next start.
    reg [31:0]  run_fw_size_bytes_q;
    reg [31:0]  run_fw_word_offset_q;
    reg [127:0] run_ctr_init_q;
    reg [255:0] run_key_q;

    // ============================================================
    // AES-CTR stream
    // ============================================================
    reg          aes_key_load_q;
    reg          aes_ctr_load_q;
    reg          aes_valid_in_q;
    reg  [127:0] aes_data_in_q;
    reg          aes_last_in_q;
    reg  [15:0]  aes_keep_in_q;

    wire         aes_ready_in_w;
    wire         aes_valid_out_w;
    wire [127:0] aes_data_out_w;
    wire         aes_last_out_w;
    wire [15:0]  aes_keep_out_w;
    wire [127:0] aes_ctr_dbg_w;
    wire [127:0] aes_keystream_dbg_w;

    aes256_ctr_stream u_aes256_ctr_stream (
        .clk          (clk_i),
        .rst          (rst_i),
        .key_load     (aes_key_load_q),
        .key_in       (run_key_q),
        .ctr_load     (aes_ctr_load_q),
        .ctr_init     (run_ctr_init_q),
        .valid_in     (aes_valid_in_q),
        .data_in      (aes_data_in_q),
        .last_in      (aes_last_in_q),
        .keep_in      (aes_keep_in_q),
        .ready_in     (aes_ready_in_w),
        .valid_out    (aes_valid_out_w),
        .data_out     (aes_data_out_w),
        .last_out     (aes_last_out_w),
        .keep_out     (aes_keep_out_w),
        .ctr_dbg      (aes_ctr_dbg_w),
        .keystream_dbg(aes_keystream_dbg_w)
    );

    // ============================================================
    // SHA3 wrapper
    // ============================================================
    reg         sha_init_q;
    reg         sha_start_q;
    reg         sha_data_valid_q;
    reg [31:0]  sha_data_q;
    reg         sha_is_last_q;
    reg [1:0]   sha_byte_num_q;

    wire        sha_input_ready_w;
    wire        sha_overflow_w;
    wire        sha_busy_w;
    wire        sha_done_w;
    wire [511:0] sha_digest_w;

    sha3_real_wrapper #(
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_sha3_real_wrapper (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .init_i          (sha_init_q),
        .start_i         (sha_start_q),
        .data_valid_i    (sha_data_valid_q),
        .data_i          (sha_data_q),
        .data_is_last_i  (sha_is_last_q),
        .data_byte_num_i (sha_byte_num_q),
        .input_ready_o   (sha_input_ready_w),
        .overflow_o      (sha_overflow_w),
        .busy_o          (sha_busy_w),
        .done_o          (sha_done_w),
        .digest_o        (sha_digest_w)
    );

    // ============================================================
    // Helper functions
    // ============================================================
    function [31:0] apply_wstrb;
        input [31:0] old_data;
        input [31:0] new_data;
        input [3:0]  strb;
        begin
            apply_wstrb[7:0]   = strb[0] ? new_data[7:0]   : old_data[7:0];
            apply_wstrb[15:8]  = strb[1] ? new_data[15:8]  : old_data[15:8];
            apply_wstrb[23:16] = strb[2] ? new_data[23:16] : old_data[23:16];
            apply_wstrb[31:24] = strb[3] ? new_data[31:24] : old_data[31:24];
        end
    endfunction

    function [15:0] make_keep;
        input [4:0] nbytes;
        begin
            case (nbytes)
                5'd0 : make_keep = 16'h0000;
                5'd1 : make_keep = 16'h0001;
                5'd2 : make_keep = 16'h0003;
                5'd3 : make_keep = 16'h0007;
                5'd4 : make_keep = 16'h000F;
                5'd5 : make_keep = 16'h001F;
                5'd6 : make_keep = 16'h003F;
                5'd7 : make_keep = 16'h007F;
                5'd8 : make_keep = 16'h00FF;
                5'd9 : make_keep = 16'h01FF;
                5'd10: make_keep = 16'h03FF;
                5'd11: make_keep = 16'h07FF;
                5'd12: make_keep = 16'h0FFF;
                5'd13: make_keep = 16'h1FFF;
                5'd14: make_keep = 16'h3FFF;
                5'd15: make_keep = 16'h7FFF;
                default: make_keep = 16'hFFFF;
            endcase
        end
    endfunction

    function [4:0] keep_to_nbytes;
        input [15:0] keep;
        integer k;
        begin
            keep_to_nbytes = 5'd0;
            for (k = 0; k < 16; k = k + 1) begin
                if (keep[k])
                    keep_to_nbytes = keep_to_nbytes + 5'd1;
            end
        end
    endfunction

    function [1:0] last_word_index_from_nbytes;
        input [4:0] nbytes;
        begin
            if (nbytes <= 5'd4)
                last_word_index_from_nbytes = 2'd0;
            else if (nbytes <= 5'd8)
                last_word_index_from_nbytes = 2'd1;
            else if (nbytes <= 5'd12)
                last_word_index_from_nbytes = 2'd2;
            else
                last_word_index_from_nbytes = 2'd3;
        end
    endfunction

    function [1:0] last_byte_num_from_nbytes;
        input [4:0] nbytes;
        begin
            case (nbytes[1:0])
                2'd0: last_byte_num_from_nbytes = 2'd0;
                2'd1: last_byte_num_from_nbytes = 2'd1;
                2'd2: last_byte_num_from_nbytes = 2'd2;
                default: last_byte_num_from_nbytes = 2'd3;
            endcase
        end
    endfunction

    function [31:0] select_word;
        input [127:0] block;
        input [1:0]   idx;
        begin
            case (idx)
                2'd0: select_word = block[127:96];
                2'd1: select_word = block[95:64];
                2'd2: select_word = block[63:32];
                default: select_word = block[31:0];
            endcase
        end
    endfunction

    // Engine status regs are declared before read_reg because read_reg exposes them.
    reg [3:0]   engine_state_q;
    reg         engine_busy_q;
    reg         engine_done_q;
    reg         engine_error_q;

    function [31:0] read_reg;
        input [7:0] off;
        begin
            case (off)
                REG_CTRL:      read_reg = 32'd0;
                REG_STATUS:    read_reg = {28'd0, sha_overflow_w, engine_error_q, engine_done_q, engine_busy_q};
                REG_FW_SIZE:   read_reg = fw_size_bytes_q;
                REG_FW_OFFSET: read_reg = fw_word_offset_q;
                REG_CTR0:      read_reg = ctr_init_q[127:96];
                REG_CTR1:      read_reg = ctr_init_q[95:64];
                REG_CTR2:      read_reg = ctr_init_q[63:32];
                REG_CTR3:      read_reg = ctr_init_q[31:0];
                8'h20:         read_reg = key_q[255:224];
                8'h24:         read_reg = key_q[223:192];
                8'h28:         read_reg = key_q[191:160];
                8'h2C:         read_reg = key_q[159:128];
                8'h30:         read_reg = key_q[127:96];
                8'h34:         read_reg = key_q[95:64];
                8'h38:         read_reg = key_q[63:32];
                8'h3C:         read_reg = key_q[31:0];
                8'h80:         read_reg = sha_digest_w[31:0];
                8'h84:         read_reg = sha_digest_w[63:32];
                8'h88:         read_reg = sha_digest_w[95:64];
                8'h8C:         read_reg = sha_digest_w[127:96];
                8'h90:         read_reg = sha_digest_w[159:128];
                8'h94:         read_reg = sha_digest_w[191:160];
                8'h98:         read_reg = sha_digest_w[223:192];
                8'h9C:         read_reg = sha_digest_w[255:224];
                8'hA0:         read_reg = sha_digest_w[287:256];
                8'hA4:         read_reg = sha_digest_w[319:288];
                8'hA8:         read_reg = sha_digest_w[351:320];
                8'hAC:         read_reg = sha_digest_w[383:352];
                8'hB0:         read_reg = sha_digest_w[415:384];
                8'hB4:         read_reg = sha_digest_w[447:416];
                8'hB8:         read_reg = sha_digest_w[479:448];
                8'hBC:         read_reg = sha_digest_w[511:480];
                default:       read_reg = 32'h6000_BAD0;
            endcase
        end
    endfunction

    // ============================================================
    // AXI4 write burst engine
    // ============================================================
    reg        wr_active_q;
    reg [31:0] wr_addr_q;
    reg [7:0]  wr_beats_left_q;
    reg [1:0]  wr_burst_q;
    reg [3:0]  wr_id_q;
    reg        wr_error_q;

    wire aw_hs_w = axi_awvalid_i && axi_awready_o;
    wire w_hs_w  = axi_wvalid_i  && axi_wready_o;

    // ============================================================
    // AXI4 read burst engine
    // ============================================================
    reg        rd_active_q;
    reg [31:0] rd_addr_q;
    reg [7:0]  rd_beats_left_q;
    reg [1:0]  rd_burst_q;
    reg [3:0]  rd_id_q;
    reg        rd_error_q;

    wire ar_hs_w = axi_arvalid_i && axi_arready_o;
    wire r_hs_w  = axi_rvalid_o  && axi_rready_i;
    wire [31:0] rd_next_addr_w = rd_addr_q + 32'd4;

    // ============================================================
    // Secure boot engine FSM
    // ============================================================
    localparam ST_IDLE      = 4'd0;
    localparam ST_INIT      = 4'd1;
    localparam ST_SHA_START = 4'd2;
    localparam ST_AES_SEND  = 4'd3;
    localparam ST_WAIT_AES  = 4'd4;
    localparam ST_SHA_FEED  = 4'd5;
    localparam ST_WAIT_SHA  = 4'd6;
    localparam ST_DONE      = 4'd7;
    localparam ST_ERROR     = 4'd8;

    reg [31:0]  offset_q;
    reg [127:0] plain_block_q;
    reg [4:0]   valid_bytes_q;
    reg         last_block_q;
    reg [1:0]   sha_word_idx_q;
    reg [1:0]   last_word_idx_q;
    reg [1:0]   last_byte_num_q;

    wire [31:0] remain_w = run_fw_size_bytes_q - offset_q;
    wire [4:0]  valid_bytes_w = (remain_w >= 32'd16) ? 5'd16 : remain_w[4:0];
    wire        last_block_w = (remain_w <= 32'd16);
    wire [31:0] rom_idx_w = run_fw_word_offset_q + (offset_q >> 2);
    wire        rom_range_ok_w = ((rom_idx_w + 32'd3) < ROM_WORDS);

    // ============================================================
    // Main sequential logic
    // ============================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            axi_awready_o <= 1'b1;
            axi_wready_o  <= 1'b0;
            axi_bvalid_o  <= 1'b0;
            axi_bresp_o   <= AXI_RESP_OKAY;
            axi_bid_o     <= 4'd0;

            axi_arready_o <= 1'b1;
            axi_rvalid_o  <= 1'b0;
            axi_rdata_o   <= 32'd0;
            axi_rresp_o   <= AXI_RESP_OKAY;
            axi_rid_o     <= 4'd0;
            axi_rlast_o   <= 1'b0;

            wr_active_q     <= 1'b0;
            wr_addr_q       <= 32'd0;
            wr_beats_left_q <= 8'd0;
            wr_burst_q      <= AXI_BURST_INCR;
            wr_id_q         <= 4'd0;
            wr_error_q      <= 1'b0;

            rd_active_q     <= 1'b0;
            rd_addr_q       <= 32'd0;
            rd_beats_left_q <= 8'd0;
            rd_burst_q      <= AXI_BURST_INCR;
            rd_id_q         <= 4'd0;
            rd_error_q      <= 1'b0;

            fw_size_bytes_q  <= 32'd0;
            fw_word_offset_q <= 32'd0;
            ctr_init_q       <= 128'd0;
            key_q            <= FIXED_KEY;
            start_pulse_q    <= 1'b0;
            clear_pulse_q    <= 1'b0;

            run_fw_size_bytes_q  <= 32'd0;
            run_fw_word_offset_q <= 32'd0;
            run_ctr_init_q       <= 128'd0;
            run_key_q            <= FIXED_KEY;

            aes_key_load_q   <= 1'b0;
            aes_ctr_load_q   <= 1'b0;
            aes_valid_in_q   <= 1'b0;
            aes_data_in_q    <= 128'd0;
            aes_last_in_q    <= 1'b0;
            aes_keep_in_q    <= 16'd0;

            sha_init_q       <= 1'b0;
            sha_start_q      <= 1'b0;
            sha_data_valid_q <= 1'b0;
            sha_data_q       <= 32'd0;
            sha_is_last_q    <= 1'b0;
            sha_byte_num_q   <= 2'd0;

            engine_state_q   <= ST_IDLE;
            engine_busy_q    <= 1'b0;
            engine_done_q    <= 1'b0;
            engine_error_q   <= 1'b0;
            offset_q         <= 32'd0;
            plain_block_q    <= 128'd0;
            valid_bytes_q    <= 5'd0;
            last_block_q     <= 1'b0;
            sha_word_idx_q   <= 2'd0;
            last_word_idx_q  <= 2'd0;
            last_byte_num_q  <= 2'd0;
        end else begin
            start_pulse_q    <= 1'b0;
            clear_pulse_q    <= 1'b0;
            aes_key_load_q   <= 1'b0;
            aes_ctr_load_q   <= 1'b0;
            aes_valid_in_q   <= 1'b0;
            aes_last_in_q    <= 1'b0;
            sha_init_q       <= 1'b0;
            sha_start_q      <= 1'b0;
            sha_data_valid_q <= 1'b0;
            sha_is_last_q    <= 1'b0;
            sha_byte_num_q   <= 2'd0;

            // ---------------- AXI4 WRITE ADDRESS ----------------
            if (!wr_active_q && !axi_bvalid_o) begin
                axi_awready_o <= 1'b1;
            end else begin
                axi_awready_o <= 1'b0;
            end

            if (aw_hs_w) begin
                wr_active_q     <= 1'b1;
                wr_addr_q       <= axi_awaddr_i;
                wr_beats_left_q <= axi_awlen_i + 8'd1;
                wr_burst_q      <= axi_awburst_i;
                wr_id_q         <= axi_awid_i;
                wr_error_q      <= !((axi_awburst_i == AXI_BURST_FIXED) ||
                                     (axi_awburst_i == AXI_BURST_INCR));
                axi_wready_o    <= 1'b1;
                axi_awready_o   <= 1'b0;
            end

            // ---------------- AXI4 WRITE DATA ----------------
            if (w_hs_w) begin
                if (!wr_error_q) begin
                    case (wr_addr_q[7:0])
                        REG_CTRL: begin
                            if (axi_wstrb_i != 4'b0000) begin
                                if (axi_wdata_i[0]) start_pulse_q <= 1'b1;
                                if (axi_wdata_i[1]) clear_pulse_q <= 1'b1;
                            end
                        end
                        REG_FW_SIZE:   fw_size_bytes_q  <= apply_wstrb(fw_size_bytes_q,  axi_wdata_i, axi_wstrb_i);
                        REG_FW_OFFSET: fw_word_offset_q <= apply_wstrb(fw_word_offset_q, axi_wdata_i, axi_wstrb_i);
                        REG_CTR0:      ctr_init_q[127:96] <= apply_wstrb(ctr_init_q[127:96], axi_wdata_i, axi_wstrb_i);
                        REG_CTR1:      ctr_init_q[95:64]  <= apply_wstrb(ctr_init_q[95:64],  axi_wdata_i, axi_wstrb_i);
                        REG_CTR2:      ctr_init_q[63:32]  <= apply_wstrb(ctr_init_q[63:32],  axi_wdata_i, axi_wstrb_i);
                        REG_CTR3:      ctr_init_q[31:0]   <= apply_wstrb(ctr_init_q[31:0],   axi_wdata_i, axi_wstrb_i);
                        8'h20: if (ALLOW_KEY_WRITE) key_q[255:224] <= apply_wstrb(key_q[255:224], axi_wdata_i, axi_wstrb_i);
                        8'h24: if (ALLOW_KEY_WRITE) key_q[223:192] <= apply_wstrb(key_q[223:192], axi_wdata_i, axi_wstrb_i);
                        8'h28: if (ALLOW_KEY_WRITE) key_q[191:160] <= apply_wstrb(key_q[191:160], axi_wdata_i, axi_wstrb_i);
                        8'h2C: if (ALLOW_KEY_WRITE) key_q[159:128] <= apply_wstrb(key_q[159:128], axi_wdata_i, axi_wstrb_i);
                        8'h30: if (ALLOW_KEY_WRITE) key_q[127:96]  <= apply_wstrb(key_q[127:96],  axi_wdata_i, axi_wstrb_i);
                        8'h34: if (ALLOW_KEY_WRITE) key_q[95:64]   <= apply_wstrb(key_q[95:64],   axi_wdata_i, axi_wstrb_i);
                        8'h38: if (ALLOW_KEY_WRITE) key_q[63:32]   <= apply_wstrb(key_q[63:32],   axi_wdata_i, axi_wstrb_i);
                        8'h3C: if (ALLOW_KEY_WRITE) key_q[31:0]    <= apply_wstrb(key_q[31:0],    axi_wdata_i, axi_wstrb_i);
                        default: begin
                            // unmapped write is ignored but completes OKAY
                        end
                    endcase
                end

                if (wr_burst_q == AXI_BURST_INCR)
                    wr_addr_q <= wr_addr_q + 32'd4;

                if (wr_beats_left_q != 8'd0)
                    wr_beats_left_q <= wr_beats_left_q - 8'd1;

                if ((wr_beats_left_q == 8'd1) || axi_wlast_i) begin
                    wr_active_q   <= 1'b0;
                    axi_wready_o  <= 1'b0;
                    axi_bvalid_o  <= 1'b1;
                    axi_bresp_o   <= (wr_error_q || (axi_wlast_i != (wr_beats_left_q == 8'd1))) ?
                                      AXI_RESP_SLVERR : AXI_RESP_OKAY;
                    axi_bid_o     <= wr_id_q;
                end
            end

            if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o <= 1'b0;
                axi_bresp_o  <= AXI_RESP_OKAY;
            end

            // ---------------- AXI4 READ ADDRESS ----------------
            if (!rd_active_q && !axi_rvalid_o) begin
                axi_arready_o <= 1'b1;
            end else begin
                axi_arready_o <= 1'b0;
            end

            if (ar_hs_w) begin
                rd_active_q     <= 1'b1;
                rd_addr_q       <= axi_araddr_i;
                rd_beats_left_q <= axi_arlen_i + 8'd1;
                rd_burst_q      <= axi_arburst_i;
                rd_id_q         <= axi_arid_i;
                rd_error_q      <= !((axi_arburst_i == AXI_BURST_FIXED) ||
                                     (axi_arburst_i == AXI_BURST_INCR));

                axi_rvalid_o    <= 1'b1;
                axi_rdata_o     <= read_reg(axi_araddr_i[7:0]);
                axi_rresp_o     <= (!((axi_arburst_i == AXI_BURST_FIXED) ||
                                      (axi_arburst_i == AXI_BURST_INCR))) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                axi_rid_o       <= axi_arid_i;
                axi_rlast_o     <= (axi_arlen_i == 8'd0);
                axi_arready_o   <= 1'b0;
            end

            if (r_hs_w) begin
                if (rd_beats_left_q <= 8'd1) begin
                    rd_active_q    <= 1'b0;
                    axi_rvalid_o   <= 1'b0;
                    axi_rlast_o    <= 1'b0;
                    rd_beats_left_q<= 8'd0;
                end else begin
                    rd_beats_left_q <= rd_beats_left_q - 8'd1;
                    if (rd_burst_q == AXI_BURST_INCR)
                        rd_addr_q <= rd_addr_q + 32'd4;
                    axi_rdata_o <= (rd_burst_q == AXI_BURST_INCR) ?
                                   read_reg(rd_next_addr_w[7:0]) : read_reg(rd_addr_q[7:0]);
                    axi_rresp_o <= rd_error_q ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                    axi_rid_o   <= rd_id_q;
                    axi_rlast_o <= (rd_beats_left_q == 8'd2);
                end
            end

            // ---------------- Secure boot engine ----------------
            if (clear_pulse_q) begin
                engine_state_q <= ST_IDLE;
                engine_busy_q  <= 1'b0;
                engine_done_q  <= 1'b0;
                engine_error_q <= 1'b0;
                offset_q       <= 32'd0;
            end else begin
                case (engine_state_q)
                    ST_IDLE: begin
                        if (start_pulse_q) begin
                            engine_done_q <= 1'b0;
                            engine_error_q<= 1'b0;

                            run_fw_size_bytes_q  <= fw_size_bytes_q;
                            run_fw_word_offset_q <= fw_word_offset_q;
                            run_ctr_init_q       <= ctr_init_q;
                            run_key_q            <= ALLOW_KEY_WRITE ? key_q : FIXED_KEY;
                            offset_q             <= 32'd0;

                            if (fw_size_bytes_q == 32'd0) begin
                                engine_error_q <= 1'b1;
                                engine_state_q <= ST_ERROR;
                            end else begin
                                engine_busy_q  <= 1'b1;
                                sha_init_q     <= 1'b1;
                                aes_key_load_q <= 1'b1;
                                aes_ctr_load_q <= 1'b1;
                                engine_state_q <= ST_INIT;
                            end
                        end
                    end

                    ST_INIT: begin
                        // AES key_load is kept at least 1 clock before first data block.
                        sha_start_q    <= 1'b1;
                        engine_state_q <= ST_SHA_START;
                    end

                    ST_SHA_START: begin
                        engine_state_q <= ST_AES_SEND;
                    end

                    ST_AES_SEND: begin
                        if (!rom_range_ok_w) begin
                            engine_error_q <= 1'b1;
                            engine_busy_q  <= 1'b0;
                            engine_state_q <= ST_ERROR;
                        end else if (aes_ready_in_w) begin
                            aes_data_in_q <= {
                                fw_rom[rom_idx_w + 32'd0],
                                fw_rom[rom_idx_w + 32'd1],
                                fw_rom[rom_idx_w + 32'd2],
                                fw_rom[rom_idx_w + 32'd3]
                            };
                            aes_keep_in_q  <= make_keep(valid_bytes_w);
                            aes_last_in_q  <= last_block_w;
                            aes_valid_in_q <= 1'b1;
                            valid_bytes_q  <= valid_bytes_w;
                            last_block_q   <= last_block_w;
                            engine_state_q <= ST_WAIT_AES;
                        end
                    end

                    ST_WAIT_AES: begin
                        if (aes_valid_out_w) begin
                            plain_block_q   <= aes_data_out_w;
                            valid_bytes_q   <= keep_to_nbytes(aes_keep_out_w);
                            last_block_q    <= aes_last_out_w;
                            sha_word_idx_q  <= 2'd0;
                            last_word_idx_q <= last_word_index_from_nbytes(keep_to_nbytes(aes_keep_out_w));
                            last_byte_num_q <= last_byte_num_from_nbytes(keep_to_nbytes(aes_keep_out_w));
                            engine_state_q  <= ST_SHA_FEED;
                        end
                    end

                    ST_SHA_FEED: begin
                        if (sha_input_ready_w) begin
                            sha_data_valid_q <= 1'b1;
                            sha_data_q       <= select_word(plain_block_q, sha_word_idx_q);

                            if (!last_block_q) begin
                                sha_is_last_q  <= 1'b0;
                                sha_byte_num_q <= 2'd0;
                                if (sha_word_idx_q == 2'd3) begin
                                    sha_word_idx_q <= 2'd0;
                                    offset_q       <= offset_q + 32'd16;
                                    engine_state_q <= ST_AES_SEND;
                                end else begin
                                    sha_word_idx_q <= sha_word_idx_q + 2'd1;
                                end
                            end else begin
                                if (sha_word_idx_q == last_word_idx_q) begin
                                    sha_is_last_q  <= 1'b1;
                                    sha_byte_num_q <= last_byte_num_q;
                                    engine_state_q <= ST_WAIT_SHA;
                                end else begin
                                    sha_is_last_q  <= 1'b0;
                                    sha_byte_num_q <= 2'd0;
                                    sha_word_idx_q <= sha_word_idx_q + 2'd1;
                                end
                            end
                        end
                    end

                    ST_WAIT_SHA: begin
                        if (sha_done_w) begin
                            engine_busy_q  <= 1'b0;
                            engine_done_q  <= 1'b1;
                            engine_state_q <= ST_DONE;
                        end
                    end

                    ST_DONE: begin
                        if (start_pulse_q) begin
                            engine_done_q <= 1'b0;
                            run_fw_size_bytes_q  <= fw_size_bytes_q;
                            run_fw_word_offset_q <= fw_word_offset_q;
                            run_ctr_init_q       <= ctr_init_q;
                            run_key_q            <= ALLOW_KEY_WRITE ? key_q : FIXED_KEY;
                            offset_q             <= 32'd0;
                            engine_busy_q        <= 1'b1;
                            sha_init_q           <= 1'b1;
                            aes_key_load_q       <= 1'b1;
                            aes_ctr_load_q       <= 1'b1;
                            engine_state_q       <= ST_INIT;
                        end
                    end

                    ST_ERROR: begin
                        engine_busy_q <= 1'b0;
                    end

                    default: begin
                        engine_state_q <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule

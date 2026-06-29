module axi_sha3_regs #(
    parameter BASE_ADDR = 32'h40000000
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

    input  wire         axi_arvalid_i,
    input  wire [31:0]  axi_araddr_i,
    input  wire [3:0]   axi_arid_i,
    input  wire [7:0]   axi_arlen_i,
    input  wire [1:0]   axi_arburst_i,
    input  wire         axi_rready_i,

    output reg          axi_awready_o,
    output reg          axi_wready_o,
    output reg          axi_bvalid_o,
    output reg  [1:0]   axi_bresp_o,
    output reg  [3:0]   axi_bid_o,

    output reg          axi_arready_o,
    output reg          axi_rvalid_o,
    output reg  [31:0]  axi_rdata_o,
    output reg  [1:0]   axi_rresp_o,
    output reg  [3:0]   axi_rid_o,
    output reg          axi_rlast_o,

    output reg          sha_init_o,
    output reg          sha_start_o,
    output reg          sha_data_valid_o,
    output reg  [31:0]  sha_data_o,
    output reg          sha_is_last_o,
    output reg  [1:0]   sha_byte_num_o,

    input  wire         sha_busy_i,
    input  wire         sha_done_i,
    input  wire [511:0] sha_digest_i
);

    reg [31:0] msg_word_count_q;
    reg [31:0] awaddr_q;
    reg [3:0]  awid_q;
    reg        aw_seen_q;
    reg        w_seen_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg [7:0]  awlen_q;
    reg        wlast_q;
    reg [1:0]  last_byte_num_cfg_q;

    wire [7:0] wr_offset_w = awaddr_q[7:0];
    wire [7:0] rd_offset_w = axi_araddr_i[7:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            axi_awready_o       <= 1'b1;
            axi_wready_o        <= 1'b1;
            axi_bvalid_o        <= 1'b0;
            axi_bresp_o         <= 2'b00;
            axi_bid_o           <= 4'd0;

            axi_arready_o       <= 1'b1;
            axi_rvalid_o        <= 1'b0;
            axi_rdata_o         <= 32'd0;
            axi_rresp_o         <= 2'b00;
            axi_rid_o           <= 4'd0;
            axi_rlast_o         <= 1'b0;

            msg_word_count_q    <= 32'd0;
            awaddr_q            <= 32'd0;
            awid_q              <= 4'd0;
            aw_seen_q           <= 1'b0;
            w_seen_q            <= 1'b0;
            wdata_q             <= 32'd0;
            wstrb_q             <= 4'd0;
            awlen_q             <= 8'd0;
            wlast_q             <= 1'b0;
            last_byte_num_cfg_q <= 2'b00;

            sha_init_o          <= 1'b0;
            sha_start_o         <= 1'b0;
            sha_data_valid_o    <= 1'b0;
            sha_data_o          <= 32'd0;
            sha_is_last_o       <= 1'b0;
            sha_byte_num_o      <= 2'b00;
        end else begin
            // pulse mặc định
            sha_init_o       <= 1'b0;
            sha_start_o      <= 1'b0;
            sha_data_valid_o <= 1'b0;
            sha_is_last_o    <= 1'b0;
            sha_byte_num_o   <= 2'b00;

            // nhận AW
            if (axi_awready_o && axi_awvalid_i) begin
                awaddr_q      <= axi_awaddr_i;
                awid_q        <= axi_awid_i;
                awlen_q       <= axi_awlen_i;
                aw_seen_q     <= 1'b1;
                axi_awready_o <= 1'b0;
            end

            // nhận W
            if (axi_wready_o && axi_wvalid_i) begin
                wdata_q      <= axi_wdata_i;
                wstrb_q      <= axi_wstrb_i;
                wlast_q      <= axi_wlast_i;
                w_seen_q     <= 1'b1;
                axi_wready_o <= 1'b0;
            end

            // tạo B response
            if (aw_seen_q && w_seen_q && !axi_bvalid_o) begin
                axi_bvalid_o <= 1'b1;
                axi_bresp_o  <= 2'b00;
                axi_bid_o    <= awid_q;

                // chỉ hỗ trợ single-beat write
                if ((awlen_q != 8'd0) || !wlast_q) begin
                    axi_bresp_o <= 2'b10;
                end else begin
                    case (wr_offset_w)
                        8'h00: begin
                            if (wstrb_q != 4'b0000) begin
                                if (wdata_q[0]) begin
                                    sha_init_o          <= 1'b1;
                                    msg_word_count_q    <= 32'd0;
                                    last_byte_num_cfg_q <= 2'b00;
                                end
                                if (wdata_q[1]) begin
                                    sha_start_o <= 1'b1;
                                end
                            end
                        end

                        // word thường
                        8'h08: begin
                            sha_data_o       <= wdata_q;
                            sha_data_valid_o <= 1'b1;
                            sha_is_last_o    <= 1'b0;
                            sha_byte_num_o   <= 2'b00;
                            msg_word_count_q <= msg_word_count_q + 32'd1;
                        end

                        // word cuối
                        8'h0C: begin
                            sha_data_o       <= wdata_q;
                            sha_data_valid_o <= 1'b1;
                            sha_is_last_o    <= 1'b1;
                            sha_byte_num_o   <= last_byte_num_cfg_q;
                            msg_word_count_q <= msg_word_count_q + 32'd1;
                        end

                        // cấu hình số byte hợp lệ của word cuối:
                        // 0 = đủ 4 byte, 1/2/3 = chỉ 1/2/3 byte hợp lệ
                        8'h10: begin
                            if (wstrb_q[0])
                                last_byte_num_cfg_q <= wdata_q[1:0];
                        end

                        default: begin
                        end
                    endcase
                end

                aw_seen_q <= 1'b0;
                w_seen_q  <= 1'b0;
            end else if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o  <= 1'b0;
                axi_awready_o <= 1'b1;
                axi_wready_o  <= 1'b1;
            end

            // read channel
            if (axi_arready_o && axi_arvalid_i && !axi_rvalid_o) begin
                axi_arready_o <= 1'b0;
                axi_rvalid_o  <= 1'b1;
                axi_rresp_o   <= 2'b00;
                axi_rid_o     <= axi_arid_i;
                axi_rlast_o   <= 1'b1;

                if (axi_arlen_i != 8'd0)
                    axi_rresp_o <= 2'b10;

                case (rd_offset_w)
                    8'h00: axi_rdata_o <= 32'd0;
                    8'h04: axi_rdata_o <= {30'd0, sha_done_i, sha_busy_i};
                    8'h0C: axi_rdata_o <= msg_word_count_q;
                    8'h10: axi_rdata_o <= {30'd0, last_byte_num_cfg_q};

                    8'h20: axi_rdata_o <= sha_digest_i[31:0];
                    8'h24: axi_rdata_o <= sha_digest_i[63:32];
                    8'h28: axi_rdata_o <= sha_digest_i[95:64];
                    8'h2C: axi_rdata_o <= sha_digest_i[127:96];
                    8'h30: axi_rdata_o <= sha_digest_i[159:128];
                    8'h34: axi_rdata_o <= sha_digest_i[191:160];
                    8'h38: axi_rdata_o <= sha_digest_i[223:192];
                    8'h3C: axi_rdata_o <= sha_digest_i[255:224];
                    8'h40: axi_rdata_o <= sha_digest_i[287:256];
                    8'h44: axi_rdata_o <= sha_digest_i[319:288];
                    8'h48: axi_rdata_o <= sha_digest_i[351:320];
                    8'h4C: axi_rdata_o <= sha_digest_i[383:352];
                    8'h50: axi_rdata_o <= sha_digest_i[415:384];
                    8'h54: axi_rdata_o <= sha_digest_i[447:416];
                    8'h58: axi_rdata_o <= sha_digest_i[479:448];
                    8'h5C: axi_rdata_o <= sha_digest_i[511:480];

                    default: axi_rdata_o <= 32'hBAD00000;
                endcase
            end else if (axi_rvalid_o && axi_rready_i) begin
                axi_rvalid_o  <= 1'b0;
                axi_rlast_o   <= 1'b0;
                axi_arready_o <= 1'b1;
            end
        end
    end

endmodule
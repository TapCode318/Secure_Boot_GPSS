module axi_aes256_ctr_regs #(
    parameter BASE_ADDR          = 32'h50000000,
    parameter ALLOW_KEY_WRITE    = 1,
    parameter [255:0] FIXED_KEY  = 256'h0000000000000000000000000000000000000000000000000000000000000000
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

    output reg          aes_key_load_o,
    output reg          aes_ctr_load_o,
    output reg          aes_valid_in_o,
    output reg  [255:0] aes_key_o,
    output reg  [127:0] aes_ctr_init_o,
    output reg  [127:0] aes_data_in_o,
    output reg          aes_last_in_o,
    output reg  [15:0]  aes_keep_in_o,

    input  wire         aes_ready_in_i,
    input  wire         aes_valid_out_i,
    input  wire [127:0] aes_data_out_i,
    input  wire         aes_last_out_i,
    input  wire [15:0]  aes_keep_out_i
);

    reg [31:0] awaddr_q;
    reg [3:0]  awid_q;
    reg [7:0]  awlen_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        wlast_q;
    reg        aw_seen_q;
    reg        w_seen_q;

    reg        busy_q;
    reg        out_valid_sticky_q;
    reg [127:0] out_data_q;
    reg         out_last_q;
    reg [15:0]  out_keep_q;

    wire [7:0] wr_offset_w = awaddr_q[7:0];
    wire [7:0] rd_offset_w = axi_araddr_i[7:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            axi_awready_o     <= 1'b1;
            axi_wready_o      <= 1'b1;
            axi_bvalid_o      <= 1'b0;
            axi_bresp_o       <= 2'b00;
            axi_bid_o         <= 4'd0;

            axi_arready_o     <= 1'b1;
            axi_rvalid_o      <= 1'b0;
            axi_rdata_o       <= 32'd0;
            axi_rresp_o       <= 2'b00;
            axi_rid_o         <= 4'd0;
            axi_rlast_o       <= 1'b0;

            awaddr_q          <= 32'd0;
            awid_q            <= 4'd0;
            awlen_q           <= 8'd0;
            wdata_q           <= 32'd0;
            wstrb_q           <= 4'd0;
            wlast_q           <= 1'b0;
            aw_seen_q         <= 1'b0;
            w_seen_q          <= 1'b0;

            aes_key_load_o    <= 1'b0;
            aes_ctr_load_o    <= 1'b0;
            aes_valid_in_o    <= 1'b0;
            aes_key_o         <= FIXED_KEY;
            aes_ctr_init_o    <= 128'd0;
            aes_data_in_o     <= 128'd0;
            aes_last_in_o     <= 1'b0;
            aes_keep_in_o     <= 16'hFFFF;

            busy_q            <= 1'b0;
            out_valid_sticky_q<= 1'b0;
            out_data_q        <= 128'd0;
            out_last_q        <= 1'b0;
            out_keep_q        <= 16'd0;
        end else begin
            aes_key_load_o <= 1'b0;
            aes_ctr_load_o <= 1'b0;
            aes_valid_in_o <= 1'b0;
            aes_last_in_o  <= 1'b0;

            if (aes_valid_out_i) begin
                out_valid_sticky_q <= 1'b1;
                out_data_q         <= aes_data_out_i;
                out_last_q         <= aes_last_out_i;
                out_keep_q         <= aes_keep_out_i;
                busy_q             <= 1'b0;
            end

            if (axi_awready_o && axi_awvalid_i) begin
                awaddr_q      <= axi_awaddr_i;
                awid_q        <= axi_awid_i;
                awlen_q       <= axi_awlen_i;
                aw_seen_q     <= 1'b1;
                axi_awready_o <= 1'b0;
            end

            if (axi_wready_o && axi_wvalid_i) begin
                wdata_q      <= axi_wdata_i;
                wstrb_q      <= axi_wstrb_i;
                wlast_q      <= axi_wlast_i;
                w_seen_q     <= 1'b1;
                axi_wready_o <= 1'b0;
            end

            if (aw_seen_q && w_seen_q && !axi_bvalid_o) begin
                axi_bvalid_o <= 1'b1;
                axi_bresp_o  <= 2'b00;
                axi_bid_o    <= awid_q;

                if ((awlen_q != 8'd0) || !wlast_q) begin
                    axi_bresp_o <= 2'b10;
                end else begin
                    case (wr_offset_w)
                        8'h00: begin
                            if (wstrb_q != 4'b0000) begin
                                if (wdata_q[4])
                                    out_valid_sticky_q <= 1'b0;

                                if (wdata_q[0]) begin
                                    aes_key_load_o <= 1'b1;
                                    if (!ALLOW_KEY_WRITE)
                                        aes_key_o <= FIXED_KEY;
                                end

                                if (wdata_q[1])
                                    aes_ctr_load_o <= 1'b1;

                                if (wdata_q[2]) begin
                                    if (busy_q || !aes_ready_in_i) begin
                                        axi_bresp_o <= 2'b10;
                                    end else begin
                                        aes_valid_in_o <= 1'b1;
                                        aes_last_in_o  <= wdata_q[3];
                                        busy_q         <= 1'b1;
                                    end
                                end
                            end
                        end

                        8'h20: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[31:0]    <= wdata_q;
                        8'h24: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[63:32]   <= wdata_q;
                        8'h28: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[95:64]   <= wdata_q;
                        8'h2C: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[127:96]  <= wdata_q;
                        8'h30: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[159:128] <= wdata_q;
                        8'h34: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[191:160] <= wdata_q;
                        8'h38: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[223:192] <= wdata_q;
                        8'h3C: if (ALLOW_KEY_WRITE && wstrb_q != 4'b0000) aes_key_o[255:224] <= wdata_q;

                        8'h40: if (wstrb_q != 4'b0000) aes_ctr_init_o[31:0]    <= wdata_q;
                        8'h44: if (wstrb_q != 4'b0000) aes_ctr_init_o[63:32]   <= wdata_q;
                        8'h48: if (wstrb_q != 4'b0000) aes_ctr_init_o[95:64]   <= wdata_q;
                        8'h4C: if (wstrb_q != 4'b0000) aes_ctr_init_o[127:96]  <= wdata_q;

                        8'h80: if (wstrb_q != 4'b0000) aes_data_in_o[31:0]     <= wdata_q;
                        8'h84: if (wstrb_q != 4'b0000) aes_data_in_o[63:32]    <= wdata_q;
                        8'h88: if (wstrb_q != 4'b0000) aes_data_in_o[95:64]    <= wdata_q;
                        8'h8C: if (wstrb_q != 4'b0000) aes_data_in_o[127:96]   <= wdata_q;

                        8'h90: if (wstrb_q != 4'b0000) aes_keep_in_o <= wdata_q[15:0];

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
                    8'h04: axi_rdata_o <= {27'd0, out_last_q, busy_q, out_valid_sticky_q, aes_ready_in_i};

                    8'h20: axi_rdata_o <= aes_key_o[31:0];
                    8'h24: axi_rdata_o <= aes_key_o[63:32];
                    8'h28: axi_rdata_o <= aes_key_o[95:64];
                    8'h2C: axi_rdata_o <= aes_key_o[127:96];
                    8'h30: axi_rdata_o <= aes_key_o[159:128];
                    8'h34: axi_rdata_o <= aes_key_o[191:160];
                    8'h38: axi_rdata_o <= aes_key_o[223:192];
                    8'h3C: axi_rdata_o <= aes_key_o[255:224];

                    8'h40: axi_rdata_o <= aes_ctr_init_o[31:0];
                    8'h44: axi_rdata_o <= aes_ctr_init_o[63:32];
                    8'h48: axi_rdata_o <= aes_ctr_init_o[95:64];
                    8'h4C: axi_rdata_o <= aes_ctr_init_o[127:96];

                    8'h80: axi_rdata_o <= aes_data_in_o[31:0];
                    8'h84: axi_rdata_o <= aes_data_in_o[63:32];
                    8'h88: axi_rdata_o <= aes_data_in_o[95:64];
                    8'h8C: axi_rdata_o <= aes_data_in_o[127:96];
                    8'h90: axi_rdata_o <= {16'd0, aes_keep_in_o};

                    8'hA0: axi_rdata_o <= out_data_q[31:0];
                    8'hA4: axi_rdata_o <= out_data_q[63:32];
                    8'hA8: axi_rdata_o <= out_data_q[95:64];
                    8'hAC: axi_rdata_o <= out_data_q[127:96];
                    8'hB0: axi_rdata_o <= {15'd0, out_last_q, out_keep_q};

                    default: axi_rdata_o <= 32'hA5E0_0000;
                endcase
            end else if (axi_rvalid_o && axi_rready_i) begin
                axi_rvalid_o  <= 1'b0;
                axi_rlast_o   <= 1'b0;
                axi_arready_o <= 1'b1;
            end
        end
    end

endmodule

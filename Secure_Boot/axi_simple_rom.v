`timescale 1ns/1ps

module axi_simple_rom #(
    parameter BASE_ADDR = 32'h00000000,
    parameter MEM_WORDS = 1024,
    parameter INIT_FILE = "boot_rom.hex"
)
(
    input  wire        clk_i,
    input  wire        rst_i,

    // AXI Write Address / Data / Response
    input  wire        axi_awvalid_i,
    input  wire [31:0] axi_awaddr_i,
    input  wire [3:0]  axi_awid_i,
    input  wire [7:0]  axi_awlen_i,
    input  wire [1:0]  axi_awburst_i,
    input  wire        axi_wvalid_i,
    input  wire [31:0] axi_wdata_i,
    input  wire [3:0]  axi_wstrb_i,
    input  wire        axi_wlast_i,
    input  wire        axi_bready_i,

    // AXI Read Address / Data
    input  wire        axi_arvalid_i,
    input  wire [31:0] axi_araddr_i,
    input  wire [3:0]  axi_arid_i,
    input  wire [7:0]  axi_arlen_i,
    input  wire [1:0]  axi_arburst_i,
    input  wire        axi_rready_i,

    output wire        axi_awready_o,
    output wire        axi_wready_o,
    output reg         axi_bvalid_o,
    output reg  [1:0]  axi_bresp_o,
    output reg  [3:0]  axi_bid_o,

    output wire        axi_arready_o,
    output reg         axi_rvalid_o,
    output reg  [31:0] axi_rdata_o,
    output reg  [1:0]  axi_rresp_o,
    output reg  [3:0]  axi_rid_o,
    output reg         axi_rlast_o
);

    reg [31:0] mem [0:MEM_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'h00000013; // NOP: addi x0, x0, 0
        $readmemh(INIT_FILE, mem);
    end

    reg        rd_active_q;
    reg [31:0] rd_addr_q;
    reg [7:0]  rd_len_q;
    reg [7:0]  rd_cnt_q;
    reg [3:0]  rd_id_q;
    reg [1:0]  rd_burst_q;

    wire [31:0] next_ar_word_addr_w = ((axi_araddr_i - BASE_ADDR) >> 2);
    wire        rd_last_beat_w      = (rd_cnt_q == rd_len_q);

    assign axi_arready_o = !rd_active_q && !axi_rvalid_o;

    // ROM does not really accept writes, but keeps simple AXI compatibility
    assign axi_awready_o = !axi_bvalid_o;
    assign axi_wready_o  = !axi_bvalid_o;

    always @(posedge clk_i) begin
        if (rst_i) begin
            axi_bvalid_o <= 1'b0;
            axi_bresp_o  <= 2'b00;
            axi_bid_o    <= 4'd0;

            rd_active_q  <= 1'b0;
            rd_addr_q    <= 32'd0;
            rd_len_q     <= 8'd0;
            rd_cnt_q     <= 8'd0;
            rd_id_q      <= 4'd0;
            rd_burst_q   <= 2'b01; // INCR burst

            axi_rvalid_o <= 1'b0;
            axi_rdata_o  <= 32'd0;
            axi_rresp_o  <= 2'b00;
            axi_rid_o    <= 4'd0;
            axi_rlast_o  <= 1'b0;
        end else begin
            // -----------------------------
            // WRITE to ROM => SLVERR
            // -----------------------------
            if (axi_awvalid_i && axi_wvalid_i && !axi_bvalid_o) begin
                axi_bvalid_o <= 1'b1;
                axi_bresp_o  <= 2'b10; // SLVERR
                axi_bid_o    <= axi_awid_i;
            end else if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o <= 1'b0;
            end

            // -----------------------------
            // START READ BURST
            // -----------------------------
            if (axi_arvalid_i && axi_arready_o) begin
                rd_active_q  <= 1'b1;
                rd_addr_q    <= axi_araddr_i;
                rd_len_q     <= axi_arlen_i;
                rd_cnt_q     <= 8'd0;
                rd_id_q      <= axi_arid_i;
                rd_burst_q   <= axi_arburst_i;

                axi_rvalid_o <= 1'b1;
                axi_rid_o    <= axi_arid_i;
                axi_rresp_o  <= 2'b00;
                axi_rlast_o  <= (axi_arlen_i == 8'd0);

                if ((axi_araddr_i >= BASE_ADDR) && (next_ar_word_addr_w < MEM_WORDS)) begin
                    axi_rdata_o <= mem[next_ar_word_addr_w];
                end else begin
                    axi_rdata_o <= 32'hDEADBEEF;
                    axi_rresp_o <= 2'b10; // SLVERR
                end
            end
            // -----------------------------
            // CONTINUE READ BURST
            // -----------------------------
            else if (axi_rvalid_o && axi_rready_i) begin
                if (rd_active_q) begin
                    if (rd_last_beat_w) begin
                        axi_rvalid_o <= 1'b0;
                        axi_rlast_o  <= 1'b0;
                        rd_active_q  <= 1'b0;
                    end else begin
                        rd_cnt_q <= rd_cnt_q + 8'd1;

                        if (rd_burst_q == 2'b00) // FIXED
                            rd_addr_q <= rd_addr_q;
                        else
                            rd_addr_q <= rd_addr_q + 32'd4;

                        axi_rvalid_o <= 1'b1;
                        axi_rid_o    <= rd_id_q;
                        axi_rresp_o  <= 2'b00;
                        axi_rlast_o  <= ((rd_cnt_q + 8'd1) == rd_len_q);

                        if ((((rd_burst_q == 2'b00) ? rd_addr_q : (rd_addr_q + 32'd4)) >= BASE_ADDR) &&
                            (((((rd_burst_q == 2'b00) ? rd_addr_q : (rd_addr_q + 32'd4)) - BASE_ADDR) >> 2) < MEM_WORDS)) begin
                            axi_rdata_o <= mem[((((rd_burst_q == 2'b00) ? rd_addr_q : (rd_addr_q + 32'd4)) - BASE_ADDR) >> 2)];
                        end else begin
                            axi_rdata_o <= 32'hDEADBEEF;
                            axi_rresp_o <= 2'b10; // SLVERR
                        end
                    end
                end else begin
                    axi_rvalid_o <= 1'b0;
                    axi_rlast_o  <= 1'b0;
                end
            end
        end
    end

endmodule
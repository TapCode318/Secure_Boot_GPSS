`timescale 1ns/1ps

module axi_simple_ram #(
    parameter BASE_ADDR = 32'h20000000,
    parameter MEM_WORDS = 1024
)
(
    input  wire         clk_i,
    input  wire         rst_i,

    // AXI Write Channel
    input  wire         axi_awvalid_i,
    input  wire [31:0]  axi_awaddr_i,
    input  wire         axi_wvalid_i,
    input  wire [31:0]  axi_wdata_i,
    input  wire [3:0]   axi_wstrb_i,
    input  wire         axi_bready_i,
    output reg          axi_awready_o,
    output reg          axi_wready_o,
    output reg          axi_bvalid_o,
    output reg  [1:0]   axi_bresp_o,

    // AXI Read Channel
    input  wire         axi_arvalid_i,
    input  wire [31:0]  axi_araddr_i,
    input  wire         axi_rready_i,
    output reg          axi_arready_o,
    output reg          axi_rvalid_o,
    output reg  [31:0]  axi_rdata_o,
    output reg  [1:0]   axi_rresp_o,
    output reg          axi_rlast_o
);

    reg [31:0] mem [0:MEM_WORDS-1];

    reg [31:0] awaddr_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        aw_seen_q;
    reg        w_seen_q;

    wire [31:0] aw_word_idx_w = (awaddr_q      - BASE_ADDR) >> 2;
    wire [31:0] ar_word_idx_w = (axi_araddr_i  - BASE_ADDR) >> 2;
    wire        aw_addr_hit_w = (awaddr_q     >= BASE_ADDR) && (aw_word_idx_w < MEM_WORDS);
    wire        ar_addr_hit_w = (axi_araddr_i >= BASE_ADDR) && (ar_word_idx_w < MEM_WORDS);

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'd0;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            axi_awready_o <= 1'b1;
            axi_wready_o  <= 1'b1;
            axi_bvalid_o  <= 1'b0;
            axi_bresp_o   <= 2'b00;

            axi_arready_o <= 1'b1;
            axi_rvalid_o  <= 1'b0;
            axi_rdata_o   <= 32'd0;
            axi_rresp_o   <= 2'b00;
            axi_rlast_o   <= 1'b0;

            awaddr_q      <= 32'd0;
            wdata_q       <= 32'd0;
            wstrb_q       <= 4'd0;
            aw_seen_q     <= 1'b0;
            w_seen_q      <= 1'b0;
        end else begin
            // ---------------- WRITE ADDRESS ----------------
            if (axi_awready_o && axi_awvalid_i) begin
                awaddr_q      <= axi_awaddr_i;
                aw_seen_q     <= 1'b1;
                axi_awready_o <= 1'b0;
            end

            // ---------------- WRITE DATA ----------------
            if (axi_wready_o && axi_wvalid_i) begin
                wdata_q      <= axi_wdata_i;
                wstrb_q      <= axi_wstrb_i;
                w_seen_q     <= 1'b1;
                axi_wready_o <= 1'b0;
            end

            // ---------------- COMMIT WRITE ----------------
            if (aw_seen_q && w_seen_q && !axi_bvalid_o) begin
                axi_bvalid_o <= 1'b1;

                if (aw_addr_hit_w) begin
                    if (wstrb_q[0]) mem[aw_word_idx_w][7:0]   <= wdata_q[7:0];
                    if (wstrb_q[1]) mem[aw_word_idx_w][15:8]  <= wdata_q[15:8];
                    if (wstrb_q[2]) mem[aw_word_idx_w][23:16] <= wdata_q[23:16];
                    if (wstrb_q[3]) mem[aw_word_idx_w][31:24] <= wdata_q[31:24];
                    axi_bresp_o <= 2'b00; // OKAY
                end else begin
                    axi_bresp_o <= 2'b10; // SLVERR
                end

                aw_seen_q <= 1'b0;
                w_seen_q  <= 1'b0;
            end else if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o  <= 1'b0;
                axi_awready_o <= 1'b1;
                axi_wready_o  <= 1'b1;
            end

            // ---------------- READ LOGIC ----------------
            if (axi_arready_o && axi_arvalid_i && !axi_rvalid_o) begin
                axi_arready_o <= 1'b0;
                axi_rvalid_o  <= 1'b1;
                axi_rlast_o   <= 1'b1;

                if (ar_addr_hit_w) begin
                    axi_rdata_o <= mem[ar_word_idx_w];
                    axi_rresp_o <= 2'b00; // OKAY
                end else begin
                    axi_rdata_o <= 32'hDEADBEEF;
                    axi_rresp_o <= 2'b10; // SLVERR
                end
            end else if (axi_rvalid_o && axi_rready_i) begin
                axi_rvalid_o  <= 1'b0;
                axi_rlast_o   <= 1'b0;
                axi_arready_o <= 1'b1;
            end
        end
    end
endmodule

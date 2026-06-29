module sha3_real_wrapper #(
    parameter FIFO_DEPTH = 8
) (
    input  wire         clk_i,
    input  wire         rst_i,
    input  wire         init_i,
    input  wire         start_i,
    input  wire         data_valid_i,
    input  wire [31:0]  data_i,
    input  wire         data_is_last_i,
    input  wire [1:0]   data_byte_num_i,
    output wire         input_ready_o,
    output wire         overflow_o,
    output reg          busy_o,
    output reg          done_o,
    output wire [511:0] digest_o
);

    localparam ST_IDLE = 2'd0;
    localparam ST_RUN  = 2'd1;
    localparam ST_WAIT = 2'd2;

    function integer clog2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clog2 = i;
        end
    endfunction

    localparam PTR_W = (FIFO_DEPTH <= 2) ? 1 : clog2(FIFO_DEPTH);

    reg [1:0] state_q;

    reg [31:0] fifo_data     [0:FIFO_DEPTH-1];
    reg        fifo_is_last  [0:FIFO_DEPTH-1];
    reg [1:0]  fifo_byte_num [0:FIFO_DEPTH-1];

    reg [PTR_W-1:0] wr_ptr_q;
    reg [PTR_W-1:0] rd_ptr_q;
    reg [PTR_W:0]   fifo_count_q;

    reg saw_last_q;
    reg overflow_q;

    wire fifo_empty_w = (fifo_count_q == 0);
    wire fifo_full_w  = (fifo_count_q == FIFO_DEPTH);

    wire [31:0] head_data_w     = fifo_data[rd_ptr_q];
    wire        head_is_last_w  = fifo_is_last[rd_ptr_q];
    wire [1:0]  head_byte_num_w = fifo_byte_num[rd_ptr_q];

    wire         core_buffer_full_w;
    wire [511:0] core_out_w;
    wire         core_out_ready_w;

    assign input_ready_o = !fifo_full_w && !saw_last_q && (state_q != ST_WAIT);
    assign overflow_o    = overflow_q;

    wire pop_w  = (state_q == ST_RUN) && !fifo_empty_w && !core_buffer_full_w;
    wire push_w = data_valid_i && input_ready_o;

    keccak u_keccak (
        .clk        (clk_i),
        .reset      (rst_i | init_i),
        .in         (head_data_w),
        .in_ready   (pop_w),
        .is_last    (pop_w && head_is_last_w),
        .byte_num   (head_byte_num_w),
        .buffer_full(core_buffer_full_w),
        .out        (core_out_w),
        .out_ready  (core_out_ready_w)
    );

    assign digest_o = core_out_w;

    always @(posedge clk_i) begin
        if (rst_i || init_i) begin
            state_q       <= ST_IDLE;
            wr_ptr_q      <= {PTR_W{1'b0}};
            rd_ptr_q      <= {PTR_W{1'b0}};
            fifo_count_q  <= {(PTR_W+1){1'b0}};
            saw_last_q    <= 1'b0;
            overflow_q    <= 1'b0;
            busy_o        <= 1'b0;
            done_o        <= 1'b0;
        end else begin
            if (start_i && (state_q == ST_IDLE))
                done_o <= 1'b0;

            if (data_valid_i && !input_ready_o)
                overflow_q <= 1'b1;

            if (push_w) begin
                fifo_data[wr_ptr_q]     <= data_i;
                fifo_is_last[wr_ptr_q]  <= data_is_last_i;
                fifo_byte_num[wr_ptr_q] <= data_is_last_i ? data_byte_num_i : 2'b00;

                if (wr_ptr_q == FIFO_DEPTH-1)
                    wr_ptr_q <= {PTR_W{1'b0}};
                else
                    wr_ptr_q <= wr_ptr_q + 1'b1;

                if (data_is_last_i)
                    saw_last_q <= 1'b1;

                if (state_q == ST_IDLE) begin
                    state_q <= ST_RUN;
                    busy_o  <= 1'b1;
                    done_o  <= 1'b0;
                end
            end

            if (pop_w) begin
                if (rd_ptr_q == FIFO_DEPTH-1)
                    rd_ptr_q <= {PTR_W{1'b0}};
                else
                    rd_ptr_q <= rd_ptr_q + 1'b1;

                if (head_is_last_w)
                    state_q <= ST_WAIT;
            end

            case ({push_w, pop_w})
                2'b10: fifo_count_q <= fifo_count_q + 1'b1;
                2'b01: fifo_count_q <= fifo_count_q - 1'b1;
                default: fifo_count_q <= fifo_count_q;
            endcase

            if ((state_q == ST_WAIT) && core_out_ready_w) begin
                state_q      <= ST_IDLE;
                wr_ptr_q     <= {PTR_W{1'b0}};
                rd_ptr_q     <= {PTR_W{1'b0}};
                fifo_count_q <= {(PTR_W+1){1'b0}};
                saw_last_q   <= 1'b0;
                overflow_q   <= 1'b0;
                busy_o       <= 1'b0;
                done_o       <= 1'b1;
            end
        end
    end
endmodule

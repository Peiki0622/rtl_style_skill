// =============================================================================
// 测试平台：tb_gnrl_cdc
// 目的：自检跨时钟域原语gnrl_cdc_tx＋gnrl_cdc_rx配对以及gnrl_async_fifo。
// 方法：每个被测配置由tb_cdc_harness独立驱动，写侧与读侧使用不同周期的时钟，
//       覆盖快写慢读、慢写快读和近似同频；检查数据顺序、输出无X、反压保持、
//       在途条目数不超过容量，并在排空阶段确认全部数据送达。
// =============================================================================
`timescale 1ns/1ps

module tb_cdc_harness #(
    parameter int  KIND     = 1,     // 被测模块选择：0为gnrl_cdc_tx＋gnrl_cdc_rx，1为gnrl_async_fifo。
    parameter int  DP       = 8,     // gnrl_async_fifo深度；KIND=0时不使用。
    parameter int  SYNC_DP  = 2,     // 透传同步级数。
    parameter int  DW       = 16,    // 测试数据位宽。
    parameter real WPERIOD  = 10.0,  // 写侧时钟周期，单位ns。
    parameter real RPERIOD  = 10.0,  // 读侧时钟周期，单位ns。
    parameter int  NUM_TXN  = 1500   // 发送的数据笔数。
) (
    // 复位：两侧同时有效、同时释放，低有效。
    input  wire   rst_n,

    // 测试状态：done为1表示全部数据已送达；err_cnt为本实例累计错误数。
    output logic  done,
    output int    err_cnt
);

    localparam int CAP = (KIND == 0) ? 2 : DP;  // 在途容量：CDC配对为发送寄存器加接收缓冲两条，异步FIFO为DP条。

    logic           wclk = 1'b0;  // 写侧时钟。
    logic           rclk = 1'b0;  // 读侧时钟。
    logic           i_vld;        // 写侧源端有效。
    logic           i_rdy;        // 被测模块写侧就绪。
    logic [DW-1:0]  i_dat;        // 写侧源端数据。
    logic           o_vld;        // 被测模块读侧有效。
    logic           o_rdy;        // 读侧宿端就绪。
    logic [DW-1:0]  o_dat;        // 被测模块读侧数据。

    always #(WPERIOD / 2.0) wclk = ~wclk;
    always #(RPERIOD / 2.0) rclk = ~rclk;

    if (KIND == 0) begin : g_dut_cdc_pair
        logic           x_vld;  // 发送端到接收端的四相有效。
        logic           x_rdy;  // 接收端到发送端的四相应答。
        logic [DW-1:0]  x_dat;  // 发送端到接收端的跨域数据。

        gnrl_cdc_tx #(
            .DW      (DW),       // 测试数据位宽。
            .SYNC_DP (SYNC_DP)   // 透传同步级数。
        ) u_cdc_tx (
            // 本域输入通道：写侧。
            .i_vld   (i_vld),
            .i_rdy   (i_rdy),
            .i_dat   (i_dat),

            // 跨域四相握手输出。
            .o_vld   (x_vld),
            .o_rdy_a (x_rdy),
            .o_dat   (x_dat),

            // 时钟／复位：写侧。
            .clk     (wclk),
            .rst_n   (rst_n)
        );

        gnrl_cdc_rx #(
            .DW      (DW),       // 测试数据位宽。
            .SYNC_DP (SYNC_DP)   // 透传同步级数。
        ) u_cdc_rx (
            // 跨域四相握手输入。
            .i_vld_a (x_vld),
            .i_rdy   (x_rdy),
            .i_dat   (x_dat),

            // 本域输出通道：读侧。
            .o_vld   (o_vld),
            .o_rdy   (o_rdy),
            .o_dat   (o_dat),

            // 时钟／复位：读侧。
            .clk     (rclk),
            .rst_n   (rst_n)
        );
    end else begin : g_dut_async_fifo
        gnrl_async_fifo #(
            .DP      (DP),       // 透传测试深度。
            .DW      (DW),       // 测试数据位宽。
            .SYNC_DP (SYNC_DP)   // 透传同步级数。
        ) u_async_fifo (
            // 写时钟域。
            .wclk   (wclk),
            .wrst_n (rst_n),

            // 写入通道。
            .i_vld  (i_vld),
            .i_rdy  (i_rdy),
            .i_dat  (i_dat),

            // 读时钟域。
            .rclk   (rclk),
            .rrst_n (rst_n),

            // 读出通道。
            .o_vld  (o_vld),
            .o_rdy  (o_rdy),
            .o_dat  (o_dat)
        );
    end

    logic [DW-1:0] exp_q[$];   // 记分板：写侧已接收、读侧尚未输出的数据。
    int            sent;       // 写侧已接收笔数。
    int            recv;       // 读侧已输出笔数。
    int            vld_pct;    // 写侧有效概率，百分比。
    int            rdy_pct;    // 读侧就绪概率，百分比。
    bit            in_hs;      // 上一个写侧上升沿发生输入握手。
    bit            hold_chk;   // 上一读侧周期输出有效但被反压，本拍须保持。
    logic [DW-1:0] hold_dat;   // 被反压时的输出数据。

    // 写侧激励：下降沿驱动，有效保持到被接收；发送完NUM_TXN笔后撤销。
    always @(negedge wclk or negedge rst_n) begin
        if (!rst_n) begin
            i_vld   <= 1'b0;
            i_dat   <= '0;
            vld_pct <= 50;
        end else begin
            if ($urandom_range(0, 99) == 0) begin
                vld_pct <= 10 + 45 * $urandom_range(0, 2);
            end
            if ((!i_vld) || in_hs) begin
                if (sent < NUM_TXN) begin
                    i_vld <= ($urandom_range(0, 99) < vld_pct);
                    i_dat <= {$urandom, $urandom};
                end else begin
                    i_vld <= 1'b0;
                end
            end
        end
    end

    // 写侧采样：上升沿记录输入握手并入队。
    always @(posedge wclk or negedge rst_n) begin
        if (!rst_n) begin
            in_hs <= 1'b0;
            sent  <= 0;
        end else begin
            in_hs <= i_vld & i_rdy;
            if (i_vld && i_rdy) begin
                exp_q.push_back(i_dat);
                sent <= sent + 1;
            end
        end
    end

    // 读侧激励：下降沿随机就绪，全部发送完后持续就绪以排空。
    always @(negedge rclk or negedge rst_n) begin
        if (!rst_n) begin
            o_rdy   <= 1'b0;
            rdy_pct <= 50;
        end else begin
            if ($urandom_range(0, 99) == 0) begin
                rdy_pct <= 10 + 45 * $urandom_range(0, 2);
            end
            if (sent >= NUM_TXN) begin
                o_rdy <= 1'b1;
            end else begin
                o_rdy <= ($urandom_range(0, 99) < rdy_pct);
            end
        end
    end

    // 读侧检查：输出无X、反压保持、数据顺序、容量和排空完成。
    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) begin
            hold_chk <= 1'b0;
            recv     <= 0;
            done     <= 1'b0;
            err_cnt  <= 0;
        end else begin
            if (o_vld && $isunknown(o_dat)) begin
                $error("%m: o_dat has X while o_vld=1");
                err_cnt++;
            end
            if (hold_chk) begin
                if ((o_vld !== 1'b1) || (o_dat !== hold_dat)) begin
                    $error("%m: output not held under backpressure");
                    err_cnt++;
                end
            end
            hold_chk <= o_vld & (~o_rdy);
            hold_dat <= o_dat;
            if (o_vld && o_rdy) begin
                recv <= recv + 1;
                if (exp_q.size() == 0) begin
                    $error("%m: output handshake with empty scoreboard");
                    err_cnt++;
                end else if (o_dat !== exp_q[0]) begin
                    $error("%m: data mismatch got=%h exp=%h", o_dat, exp_q[0]);
                    err_cnt++;
                    void'(exp_q.pop_front());
                end else begin
                    void'(exp_q.pop_front());
                end
            end
            if (exp_q.size() > CAP) begin
                $error("%m: occupancy %0d exceeds capacity %0d", exp_q.size(), CAP);
                err_cnt++;
            end
            if ((recv == NUM_TXN) && (exp_q.size() == 0)) begin
                done <= 1'b1;
            end
        end
    end

endmodule

module tb_gnrl_cdc;

    localparam int NUM = 7;  // 被测配置个数，等于下方harness实例数。

    logic           rst_n;  // 全部配置共用复位，两侧同时有效。
    wire  [NUM-1:0] done;   // 各配置完成标志，由各harness输出驱动。
    int             err[NUM];  // 各配置错误数。

    // CDC配对：快写慢读。
    tb_cdc_harness #(
        .KIND    (0),     // gnrl_cdc_tx＋gnrl_cdc_rx。
        .SYNC_DP (2),     // 默认同步级数。
        .WPERIOD (3.7),   // 快写侧。
        .RPERIOD (13.0)   // 慢读侧。
    ) u_cdc_fast_to_slow (
        // 复位。
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[0]),
        .err_cnt (err[0])
    );

    // CDC配对：慢写快读，3级同步。
    tb_cdc_harness #(
        .KIND    (0),     // gnrl_cdc_tx＋gnrl_cdc_rx。
        .SYNC_DP (3),     // 3级同步。
        .WPERIOD (13.0),  // 慢写侧。
        .RPERIOD (3.7)    // 快读侧。
    ) u_cdc_slow_to_fast (
        // 复位。
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[1]),
        .err_cnt (err[1])
    );

    // CDC配对：近似同频。
    tb_cdc_harness #(
        .KIND    (0),     // gnrl_cdc_tx＋gnrl_cdc_rx。
        .SYNC_DP (2),     // 默认同步级数。
        .WPERIOD (10.0),  // 写侧。
        .RPERIOD (10.3)   // 读侧，相位缓慢滑动。
    ) u_cdc_near (
        // 复位。
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[2]),
        .err_cnt (err[2])
    );

    // 异步FIFO：最小深度2，快写慢读。
    tb_cdc_harness #(
        .KIND    (1),     // gnrl_async_fifo。
        .DP      (2),     // 最小合法深度。
        .SYNC_DP (2),     // 默认同步级数。
        .WPERIOD (3.7),   // 快写侧。
        .RPERIOD (13.0)   // 慢读侧。
    ) u_afifo_dp2 (
        // 复位。
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[3]),
        .err_cnt (err[3])
    );

    // 异步FIFO：深度8，慢写快读。
    tb_cdc_harness #(
        .KIND    (1),     // gnrl_async_fifo。
        .DP      (8),     // 默认深度。
        .SYNC_DP (2),     // 默认同步级数。
        .WPERIOD (13.0),  // 慢写侧。
        .RPERIOD (3.7)    // 快读侧。
    ) u_afifo_dp8_s2f (
        // 复位。
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[4]),
        .err_cnt (err[4])
    );

    // 异步FIFO：深度8，快写慢读，3级同步。
    tb_cdc_harness #(
        .KIND    (1),     // gnrl_async_fifo。
        .DP      (8),     // 默认深度。
        .SYNC_DP (3),     // 3级同步。
        .WPERIOD (3.7),   // 快写侧。
        .RPERIOD (13.0)   // 慢读侧。
    ) u_afifo_dp8_f2s (
        // 复位。
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[5]),
        .err_cnt (err[5])
    );

    // 异步FIFO：深度16，近似同频。
    tb_cdc_harness #(
        .KIND    (1),     // gnrl_async_fifo。
        .DP      (16),    // 较大深度，指针5位。
        .SYNC_DP (2),     // 默认同步级数。
        .WPERIOD (10.0),  // 写侧。
        .RPERIOD (10.3)   // 读侧。
    ) u_afifo_dp16_near (
        // 复位。
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[6]),
        .err_cnt (err[6])
    );

    initial begin : MAIN_PROC
        int total;
        rst_n = 1'b0;
        #57;
        rst_n = 1'b1;
        fork
            begin
                wait (&done);
            end
            begin
                #5_000_000;
                $error("timeout, done=%b", done);
            end
        join_any
        disable fork;
        total = 0;
        for (int k = 0; k < NUM; k++) begin
            total += err[k];
        end
        if ((&done) && (total == 0)) begin
            $display("TB_RESULT: PASS tb_gnrl_cdc");
        end else begin
            $display("TB_RESULT: FAIL tb_gnrl_cdc errors=%0d done=%b", total, done);
        end
        $finish;
    end

endmodule

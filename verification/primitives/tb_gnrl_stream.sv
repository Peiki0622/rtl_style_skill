// =============================================================================
// 测试平台：tb_gnrl_stream
// 目的：自检同时钟域的valid/ready流式原语gnrl_pipe_stage、gnrl_fifo和gnrl_bypbuf。
// 方法：每个被测配置由tb_stream_harness独立驱动，统一检查：
//   - 数据顺序与内容（记分板）；o_vld为1时o_dat没有X；MSKO=1时o_vld为0的o_dat为0；
//   - 反压期间o_vld保持且o_dat不变；在途条目数不超过容量；
//   - 满速阶段吞吐率：不切断反压的配置每拍一笔，切断反压的单条目配置每两拍一笔。
// =============================================================================
`timescale 1ns/1ps

module tb_stream_harness #(
    parameter int KIND      = 1,     // 被测模块选择：0为gnrl_pipe_stage，1为gnrl_fifo，2为gnrl_bypbuf。
    parameter int DP        = 4,     // 透传给被测模块的深度参数。
    parameter int CUT_READY = 0,     // 透传给被测模块的反压切断开关，gnrl_bypbuf忽略。
    parameter int MSKO      = 0,     // 透传给gnrl_fifo的输出屏蔽开关，1时额外检查空时o_dat为0。
    parameter int DW        = 16,    // 测试数据位宽。
    parameter int RAND_CYC  = 4000,  // 随机握手阶段周期数。
    parameter int TPUT_CYC  = 200,   // 满速吞吐率测量周期数。
    parameter int EXP_FULL  = 1      // 满速阶段期望：1为每拍一笔，0为每两拍一笔。
) (
    // 时钟／复位：由顶层提供，复位低有效。
    input  wire   clk,
    input  wire   rst_n,

    // 测试状态：done为1表示排空完成；err_cnt为本实例累计错误数。
    output logic  done,
    output int    err_cnt
);

    localparam int CAP = DP;  // 在途条目容量：各被测模块内部寄存条目数均不超过DP。

    logic           i_vld;  // 源端有效。
    logic           i_rdy;  // 被测模块输入就绪。
    logic [DW-1:0]  i_dat;  // 源端数据。
    logic           o_vld;  // 被测模块输出有效。
    logic           o_rdy;  // 宿端就绪。
    logic [DW-1:0]  o_dat;  // 被测模块输出数据。

    if (KIND == 0) begin : g_dut_pipe_stage
        gnrl_pipe_stage #(
            .CUT_READY (CUT_READY),  // 透传测试配置。
            .DP        (DP),         // 透传测试配置，只取0或1。
            .DW        (DW)          // 测试数据位宽。
        ) u_dut (
            // 输入通道。
            .i_vld (i_vld),
            .i_rdy (i_rdy),
            .i_dat (i_dat),

            // 输出通道。
            .o_vld (o_vld),
            .o_rdy (o_rdy),
            .o_dat (o_dat),

            // 时钟／复位。
            .clk   (clk),
            .rst_n (rst_n)
        );
    end else if (KIND == 1) begin : g_dut_fifo
        gnrl_fifo #(
            .CUT_READY (CUT_READY),  // 透传测试配置。
            .MSKO      (MSKO),       // 透传测试配置。
            .DP        (DP),         // 透传测试深度。
            .DW        (DW)          // 测试数据位宽。
        ) u_dut (
            // 写入通道。
            .i_vld (i_vld),
            .i_rdy (i_rdy),
            .i_dat (i_dat),

            // 读出通道。
            .o_vld (o_vld),
            .o_rdy (o_rdy),
            .o_dat (o_dat),

            // 时钟／复位。
            .clk   (clk),
            .rst_n (rst_n)
        );
    end else begin : g_dut_bypbuf
        gnrl_bypbuf #(
            .DP (DP),  // 透传测试深度。
            .DW (DW)   // 测试数据位宽。
        ) u_dut (
            // 输入通道。
            .i_vld (i_vld),
            .i_rdy (i_rdy),
            .i_dat (i_dat),

            // 输出通道。
            .o_vld (o_vld),
            .o_rdy (o_rdy),
            .o_dat (o_dat),

            // 时钟／复位。
            .clk   (clk),
            .rst_n (rst_n)
        );
    end

    logic [DW-1:0] exp_q[$];   // 记分板：已被接收、尚未输出的数据。
    int            cyc;        // 复位释放后的周期计数，决定测试阶段。
    int            vld_pct;    // 当前源端有效概率，百分比。
    int            rdy_pct;    // 当前宿端就绪概率，百分比。
    bit            in_hs;      // 上一个上升沿发生输入握手。
    bit            hold_chk;   // 上一拍输出有效但被反压，本拍须保持。
    logic [DW-1:0] hold_dat;   // 被反压时的输出数据。
    int            tput_cnt;   // 满速阶段输入握手计数。

    // 激励：下降沿驱动；有效一旦拉高须保持到被接收，数据同时保持。
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_vld   <= 1'b0;
            i_dat   <= '0;
            o_rdy   <= 1'b0;
            cyc     <= 0;
            vld_pct <= 50;
            rdy_pct <= 50;
        end else begin
            cyc <= cyc + 1;
            if ((cyc % 100) == 0) begin
                vld_pct <= 10 + 40 * $urandom_range(0, 2);
                rdy_pct <= 10 + 40 * $urandom_range(0, 2);
            end
            if (cyc < RAND_CYC) begin
                // 随机阶段：按概率产生有效和就绪。
                if ((!i_vld) || in_hs) begin
                    i_vld <= ($urandom_range(0, 99) < vld_pct);
                    i_dat <= {$urandom, $urandom, $urandom};
                end
                o_rdy <= ($urandom_range(0, 99) < rdy_pct);
            end else if (cyc < RAND_CYC + TPUT_CYC) begin
                // 满速阶段：源端持续有效、宿端持续就绪。
                if ((!i_vld) || in_hs) begin
                    i_vld <= 1'b1;
                    i_dat <= {$urandom, $urandom, $urandom};
                end
                o_rdy <= 1'b1;
            end else begin
                // 排空阶段：已经发出的有效保持到被接收后撤销，宿端持续就绪。
                if (in_hs) begin
                    i_vld <= 1'b0;
                end
                o_rdy <= 1'b1;
            end
        end
    end

    // 检查：上升沿采样握手，先入队再出队，以覆盖直通和旁路的同拍出入。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_hs    <= 1'b0;
            hold_chk <= 1'b0;
            tput_cnt <= 0;
            done     <= 1'b0;
            err_cnt  <= 0;
        end else begin
            in_hs <= i_vld & i_rdy;
            if (o_vld && $isunknown(o_dat)) begin
                $error("%m: o_dat has X while o_vld=1");
                err_cnt++;
            end
            if ((MSKO == 1) && (!o_vld) && (o_dat !== '0)) begin
                $error("%m: MSKO=1 but o_dat=%h while o_vld=0", o_dat);
                err_cnt++;
            end
            if (hold_chk) begin
                if ((o_vld !== 1'b1) || (o_dat !== hold_dat)) begin
                    $error("%m: output not held under backpressure vld=%b dat=%h exp=%h",
                           o_vld, o_dat, hold_dat);
                    err_cnt++;
                end
            end
            hold_chk <= o_vld & (~o_rdy);
            hold_dat <= o_dat;
            if (i_vld && i_rdy) begin
                exp_q.push_back(i_dat);
                if ((cyc > RAND_CYC) && (cyc <= RAND_CYC + TPUT_CYC)) begin
                    tput_cnt <= tput_cnt + 1;
                end
            end
            if (o_vld && o_rdy) begin
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
            if ((cyc > RAND_CYC + TPUT_CYC + 20) && (exp_q.size() == 0) && (!i_vld) && (!done)) begin
                // 吞吐率：允许测量窗口两端各一拍误差。
                if (EXP_FULL == 1) begin
                    if (tput_cnt < TPUT_CYC - 2) begin
                        $error("%m: throughput %0d/%0d, expected full rate", tput_cnt, TPUT_CYC);
                        err_cnt++;
                    end
                end else begin
                    if ((tput_cnt < TPUT_CYC / 2 - 2) || (tput_cnt > TPUT_CYC / 2 + 2)) begin
                        $error("%m: throughput %0d/%0d, expected half rate", tput_cnt, TPUT_CYC);
                        err_cnt++;
                    end
                end
                done <= 1'b1;
            end
        end
    end

endmodule

module tb_gnrl_stream;

    localparam int NUM = 12;  // 被测配置个数，等于下方harness实例数。

    logic       clk = 1'b0;  // 10ns测试时钟。
    logic       rst_n;       // 低有效复位。
    wire  [NUM-1:0] done;    // 各配置排空完成标志，由各harness输出驱动。
    int         err[NUM];    // 各配置错误数。

    always #5 clk = ~clk;

    // 被测配置：gnrl_pipe_stage直通。
    tb_stream_harness #(
        .KIND      (0),  // gnrl_pipe_stage。
        .DP        (0),  // 直通配置。
        .CUT_READY (0),  // 直通不使用。
        .EXP_FULL  (1)   // 直通满速。
    ) u_pipe_dp0 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[0]),
        .err_cnt (err[0])
    );

    // 被测配置：gnrl_pipe_stage一级、不切断反压。
    tb_stream_harness #(
        .KIND      (0),  // gnrl_pipe_stage。
        .DP        (1),  // 一级寄存器。
        .CUT_READY (0),  // 不切断反压，期望满速。
        .EXP_FULL  (1)   // 满速。
    ) u_pipe_dp1_nocut (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[1]),
        .err_cnt (err[1])
    );

    // 被测配置：gnrl_pipe_stage一级、切断反压。
    tb_stream_harness #(
        .KIND      (0),  // gnrl_pipe_stage。
        .DP        (1),  // 一级寄存器。
        .CUT_READY (1),  // 切断反压，期望半速。
        .EXP_FULL  (0)   // 每两拍一笔。
    ) u_pipe_dp1_cut (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[2]),
        .err_cnt (err[2])
    );

    // 被测配置：gnrl_fifo直通。
    tb_stream_harness #(
        .KIND      (1),  // gnrl_fifo。
        .DP        (0),  // 深度0直通。
        .CUT_READY (0),  // 直通不使用。
        .EXP_FULL  (1)   // 直通满速。
    ) u_fifo_dp0 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[3]),
        .err_cnt (err[3])
    );

    // 被测配置：gnrl_fifo单条目、不切断反压。
    tb_stream_harness #(
        .KIND      (1),  // gnrl_fifo。
        .DP        (1),  // 单条目。
        .CUT_READY (0),  // 不切断反压，期望满速。
        .EXP_FULL  (1)   // 满速。
    ) u_fifo_dp1_nocut (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[4]),
        .err_cnt (err[4])
    );

    // 被测配置：gnrl_fifo单条目、切断反压。
    tb_stream_harness #(
        .KIND      (1),  // gnrl_fifo。
        .DP        (1),  // 单条目。
        .CUT_READY (1),  // 切断反压，期望半速。
        .EXP_FULL  (0)   // 每两拍一笔。
    ) u_fifo_dp1_cut (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[5]),
        .err_cnt (err[5])
    );

    // 被测配置：gnrl_fifo两条目。
    tb_stream_harness #(
        .KIND      (1),  // gnrl_fifo。
        .DP        (2),  // 最小多条目深度。
        .CUT_READY (0),  // 多条目时不起作用。
        .EXP_FULL  (1)   // 满速。
    ) u_fifo_dp2 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[6]),
        .err_cnt (err[6])
    );

    // 被测配置：gnrl_fifo五条目、输出屏蔽，覆盖非2的幂深度。
    tb_stream_harness #(
        .KIND      (1),  // gnrl_fifo。
        .DP        (5),  // 非2的幂深度。
        .CUT_READY (1),  // 多条目时不起作用，检查不影响满速。
        .MSKO      (1),  // 打开输出屏蔽并检查。
        .EXP_FULL  (1)   // 满速。
    ) u_fifo_dp5_msko (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[7]),
        .err_cnt (err[7])
    );

    // 被测配置：gnrl_fifo八条目。
    tb_stream_harness #(
        .KIND      (1),  // gnrl_fifo。
        .DP        (8),  // 默认深度。
        .CUT_READY (0),  // 多条目时不起作用。
        .EXP_FULL  (1)   // 满速。
    ) u_fifo_dp8 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[8]),
        .err_cnt (err[8])
    );

    // 被测配置：gnrl_bypbuf单条目。
    tb_stream_harness #(
        .KIND      (2),  // gnrl_bypbuf。
        .DP        (1),  // 单条目内部FIFO。
        .EXP_FULL  (1)   // 宿端持续就绪时全部旁路，满速。
    ) u_bypbuf_dp1 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[9]),
        .err_cnt (err[9])
    );

    // 被测配置：gnrl_bypbuf四条目。
    tb_stream_harness #(
        .KIND      (2),  // gnrl_bypbuf。
        .DP        (4),  // 四条目内部FIFO。
        .EXP_FULL  (1)   // 满速。
    ) u_bypbuf_dp4 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[10]),
        .err_cnt (err[10])
    );

    // 被测配置：gnrl_fifo三条目，较宽数据。
    tb_stream_harness #(
        .KIND      (1),   // gnrl_fifo。
        .DP        (3),   // 奇数深度。
        .DW        (40),  // 超过32bit，检查宽数据通路。
        .EXP_FULL  (1)    // 满速。
    ) u_fifo_dp3_w40 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .done    (done[11]),
        .err_cnt (err[11])
    );

    initial begin : MAIN_PROC
        int total;
        rst_n = 1'b0;
        #23;
        rst_n = 1'b1;
        fork
            begin
                wait (&done);
            end
            begin
                #2_000_000;
                $error("timeout, done=%b", done);
            end
        join_any
        disable fork;
        total = 0;
        for (int k = 0; k < NUM; k++) begin
            total += err[k];
        end
        if ((&done) && (total == 0)) begin
            $display("TB_RESULT: PASS tb_gnrl_stream");
        end else begin
            $display("TB_RESULT: FAIL tb_gnrl_stream errors=%0d done=%b", total, done);
        end
        $finish;
    end

endmodule

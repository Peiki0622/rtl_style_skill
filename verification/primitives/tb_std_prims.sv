// =============================================================================
// 测试平台：tb_std_prims
// 目的：自检std_单元级原语。
//   - 寄存器族：dff／dffr／dffrs／dffl／dfflr／dfflrs与参考模型逐拍比较，含中途异步复位；
//   - std_ltch：透明与保持；std_clkgate：高电平期间改变使能不产生毛刺、脉冲个数正确；
//   - std_clk_mux2：选择正确；std_sync：延迟DP拍与复位值；std_rst_sync：异步置位、同步释放
//     与测试旁路；std_pulse_sync：快到慢、慢到快两种时钟比下脉冲个数守恒。
// 负向测试：定义TB_XCHECK_NEG时向加载使能注入X，预期std_xchecker终止仿真；
//           定义TB_LTCH_Z_NEG时把锁存器透明控制置为Z，预期std_ltch的检查终止仿真。
// =============================================================================
`timescale 1ns/1ps

module tb_std_prims;

    localparam int            DW        = 8;      // 寄存器原语测试位宽，取8bit覆盖多位复位值。
    localparam logic [DW-1:0] DFFR_RST  = 8'hA5;  // std_dffr复位值对照，非全0／全1，用于检查逐位复位。
    localparam logic [DW-1:0] DFFLR_RST = 8'h3C;  // std_dfflr复位值对照，非全0／全1，用于检查逐位复位。
    localparam int            CYCLES    = 3000;   // 寄存器族随机测试周期数。
    localparam int            SYNC_DP   = 3;      // std_sync测试级数，取3以区别默认值。
    localparam logic [1:0]    SYNC_RST  = 2'b10;  // std_sync复位值对照，检查RST_VAL逐位传递。
    localparam int            PULSE_NUM = 300;    // 每个脉冲同步实例发送的源脉冲个数。

    int err_cnt = 0;  // 全部检查的累计错误数，结束时为0才算通过。

    // -------------------------------------------------------------------------
    // 时钟：clk为10ns主时钟；clk_slow为13ns慢时钟；clk_fast为3ns快时钟。
    // -------------------------------------------------------------------------
    logic clk      = 1'b0;
    logic clk_slow = 1'b0;
    logic clk_fast = 1'b0;

    always #5 clk = ~clk;
    always #6.5 clk_slow = ~clk_slow;
    always #1.5 clk_fast = ~clk_fast;

    // -------------------------------------------------------------------------
    // 寄存器族：共用激励，各自与参考模型比较
    // -------------------------------------------------------------------------
    logic          rst_n;        // 寄存器族共用低有效异步复位。
    logic          lden;         // 带加载使能原语的共用加载使能。
    logic [DW-1:0] dnxt;         // 寄存器族共用下一值。
    logic [DW-1:0] q_dff;        // std_dff输出。
    logic [DW-1:0] q_dffr;       // std_dffr输出。
    logic [DW-1:0] q_dffrs;      // std_dffrs输出。
    logic [DW-1:0] q_dffl;       // std_dffl输出。
    logic [DW-1:0] q_dfflr;      // std_dfflr输出。
    logic [DW-1:0] q_dfflrs;     // std_dfflrs输出。
    logic [DW-1:0] m_dff;        // std_dff参考模型。
    logic [DW-1:0] m_dffr;       // std_dffr参考模型。
    logic [DW-1:0] m_dffrs;      // std_dffrs参考模型。
    logic [DW-1:0] m_dffl;       // std_dffl参考模型。
    logic [DW-1:0] m_dfflr;      // std_dfflr参考模型。
    logic [DW-1:0] m_dfflrs;     // std_dfflrs参考模型。
    bit            dff_loaded;   // std_dff已经至少采样一次，之后输出才有确定值。
    bit            dffl_loaded;  // std_dffl已经至少装入一次，之后输出才有确定值。

    // 被测寄存器：单行位置连接，端口顺序为原语约定的固定顺序。
    std_dff    #(.DW(DW))                         u_dff    (dnxt, q_dff, clk);
    std_dffr   #(.DW(DW), .RST_VAL(DFFR_RST))     u_dffr   (dnxt, q_dffr, clk, rst_n);
    std_dffrs  #(.DW(DW))                         u_dffrs  (dnxt, q_dffrs, clk, rst_n);
    std_dffl   #(.DW(DW))                         u_dffl   (lden, dnxt, q_dffl, clk);
    std_dfflr  #(.DW(DW), .RST_VAL(DFFLR_RST))    u_dfflr  (lden, dnxt, q_dfflr, clk, rst_n);
    std_dfflrs #(.DW(DW))                         u_dfflrs (lden, dnxt, q_dfflrs, clk, rst_n);

    // 参考模型（带复位）：复位优先，复位释放后按是否带加载使能更新。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_dffr   <= DFFR_RST;
            m_dffrs  <= {DW{1'b1}};
            m_dfflr  <= DFFLR_RST;
            m_dfflrs <= {DW{1'b1}};
        end else begin
            m_dffr  <= dnxt;
            m_dffrs <= dnxt;
            if (lden) begin
                m_dfflr  <= dnxt;
                m_dfflrs <= dnxt;
            end
        end
    end

    // 参考模型（无复位）：记录是否已经装入过确定值。
    always @(posedge clk) begin
        m_dff      <= dnxt;
        dff_loaded <= 1'b1;
        if (lden) begin
            m_dffl      <= dnxt;
            dffl_loaded <= 1'b1;
        end
    end

    // 寄存器族比较：在下降沿进行，此时含#1仿真延时的输出也已稳定。
    task automatic check_regs(input string tag);
        if (q_dffr !== m_dffr) begin
            $error("[%s] std_dffr mismatch q=%h exp=%h", tag, q_dffr, m_dffr);
            err_cnt++;
        end
        if (q_dffrs !== m_dffrs) begin
            $error("[%s] std_dffrs mismatch q=%h exp=%h", tag, q_dffrs, m_dffrs);
            err_cnt++;
        end
        if (q_dfflr !== m_dfflr) begin
            $error("[%s] std_dfflr mismatch q=%h exp=%h", tag, q_dfflr, m_dfflr);
            err_cnt++;
        end
        if (q_dfflrs !== m_dfflrs) begin
            $error("[%s] std_dfflrs mismatch q=%h exp=%h", tag, q_dfflrs, m_dfflrs);
            err_cnt++;
        end
        if (dff_loaded && (q_dff !== m_dff)) begin
            $error("[%s] std_dff mismatch q=%h exp=%h", tag, q_dff, m_dff);
            err_cnt++;
        end
        if (dffl_loaded && (q_dffl !== m_dffl)) begin
            $error("[%s] std_dffl mismatch q=%h exp=%h", tag, q_dffl, m_dffl);
            err_cnt++;
        end
    endtask

    // 寄存器族激励：下降沿检查后驱动新值；周期性在低电平期间插入异步复位脉冲。
    initial begin : REG_STIM_PROC
        rst_n       = 1'b0;
        lden        = 1'b0;
        dnxt        = '0;
        dff_loaded  = 1'b0;
        dffl_loaded = 1'b0;
        repeat (3) begin
            @(negedge clk);
        end
        check_regs("reset");
        rst_n = 1'b1;
        for (int c = 0; c < CYCLES; c++) begin
            @(negedge clk);
            check_regs("run");
            dnxt = $urandom;
            lden = $urandom_range(0, 1);
            if ((c % 397) == 200) begin
                // 异步复位：低电平期间拉低，检查立即生效，再在下一个上升沿前释放。
                #1;
                rst_n = 1'b0;
                #0.5;
                check_regs("async_reset");
                #1;
                rst_n = 1'b1;
            end
`ifdef TB_XCHECK_NEG
            if (c == 100) begin
                // 负向测试：加载使能为X，预期std_xchecker在下一个上升沿终止仿真。
                lden = 1'bx;
            end
`endif
        end
    end

    // -------------------------------------------------------------------------
    // std_ltch：透明期间跟随，锁存期间保持
    // -------------------------------------------------------------------------
    logic          l_en;  // 锁存器透明控制。
    logic [DW-1:0] l_d;   // 锁存器数据输入。
    logic [DW-1:0] l_q;   // 锁存器输出。

    std_ltch #(.DW(DW)) u_ltch (l_en, l_d, l_q);

    initial begin : LTCH_STIM_PROC
        logic [DW-1:0] held;
        l_en = 1'b0;
        l_d  = '0;
        #3;
        for (int k = 0; k < 200; k++) begin
            // 透明：打开后输出跟随输入的每次变化。
            l_en = 1'b1;
            l_d  = $urandom;
            #1;
            if (l_q !== l_d) begin
                $error("std_ltch transparent mismatch q=%h d=%h", l_q, l_d);
                err_cnt++;
            end
            held = $urandom;
            l_d  = held;
            #1;
            l_en = 1'b0;
            #1;
            // 锁存：关闭后改变输入，输出保持关闭前的值。
            l_d = ~held;
`ifdef TB_LTCH_Z_NEG
            if (k == 50) begin
                // 负向测试：透明控制悬空为Z，预期std_ltch的X/Z检查终止仿真。
                l_en = 1'bz;
            end
`endif
            #1;
            if (l_q !== held) begin
                $error("std_ltch hold mismatch q=%h exp=%h", l_q, held);
                err_cnt++;
            end
        end
    end

    // -------------------------------------------------------------------------
    // std_clkgate：使能在低电平锁存，高电平期间改变使能不影响输出
    // -------------------------------------------------------------------------
    logic cg_en;        // 门控功能使能。
    logic cg_test;      // 门控测试模式。
    logic cg_clk_out;   // 门控输出时钟。
    int   cg_exp_cnt;   // 预期通过的时钟脉冲数。
    int   cg_act_cnt;   // 实际观测到的输出上升沿数。

    std_clkgate u_clkgate (
        // 输入时钟：主时钟。
        .clk_in    (clk),

        // 测试控制：随机打开，检查强制开时钟。
        .test_mode (cg_test),

        // 门控使能：低电平期间设置，高电平期间故意翻转以检查无毛刺。
        .clock_en  (cg_en),

        // 输出时钟。
        .clk_out   (cg_clk_out)
    );

    always @(posedge cg_clk_out) begin
        cg_act_cnt++;
    end

    initial begin : CLKGATE_STIM_PROC
        logic exp_on;
        cg_en      = 1'b0;
        cg_test    = 1'b0;
        cg_exp_cnt = 0;
        cg_act_cnt = 0;
        for (int k = 0; k < 500; k++) begin
            @(negedge clk);
            #1;
            cg_en   = $urandom_range(0, 1);
            cg_test = ($urandom_range(0, 7) == 0);
            @(posedge clk);
            exp_on = cg_en | cg_test;
            if (exp_on) begin
                cg_exp_cnt++;
            end
            #1;
            if (cg_clk_out !== exp_on) begin
                $error("std_clkgate output=%b exp=%b at rising phase", cg_clk_out, exp_on);
                err_cnt++;
            end
            // 高电平期间翻转使能，输出必须保持到下降沿。
            cg_en   = ~cg_en;
            cg_test = 1'b0;
            #2;
            if (cg_clk_out !== exp_on) begin
                $error("std_clkgate glitch: output=%b exp=%b after enable toggle", cg_clk_out, exp_on);
                err_cnt++;
            end
        end
        #1;
        if (cg_act_cnt != cg_exp_cnt) begin
            $error("std_clkgate pulse count act=%0d exp=%0d", cg_act_cnt, cg_exp_cnt);
            err_cnt++;
        end
    end

    // -------------------------------------------------------------------------
    // std_clk_mux2：静态选择
    // -------------------------------------------------------------------------
    logic cm_sel;      // 时钟选择。
    logic cm_clk_out;  // 选择后的时钟。

    std_clk_mux2 u_clk_mux2 (
        // 候选时钟：clk0为主时钟，clk1为慢时钟。
        .clk0    (clk),
        .clk1    (clk_slow),

        // 选择控制。
        .sel     (cm_sel),

        // 输出时钟。
        .clk_out (cm_clk_out)
    );

    initial begin : CLK_MUX_STIM_PROC
        cm_sel = 1'b0;
        for (int k = 0; k < 400; k++) begin
            #0.7;
            if ((k % 50) == 0) begin
                cm_sel = ~cm_sel;
            end
            #0.1;
            if (cm_clk_out !== (cm_sel ? clk_slow : clk)) begin
                $error("std_clk_mux2 output mismatch sel=%b", cm_sel);
                err_cnt++;
            end
        end
    end

    // -------------------------------------------------------------------------
    // std_sync：同域激励下验证DP拍延迟和复位值
    // -------------------------------------------------------------------------
    logic       sy_rst_n;  // 同步器复位。
    logic [1:0] sy_din;    // 同步器输入，在下降沿驱动。
    logic [1:0] sy_dout;   // 同步器输出。
    logic [1:0] sy_hist[$];  // 输入历史，用于计算DP拍前的期望值。

    std_sync #(
        .DP      (SYNC_DP),   // 测试3级同步。
        .DW      (2),         // 测试多位同步时各位独立传递。
        .RST_VAL (SYNC_RST)   // 非全0复位值，检查逐级复位。
    ) u_sync (
        // 异步输入。
        .din_a (sy_din),

        // 同步输出。
        .dout  (sy_dout),

        // 时钟／复位：主时钟域。
        .clk   (clk),
        .rst_n (sy_rst_n)
    );

    initial begin : SYNC_STIM_PROC
        sy_rst_n = 1'b0;
        sy_din   = SYNC_RST;
        repeat (2) begin
            @(negedge clk);
        end
        if (sy_dout !== SYNC_RST) begin
            $error("std_sync reset value=%b exp=%b", sy_dout, SYNC_RST);
            err_cnt++;
        end
        sy_rst_n = 1'b1;
        for (int k = 0; k < SYNC_DP; k++) begin
            sy_hist.push_back(SYNC_RST);
        end
        for (int k = 0; k < 500; k++) begin
            @(negedge clk);
            if (sy_dout !== sy_hist[0]) begin
                $error("std_sync dout=%b exp=%b", sy_dout, sy_hist[0]);
                err_cnt++;
            end
            void'(sy_hist.pop_front());
            sy_din = $urandom;
            sy_hist.push_back(sy_din);
        end
    end

    // -------------------------------------------------------------------------
    // std_rst_sync：异步置位、同步释放、测试旁路
    // -------------------------------------------------------------------------
    logic rs_rst_n_a;   // 外部异步复位。
    logic rs_test;      // 测试模式。
    logic rs_rst_sync;  // 同步后复位。

    std_rst_sync #(
        .DP (2)  // 测试默认2级同步，释放后第2个上升沿输出为1。
    ) u_rst_sync (
        // 时钟：主时钟。
        .clk        (clk),

        // 复位输入。
        .rst_n_a    (rs_rst_n_a),

        // 测试控制。
        .test_mode  (rs_test),

        // 同步复位输出。
        .rst_n_sync (rs_rst_sync)
    );

    task automatic expect_rs(input logic exp, input string tag);
        if (rs_rst_sync !== exp) begin
            $error("std_rst_sync [%s] out=%b exp=%b", tag, rs_rst_sync, exp);
            err_cnt++;
        end
    endtask

    initial begin : RST_SYNC_STIM_PROC
        rs_rst_n_a = 1'b0;
        rs_test    = 1'b0;
        for (int k = 0; k < 50; k++) begin
            repeat (2) begin
                @(negedge clk);
            end
            expect_rs(1'b0, "asserted");
            // 释放：在低电平中间异步释放，之后第1个上升沿仍为0，第2个上升沿变1。
            #2;
            rs_rst_n_a = 1'b1;
            #0.1;
            expect_rs(1'b0, "release_same_phase");
            @(posedge clk);
            #1.5;
            expect_rs(1'b0, "after_1st_edge");
            @(posedge clk);
            #1.5;
            expect_rs(1'b1, "after_2nd_edge");
            repeat ($urandom_range(0, 3)) begin
                @(posedge clk);
            end
            // 置位：在高电平中间拉低，输出立即为0。
            #2;
            rs_rst_n_a = 1'b0;
            #0.1;
            expect_rs(1'b0, "async_assert");
        end
        // 测试旁路：test_mode为1时输出直接跟随外部复位。
        rs_test = 1'b1;
        for (int k = 0; k < 20; k++) begin
            #3.3;
            rs_rst_n_a = $urandom_range(0, 1);
            #0.1;
            expect_rs(rs_rst_n_a, "test_bypass");
        end
        rs_test = 1'b0;
    end

    // -------------------------------------------------------------------------
    // std_pulse_sync：快到慢、慢到快两个实例，比较脉冲个数
    // -------------------------------------------------------------------------
    logic ps_rst_n;       // 脉冲同步器两侧共用复位，同时有效。
    logic ps_src_pulse0;  // 实例0源脉冲（clk域）。
    logic ps_dst_pulse0;  // 实例0目标脉冲（clk_slow域）。
    logic ps_src_pulse1;  // 实例1源脉冲（clk域）。
    logic ps_dst_pulse1;  // 实例1目标脉冲（clk_fast域）。
    int   ps_dst_cnt0;    // 实例0目标脉冲计数。
    int   ps_dst_cnt1;    // 实例1目标脉冲计数。

    // 实例0：10ns源时钟到13ns目标时钟，源脉冲间隔保证不少于两个目标周期。
    std_pulse_sync #(
        .SYNC_DP (2)  // 默认2级同步。
    ) u_pulse_sync_slow (
        // 源域：主时钟。
        .src_clk   (clk),
        .src_rst_n (ps_rst_n),
        .src_pulse (ps_src_pulse0),

        // 目标域：慢时钟。
        .dst_clk   (clk_slow),
        .dst_rst_n (ps_rst_n),
        .dst_pulse (ps_dst_pulse0)
    );

    // 实例1：10ns源时钟到3ns目标时钟，源脉冲可以背靠背。
    std_pulse_sync #(
        .SYNC_DP (3)  // 测试3级同步。
    ) u_pulse_sync_fast (
        // 源域：主时钟。
        .src_clk   (clk),
        .src_rst_n (ps_rst_n),
        .src_pulse (ps_src_pulse1),

        // 目标域：快时钟。
        .dst_clk   (clk_fast),
        .dst_rst_n (ps_rst_n),
        .dst_pulse (ps_dst_pulse1)
    );

    always @(posedge clk_slow) begin
        if (ps_dst_pulse0 === 1'b1) begin
            ps_dst_cnt0++;
        end
    end

    always @(posedge clk_fast) begin
        if (ps_dst_pulse1 === 1'b1) begin
            ps_dst_cnt1++;
        end
    end

    initial begin : PULSE_STIM0_PROC
        ps_rst_n      = 1'b0;
        ps_src_pulse0 = 1'b0;
        ps_dst_cnt0   = 0;
        ps_dst_cnt1   = 0;
        #20;
        ps_rst_n = 1'b1;
        for (int k = 0; k < PULSE_NUM; k++) begin
            repeat ($urandom_range(3, 8)) begin
                @(negedge clk);
            end
            ps_src_pulse0 = 1'b1;
            @(negedge clk);
            ps_src_pulse0 = 1'b0;
        end
    end

    initial begin : PULSE_STIM1_PROC
        ps_src_pulse1 = 1'b0;
        #20;
        for (int k = 0; k < PULSE_NUM; k++) begin
            @(negedge clk);
            ps_src_pulse1 = 1'b1;
            repeat ($urandom_range(0, 2)) begin
                @(negedge clk);
            end
            ps_src_pulse1 = 1'b0;
            repeat ($urandom_range(0, 2)) begin
                @(negedge clk);
            end
        end
    end

    // 实例1允许连续多拍高电平：每个高电平上升沿都计为一次源事件，单独统计。
    int ps_src_cnt1 = 0;  // 实例1源事件计数。
    always @(posedge clk) begin
        if ((ps_rst_n === 1'b1) && (ps_src_pulse1 === 1'b1)) begin
            ps_src_cnt1++;
        end
    end

    // -------------------------------------------------------------------------
    // 结束判定
    // -------------------------------------------------------------------------
    initial begin : FINISH_PROC
        #((CYCLES + 100) * 10);
        if (ps_dst_cnt0 != PULSE_NUM) begin
            $error("std_pulse_sync slow dst count=%0d exp=%0d", ps_dst_cnt0, PULSE_NUM);
            err_cnt++;
        end
        if (ps_dst_cnt1 != ps_src_cnt1) begin
            $error("std_pulse_sync fast dst count=%0d exp=%0d", ps_dst_cnt1, ps_src_cnt1);
            err_cnt++;
        end
        if (err_cnt == 0) begin
            $display("TB_RESULT: PASS tb_std_prims");
        end else begin
            $display("TB_RESULT: FAIL tb_std_prims errors=%0d", err_cnt);
        end
        $finish;
    end

endmodule

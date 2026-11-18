// =============================================================================
// 测试平台：tb_gnrl_misc
// 目的：自检gnrl_rr_arb、gnrl_ram_sp和gnrl_ram_tp。
//   - gnrl_rr_arb：N=1／4／5／8，与“从上次授权者之后循环查找”的参考模型逐拍比较，
//     并检查授权独热、只授权给有请求者、未确认时优先级不轮转。
//   - gnrl_ram_sp／gnrl_ram_tp：与带写掩码的参考存储模型比较读数据，含读数据保持、
//     两端口同拍读写同一地址读出旧值。
// =============================================================================
`timescale 1ns/1ps

module tb_arb_harness #(
    parameter int N      = 4,     // 透传给被测仲裁器的请求路数。
    parameter int CYCLES = 4000   // 随机测试周期数。
) (
    // 时钟／复位：由顶层提供。
    input  wire   clk,
    input  wire   rst_n,

    // 测试状态：本实例累计错误数。
    output int    err_cnt
);

    logic [N-1:0] req;      // 随机请求。
    logic [N-1:0] gnt;      // 被测授权。
    logic         gnt_ack;  // 随机授权确认。
    int           last;     // 参考模型：上次被确认的授权者，复位为N-1，使第0路最先被查找。

    gnrl_rr_arb #(
        .N (N)  // 透传测试路数。
    ) u_dut (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 请求与授权。
        .req     (req),
        .gnt     (gnt),

        // 授权确认。
        .gnt_ack (gnt_ack)
    );

    // 激励：下降沿驱动随机请求和确认。
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req     <= '0;
            gnt_ack <= 1'b0;
        end else begin
            req     <= $urandom;
            gnt_ack <= ($urandom_range(0, 3) != 0);
        end
    end

    // 检查：上升沿按参考模型计算期望授权并比较，确认时更新模型。
    always @(posedge clk or negedge rst_n) begin
        logic [N-1:0] exp_gnt;
        int           exp_idx;
        if (!rst_n) begin
            last    <= N - 1;
            err_cnt <= 0;
        end else begin
            exp_gnt = '0;
            exp_idx = -1;
            for (int k = 1; k <= N; k++) begin
                if ((exp_idx < 0) && req[(last + k) % N]) begin
                    exp_idx = (last + k) % N;
                end
            end
            if (exp_idx >= 0) begin
                exp_gnt[exp_idx] = 1'b1;
            end
            if (gnt !== exp_gnt) begin
                $error("%m: req=%b gnt=%b exp=%b last=%0d", req, gnt, exp_gnt, last);
                err_cnt++;
            end
            if (gnt_ack && (exp_idx >= 0)) begin
                last <= exp_idx;
            end
        end
    end

endmodule

module tb_gnrl_misc;

    localparam int RAM_CYC = 6000;  // 存储器随机测试周期数。

    logic clk = 1'b0;  // 10ns测试时钟。
    logic rst_n;       // 低有效复位。
    int   err_arb[4];  // 各仲裁器配置错误数。
    int   err_ram;     // 存储器检查错误数。

    always #5 clk = ~clk;

    // 仲裁器：单路直通。
    tb_arb_harness #(
        .N (1)  // 单路。
    ) u_arb_n1 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .err_cnt (err_arb[0])
    );

    // 仲裁器：4路。
    tb_arb_harness #(
        .N (4)  // 默认路数。
    ) u_arb_n4 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .err_cnt (err_arb[1])
    );

    // 仲裁器：5路，非2的幂。
    tb_arb_harness #(
        .N (5)  // 非2的幂路数。
    ) u_arb_n5 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .err_cnt (err_arb[2])
    );

    // 仲裁器：8路。
    tb_arb_harness #(
        .N (8)  // 较宽路数。
    ) u_arb_n8 (
        // 时钟／复位。
        .clk     (clk),
        .rst_n   (rst_n),

        // 测试状态。
        .err_cnt (err_arb[3])
    );

    // -------------------------------------------------------------------------
    // gnrl_ram_sp：深度16、字宽16、2段写掩码
    // -------------------------------------------------------------------------
    localparam int SP_DP = 16;  // 单端口RAM测试深度。
    localparam int SP_DW = 16;  // 单端口RAM测试字宽。
    localparam int SP_MW = 2;   // 单端口RAM写掩码位数，每位控制8bit。

    logic                     sp_cs;      // 片选。
    logic                     sp_we;      // 写使能。
    logic [$clog2(SP_DP)-1:0] sp_addr;    // 地址。
    logic [SP_MW-1:0]         sp_wem;     // 写掩码。
    logic [SP_DW-1:0]         sp_din;     // 写数据。
    logic [SP_DW-1:0]         sp_dout;    // 读数据。
    logic [SP_DW-1:0]         sp_mem[SP_DP];  // 参考存储模型，初值为X。
    logic [SP_DW-1:0]         sp_exp;     // 期望读数据。
    bit                       sp_exp_vld; // 已经发生过读操作，期望读数据有效。

    gnrl_ram_sp #(
        .DP (SP_DP),  // 测试深度。
        .DW (SP_DW),  // 测试字宽。
        .MW (SP_MW)   // 测试写掩码位数。
    ) u_ram_sp (
        // 时钟。
        .clk  (clk),

        // 访问命令。
        .cs   (sp_cs),
        .we   (sp_we),
        .addr (sp_addr),

        // 写数据。
        .wem  (sp_wem),
        .din  (sp_din),

        // 读数据。
        .dout (sp_dout)
    );

    // -------------------------------------------------------------------------
    // gnrl_ram_tp：深度16、字宽32、4段写掩码
    // -------------------------------------------------------------------------
    localparam int TP_DP = 16;  // 两端口RAM测试深度。
    localparam int TP_DW = 32;  // 两端口RAM测试字宽。
    localparam int TP_MW = 4;   // 两端口RAM写掩码位数，每位控制8bit。

    logic                     tp_wen;     // 写使能。
    logic [$clog2(TP_DP)-1:0] tp_waddr;   // 写地址。
    logic [TP_MW-1:0]         tp_wem;     // 写掩码。
    logic [TP_DW-1:0]         tp_wdat;    // 写数据。
    logic                     tp_ren;     // 读使能。
    logic [$clog2(TP_DP)-1:0] tp_raddr;   // 读地址。
    logic [TP_DW-1:0]         tp_rdat;    // 读数据。
    logic [TP_DW-1:0]         tp_mem[TP_DP];  // 参考存储模型，初值为X。
    logic [TP_DW-1:0]         tp_exp;     // 期望读数据。
    bit                       tp_exp_vld; // 已经发生过读操作，期望读数据有效。

    gnrl_ram_tp #(
        .DP (TP_DP),  // 测试深度。
        .DW (TP_DW),  // 测试字宽。
        .MW (TP_MW)   // 测试写掩码位数。
    ) u_ram_tp (
        // 时钟。
        .clk   (clk),

        // 写口。
        .wen   (tp_wen),
        .waddr (tp_waddr),
        .wem   (tp_wem),
        .wdat  (tp_wdat),

        // 读口。
        .ren   (tp_ren),
        .raddr (tp_raddr),
        .rdat  (tp_rdat)
    );

    // 存储器参考模型：上升沿先取读出旧值，再按掩码写入。
    always @(posedge clk) begin
        if (sp_cs && (!sp_we)) begin
            sp_exp     <= sp_mem[sp_addr];
            sp_exp_vld <= 1'b1;
        end
        if (sp_cs && sp_we) begin
            for (int k = 0; k < SP_MW; k++) begin
                if (sp_wem[k]) begin
                    sp_mem[sp_addr][k*8 +: 8] <= sp_din[k*8 +: 8];
                end
            end
        end
        if (tp_ren) begin
            tp_exp     <= tp_mem[tp_raddr];
            tp_exp_vld <= 1'b1;
        end
        if (tp_wen) begin
            for (int k = 0; k < TP_MW; k++) begin
                if (tp_wem[k]) begin
                    tp_mem[tp_waddr][k*8 +: 8] <= tp_wdat[k*8 +: 8];
                end
            end
        end
    end

    // 存储器激励与检查：下降沿比较读数据，再驱动下一拍命令；地址集中在小范围以提高冲突概率。
    initial begin : RAM_STIM_PROC
        err_ram    = 0;
        sp_exp_vld = 1'b0;
        tp_exp_vld = 1'b0;
        sp_cs      = 1'b0;
        sp_we      = 1'b0;
        sp_addr    = '0;
        sp_wem     = '0;
        sp_din     = '0;
        tp_wen     = 1'b0;
        tp_waddr   = '0;
        tp_wem     = '0;
        tp_wdat    = '0;
        tp_ren     = 1'b0;
        tp_raddr   = '0;
        for (int c = 0; c < RAM_CYC; c++) begin
            @(negedge clk);
            if (sp_exp_vld && (sp_dout !== sp_exp)) begin
                $error("gnrl_ram_sp dout=%h exp=%h", sp_dout, sp_exp);
                err_ram++;
            end
            if (tp_exp_vld && (tp_rdat !== tp_exp)) begin
                $error("gnrl_ram_tp rdat=%h exp=%h", tp_rdat, tp_exp);
                err_ram++;
            end
            sp_cs    = ($urandom_range(0, 3) != 0);
            sp_we    = $urandom_range(0, 1);
            sp_addr  = (c < RAM_CYC / 2) ? $urandom_range(0, 3) : $urandom;
            sp_wem   = $urandom;
            sp_din   = $urandom;
            tp_wen   = $urandom_range(0, 1);
            tp_waddr = (c < RAM_CYC / 2) ? $urandom_range(0, 3) : $urandom;
            tp_wem   = $urandom;
            tp_wdat  = $urandom;
            tp_ren   = $urandom_range(0, 1);
            tp_raddr = (c < RAM_CYC / 2) ? $urandom_range(0, 3) : $urandom;
        end
    end

    initial begin : MAIN_PROC
        int total;
        rst_n = 1'b0;
        #23;
        rst_n = 1'b1;
        #((RAM_CYC + 20) * 10);
        total = err_ram;
        for (int k = 0; k < 4; k++) begin
            total += err_arb[k];
        end
        if (total == 0) begin
            $display("TB_RESULT: PASS tb_gnrl_misc");
        end else begin
            $display("TB_RESULT: FAIL tb_gnrl_misc errors=%0d", total);
        end
        $finish;
    end

endmodule

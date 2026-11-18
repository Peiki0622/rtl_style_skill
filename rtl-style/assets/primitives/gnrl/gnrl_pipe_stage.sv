// =============================================================================
// 模块：gnrl_pipe_stage
// 功能：valid/ready握手的单级流水寄存器，可选直通。
// 时序：DP=1时i_vld与i_rdy同为1的上升沿装入数据，下一拍o_vld为1；o_vld与o_rdy同为1的
//       上升沿完成输出。CUT_READY=0时允许同拍出入，吞吐率每拍一笔，但o_rdy组合传到i_rdy；
//       CUT_READY=1时i_rdy只取决于本级是否为空，切断反压组合路径，吞吐率每两拍一笔。
// 说明：数据寄存器不复位，o_vld为0时o_dat为无效值，下游必须以o_vld限定使用。
// =============================================================================
`include "std_defines.svh"

module gnrl_pipe_stage #(
    parameter int CUT_READY = 0,   // 反压切断开关：1切断o_rdy到i_rdy的组合路径，0保持满吞吐。
    parameter int DP        = 1,   // 级数：0为组合直通，1为插入一级寄存器，其他值非法。
    parameter int DW        = 32   // 数据位宽，单位为bit，合法值为正整数。
) (
    // 输入通道：i_vld与i_rdy同为1的上升沿接收i_dat；未被接收时上游保持i_vld和i_dat。
    input  wire            i_vld,
    output logic           i_rdy,
    input  wire  [DW-1:0]  i_dat,

    // 输出通道：o_vld与o_rdy同为1的上升沿完成输出；DP=1时o_vld和o_dat来自寄存器。
    output logic           o_vld,
    input  wire            o_rdy,
    output logic [DW-1:0]  o_dat,

    // 时钟／复位：全部接口属clk域；rst_n低有效异步复位，复位后本级为空。
    input  wire            clk,
    input  wire            rst_n
);

    if (DP == 0) begin : g_dp_eq_0
        // 直通：不插入寄存器，握手与数据全部组合连通。
        assign o_vld = i_vld;
        assign i_rdy = o_rdy;
        assign o_dat = i_dat;
    end else begin : g_dp_gt_0
        logic vld_set;  // 有效标志置位条件：输入握手成功，本级装入新数据。
        logic vld_clr;  // 有效标志清零条件：输出握手成功，本级数据被取走。
        logic vld_en;   // 有效标志更新使能：置位或清零任一发生。
        logic vld_d;    // 有效标志下一值：同拍置位与清零时置位优先，保持为1。
        logic vld_q;    // 有效标志寄存器输出，即o_vld。

        // 有效标志：输入握手置位、输出握手清零；同拍出入时新数据接替旧数据，保持有效。
        assign vld_set = i_vld & i_rdy;
        assign vld_clr = o_vld & o_rdy;
        assign vld_en  = vld_set | vld_clr;
        assign vld_d   = vld_set | (~vld_clr);

        // 有效标志寄存器：复位为0表示本级为空；置位或清零时更新。
        std_dfflr #(.DW(1)) u_vld_dfflr (vld_en, vld_d, vld_q, clk, rst_n);

        // 数据寄存器：只在输入握手时装入；不复位，由o_vld限定使用。
        std_dffl #(.DW(DW)) u_dat_dffl (vld_set, i_dat, o_dat, clk);

        assign o_vld = vld_q;

        if (CUT_READY == 1) begin : g_cut_ready
            // 切断反压：只有本级为空才接收，i_rdy不依赖o_rdy。
            assign i_rdy = ~vld_q;
        end else begin : g_no_cut_ready
            // 不切断反压：本级为空，或本拍数据正被取走时都可接收。
            assign i_rdy = (~vld_q) | vld_clr;
        end
    end

// synopsys translate_off
    // 参数检查：只支持0级直通和1级寄存器，多级请串联例化或使用gnrl_fifo。
    initial begin : PARAM_CHECK_PROC
        if ((DP != 0) && (DP != 1)) begin
            $fatal(1, "gnrl_pipe_stage: DP=%0d is illegal, must be 0 or 1 at %m", DP);
        end
    end
// synopsys translate_on

endmodule

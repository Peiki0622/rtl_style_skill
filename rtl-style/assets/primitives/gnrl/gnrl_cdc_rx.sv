// =============================================================================
// 模块：gnrl_cdc_rx
// 功能：跨时钟域接收端，把来自异步发送端的四相握手转换为本域valid/ready握手。
// 四相握手（i_vld_a／i_rdy）：
//   (1) 发送端拉高i_vld_a，i_dat已经稳定；(2) 本端缓冲为空时采样i_dat并拉高i_rdy；
//   (3) 发送端看到i_rdy后拉低i_vld_a；(4) 本端检测到i_vld_a下降沿后拉低i_rdy。
// 时序：i_dat在第(2)步装入本地缓冲，之后o_vld为1；本地缓冲被下游取走前不再应答新传输。
// 约束：i_vld_a须为发送端寄存器输出；i_dat在i_vld_a为1至i_rdy下降沿期间由发送端保持。
//       与gnrl_cdc_tx配对使用，两侧复位须同时有效。
// =============================================================================
`include "std_defines.svh"

module gnrl_cdc_rx #(
    parameter int DW      = 32,  // 传输数据位宽，单位为bit，合法值为正整数。
    parameter int SYNC_DP = 2    // i_vld_a的同步级数，合法值不小于2。
) (
    // 跨域四相握手输入：i_vld_a与i_dat来自发送端时钟域；i_rdy为本域寄存器输出。
    input  wire            i_vld_a,
    output logic           i_rdy,
    input  wire  [DW-1:0]  i_dat,

    // 本域输出通道：o_vld与o_rdy同为1的上升沿完成输出；o_vld和o_dat来自寄存器。
    output logic           o_vld,
    input  wire            o_rdy,
    output logic [DW-1:0]  o_dat,

    // 时钟／复位：接收端时钟域；rst_n低有效异步复位，复位后缓冲为空、没有应答。
    input  wire            clk,
    input  wire            rst_n
);

    logic           i_vld_sync;       // i_vld_a同步到本域后的电平。
    logic           i_vld_sync_r;     // i_vld_sync延迟一拍，用于下降沿检测。
    logic           i_vld_sync_nedge; // i_vld下降沿：发送端完成四相握手第(3)步。
    logic           buf_rdy;          // 本地缓冲为空，可以接收新传输。
    logic           i_rdy_set;        // 应答置位条件：缓冲为空、看到有效且尚未应答。
    logic           i_rdy_clr;        // 应答清零条件：检测到i_vld下降沿。
    logic           i_rdy_ena;        // 应答更新使能。
    logic           i_rdy_nxt;        // 应答下一值。
    logic           i_rdy_r;          // 应答寄存器输出，即i_rdy。
    logic           buf_dat_ena;      // 缓冲数据装入使能：与应答置位同拍。
    logic           buf_vld_set;      // 缓冲有效置位条件：装入新数据。
    logic           buf_vld_clr;      // 缓冲有效清零条件：本域输出握手成功。
    logic           buf_vld_ena;      // 缓冲有效更新使能。
    logic           buf_vld_nxt;      // 缓冲有效下一值。
    logic           buf_vld_r;        // 缓冲有效寄存器输出，即o_vld。

    // 有效同步：发送端的i_vld_a先同步到本域再使用。
    std_sync #(
        .DP      (SYNC_DP),  // 透传同步级数配置。
        .DW      (1),        // 只同步1bit有效信号。
        .RST_VAL (1'b0)      // 与发送端有效寄存器复位值一致。
    ) u_i_vld_sync (
        // 异步输入：发送端有效寄存器输出。
        .din_a (i_vld_a),

        // 同步输出：本域有效电平。
        .dout  (i_vld_sync),

        // 时钟／复位：接收端时钟域。
        .clk   (clk),
        .rst_n (rst_n)
    );

    // 有效下降沿：上一拍为1、本拍为0，表示发送端已撤销有效，可以撤销应答。
    std_dffr #(.DW(1)) u_i_vld_sync_dffr (i_vld_sync, i_vld_sync_r, clk, rst_n);
    assign i_vld_sync_nedge = (~i_vld_sync) & i_vld_sync_r;

    // 应答：缓冲为空且看到有效时置位，完成第(2)步；看到有效下降沿时清零，完成第(4)步。
    assign i_rdy_set = buf_rdy & i_vld_sync & (~i_rdy_r);
    assign i_rdy_clr = i_vld_sync_nedge;
    assign i_rdy_ena = i_rdy_set | i_rdy_clr;
    assign i_rdy_nxt = i_rdy_set | (~i_rdy_clr);
    std_dfflr #(.DW(1)) u_i_rdy_dfflr (i_rdy_ena, i_rdy_nxt, i_rdy_r, clk, rst_n);
    assign i_rdy = i_rdy_r;

    // 缓冲数据：与应答置位同拍采样i_dat，此时发送端保证数据已稳定。
    assign buf_dat_ena = i_rdy_set;
    std_dfflr #(.DW(DW)) u_buf_dat_dfflr (buf_dat_ena, i_dat, o_dat, clk, rst_n);

    // 缓冲有效：装入时置位，本域输出握手时清零；两者不会同拍发生，因为只有空缓冲才装入。
    assign buf_vld_set = buf_dat_ena;
    assign buf_vld_clr = o_vld & o_rdy;
    assign buf_vld_ena = buf_vld_set | buf_vld_clr;
    assign buf_vld_nxt = buf_vld_set | (~buf_vld_clr);
    std_dfflr #(.DW(1)) u_buf_vld_dfflr (buf_vld_ena, buf_vld_nxt, buf_vld_r, clk, rst_n);

    // 输出：缓冲为空才可接收下一次跨域传输。
    assign buf_rdy = ~buf_vld_r;
    assign o_vld   = buf_vld_r;

endmodule

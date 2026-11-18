// =============================================================================
// 模块：gnrl_cdc_tx
// 功能：跨时钟域发送端，把本域valid/ready握手转换为四相握手送往异步接收端。
// 四相握手（o_vld／o_rdy_a）：
//   (1) 本端拉高o_vld，o_dat同时稳定；(2) 接收端采样后拉高o_rdy_a；
//   (3) 本端检测到o_rdy_a为1后拉低o_vld；(4) 接收端检测到o_vld为0后拉低o_rdy_a。
// 时序：o_rdy_a同步到本域后，在其下降沿之前不再接收新数据；o_dat从装入到o_rdy_a下降沿
//       一直保持，接收端可以在任意时刻采样。一次传输需要两个方向各约两次同步延迟。
// 约束：o_vld和o_dat均直接来自寄存器；o_dat到接收端是多位异步路径，须按项目CDC规范
//       约束最大延迟或偏斜。与gnrl_cdc_rx配对使用，两侧复位须同时有效。
// =============================================================================
`include "std_defines.svh"

module gnrl_cdc_tx #(
    parameter int DW      = 32,  // 传输数据位宽，单位为bit，合法值为正整数。
    parameter int SYNC_DP = 2    // o_rdy_a的同步级数，合法值不小于2。
) (
    // 本域输入通道：i_vld与i_rdy同为1的上升沿接收i_dat；未被接收时上游保持i_vld和i_dat。
    input  wire            i_vld,
    output logic           i_rdy,
    input  wire  [DW-1:0]  i_dat,

    // 跨域四相握手输出：o_vld与o_dat来自本域寄存器；o_rdy_a来自接收端时钟域，异步输入。
    output logic           o_vld,
    input  wire            o_rdy_a,
    output logic [DW-1:0]  o_dat,

    // 时钟／复位：发送端时钟域；rst_n低有效异步复位，复位后没有在途传输。
    input  wire            clk,
    input  wire            rst_n
);

    logic           o_rdy_sync;    // o_rdy_a同步到本域后的电平。
    logic           o_rdy_sync_r;  // o_rdy_sync延迟一拍，用于下降沿检测。
    logic           o_rdy_nedge;   // o_rdy下降沿：接收端完成四相握手第(4)步。
    logic           vld_set;       // o_vld置位条件：本域输入握手成功，开始一次跨域传输。
    logic           vld_clr;       // o_vld清零条件：接收端已应答，即握手第(3)步。
    logic           vld_ena;       // o_vld更新使能。
    logic           vld_nxt;       // o_vld下一值；置位与清零不会同拍发生。
    logic           vld_r;         // o_vld寄存器输出。
    logic           nrdy_set;      // 忙标志置位条件：开始一次跨域传输。
    logic           nrdy_clr;      // 忙标志清零条件：检测到o_rdy下降沿，传输完全结束。
    logic           nrdy_ena;      // 忙标志更新使能。
    logic           nrdy_nxt;      // 忙标志下一值。
    logic           nrdy_r;        // 忙标志：从接收新数据到四相握手结束期间为1。

    // 应答同步：接收端的o_rdy_a先同步到本域再使用。
    std_sync #(
        .DP      (SYNC_DP),  // 透传同步级数配置。
        .DW      (1),        // 只同步1bit应答信号。
        .RST_VAL (1'b0)      // 与接收端应答寄存器复位值一致。
    ) u_o_rdy_sync (
        // 异步输入：接收端应答寄存器输出。
        .din_a (o_rdy_a),

        // 同步输出：本域应答电平。
        .dout  (o_rdy_sync),

        // 时钟／复位：发送端时钟域。
        .clk   (clk),
        .rst_n (rst_n)
    );

    // 应答下降沿：上一拍为1、本拍为0，表示接收端已撤销应答，四相握手结束。
    std_dffr #(.DW(1)) u_o_rdy_sync_dffr (o_rdy_sync, o_rdy_sync_r, clk, rst_n);
    assign o_rdy_nedge = (~o_rdy_sync) & o_rdy_sync_r;

    // 跨域有效：本域握手时置位；看到同步后的应答为1时清零，完成第(3)步。
    assign vld_set = i_vld & i_rdy;
    assign vld_clr = o_vld & o_rdy_sync;
    assign vld_ena = vld_set | vld_clr;
    assign vld_nxt = vld_set | (~vld_clr);
    std_dfflr #(.DW(1)) u_vld_dfflr (vld_ena, vld_nxt, vld_r, clk, rst_n);

    // 跨域数据：只在开始传输时装入，并保持到下一次传输开始。
    std_dfflr #(.DW(DW)) u_dat_dfflr (vld_set, i_dat, o_dat, clk, rst_n);

    // 忙标志：开始传输时置位，检测到应答下降沿时清零；忙期间不接收新数据。
    // 由于i_rdy在nrdy_clr当拍已为1，置位与清零可能同拍发生，此时置位优先、保持为忙，
    // 即在看到应答下降沿的同一拍就可以开始下一次传输。
    assign nrdy_set = vld_set;
    assign nrdy_clr = o_rdy_nedge;
    assign nrdy_ena = nrdy_set | nrdy_clr;
    assign nrdy_nxt = nrdy_set | (~nrdy_clr);
    std_dfflr #(.DW(1)) u_nrdy_dfflr (nrdy_ena, nrdy_nxt, nrdy_r, clk, rst_n);

    // 输出：跨域有效来自寄存器；忙标志为0或正在清零时可以接收新数据。
    assign o_vld = vld_r;
    assign i_rdy = (~nrdy_r) | nrdy_clr;

endmodule

// =============================================================================
// 模块：std_pulse_sync
// 功能：单周期脉冲跨时钟域同步器（翻转式）。源域每收到一个src_pulse就翻转一次电平，
//       电平经std_sync同步到目标域后做边沿检测，在目标域输出一个单周期dst_pulse。
// 时序：dst_pulse在src_pulse之后约SYNC_DP+1个dst_clk周期出现，宽度为一个dst_clk周期。
// 约束：没有应答反馈。相邻两个src_pulse之间必须至少间隔两个dst_clk周期，否则两次翻转
//       可能被目标域合并成一次而丢失脉冲；需要背压时请使用gnrl_cdc_tx／gnrl_cdc_rx。
//       两侧复位必须同时有效，单侧复位会使翻转电平失配并产生一个假脉冲。
// =============================================================================
`include "std_defines.svh"

module std_pulse_sync #(
    parameter int SYNC_DP = 2  // 目标域同步级数，合法值不小于2。
) (
    // 源域：src_pulse为src_clk域单周期脉冲，高电平期间的每个上升沿计为一次事件。
    input  wire   src_clk,
    input  wire   src_rst_n,
    input  wire   src_pulse,

    // 目标域：dst_pulse为dst_clk域单周期脉冲，每个源事件对应一个。
    input  wire   dst_clk,
    input  wire   dst_rst_n,
    output logic  dst_pulse
);

    logic src_tgl_q;     // 源域翻转电平，每个src_pulse翻转一次，复位为0。
    logic src_tgl_d;     // 源域翻转电平的下一值，即当前值取反。
    logic dst_tgl_sync;  // 翻转电平同步到目标域后的值。
    logic dst_tgl_q;     // 同步后翻转电平延迟一拍，用于边沿检测。

    // 源域翻转：src_pulse有效的上升沿翻转一次，其余周期保持。
    assign src_tgl_d = ~src_tgl_q;
    std_dfflr #(.DW(1)) u_src_tgl_dfflr (src_pulse, src_tgl_d, src_tgl_q, src_clk, src_rst_n);

    // 电平同步：把源域翻转电平同步到目标域，复位值与源域一致为0。
    std_sync #(
        .DP      (SYNC_DP),  // 透传同步级数配置。
        .DW      (1),        // 只同步1bit翻转电平。
        .RST_VAL (1'b0)      // 与源域翻转寄存器复位值一致，复位释放后不产生假边沿。
    ) u_tgl_sync (
        // 异步输入：源域翻转寄存器输出，无组合逻辑。
        .din_a (src_tgl_q),

        // 同步输出：目标域翻转电平。
        .dout  (dst_tgl_sync),

        // 时钟／复位：目标域。
        .clk   (dst_clk),
        .rst_n (dst_rst_n)
    );

    // 边沿检测：保存上一拍同步电平，与当前值不同即表示收到一次源事件。
    std_dffr #(.DW(1)) u_dst_tgl_dffr (dst_tgl_sync, dst_tgl_q, dst_clk, dst_rst_n);

    // 目标脉冲：同步电平的任一跳变产生一个dst_clk周期的脉冲。
    assign dst_pulse = dst_tgl_sync ^ dst_tgl_q;

endmodule

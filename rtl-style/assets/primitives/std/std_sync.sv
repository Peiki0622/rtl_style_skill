// =============================================================================
// 模块：std_sync
// 功能：多级触发器电平同步器，把异步电平信号同步到clk域。
// 时序：din_a变化后经过DP到DP+1个clk上升沿反映到dout；短于一个clk周期加建立保持
//       时间的脉冲可能丢失，脉冲请使用std_pulse_sync。
// 约束：din_a必须由源域触发器直接驱动，中间不得有组合逻辑。DW大于1时各位独立同步，
//       不保证同拍到达，只适用于格雷码指针等每次最多一位变化的信号；多位数据跨域请使用
//       gnrl_cdc_tx／gnrl_cdc_rx或gnrl_async_fifo。
// =============================================================================
`include "std_defines.svh"

module std_sync #(
    parameter int            DP      = 2,   // 同步级数（串联触发器个数），合法值≥2，高可靠场合取3。
    parameter int            DW      = 1,   // 同步位宽(bit)；大于1时只用于每次最多一位变化的信号。
    parameter logic [DW-1:0] RST_VAL = '0   // 各级复位值，须与源信号复位值一致，避免假跳变。
) (
    // 异步输入：来自其他时钟域的电平信号，由源域触发器直接驱动。
    input  wire  [DW-1:0]  din_a,

    // 同步输出：clk域内可直接使用的电平信号。
    output logic [DW-1:0]  dout,

    // 时钟／复位：目标域时钟；rst_n低有效异步复位，释放须已在clk域同步。
    input  wire            clk,
    input  wire            rst_n
);

    logic [DP-1:0][DW-1:0] sync_dat;  // 各级输出：[0]为第一级（可能亚稳态），[DP-1]为最后一级。

    // 同步链：第一级采样异步输入，其后每级采样前一级，逐级降低亚稳态传播概率。
    for (genvar i = 0; i < DP; i = i + 1) begin : g_sync_stage
        if (i == 0) begin : g_first
            // 第一级：直接采样异步输入，输出可能亚稳态，只允许连接下一级同步触发器。
            std_dffr #(.DW(DW), .RST_VAL(RST_VAL)) u_sync_dffr (din_a, sync_dat[0], clk, rst_n);
        end else begin : g_follow
            // 后续级：采样前一级输出，最后一级的输出才可供clk域逻辑使用。
            std_dffr #(.DW(DW), .RST_VAL(RST_VAL))
                u_sync_dffr (sync_dat[i-1], sync_dat[i], clk, rst_n);
        end
    end

    // 同步输出：取最后一级触发器。
    assign dout = sync_dat[DP-1];

// synopsys translate_off
    // 参数检查：同步级数少于2时无法提供亚稳态恢复时间，仿真开始即报错。
    initial begin : PARAM_CHECK_PROC
        if (DP < 2) begin
            $fatal(1, "std_sync: DP=%0d is illegal, must be >= 2 at %m", DP);
        end
    end
// synopsys translate_on

endmodule

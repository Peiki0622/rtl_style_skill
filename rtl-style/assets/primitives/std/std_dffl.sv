// =============================================================================
// 模块：std_dffl
// 功能：带加载使能、无复位的通用寄存器原语。
// 时序：clk上升沿lden为1时装入dnxt，为0时保持原值；上电后直到第一次装入前输出为X。
// 适用：由有效标志限定使用的宽数据寄存器，如FIFO存储体、流水线数据级、小寄存器堆，
//       不复位以节省面积。控制信号、有效标志和状态寄存器不得使用本原语。
// 端口顺序：(lden, dnxt, qout, clk)是单行位置例化的固定顺序，不得调整。
// =============================================================================
`include "std_defines.svh"

module std_dffl #(
    parameter int DW = 32  // 寄存器位宽，单位为bit，合法值为正整数。
) (
    // 加载控制与数据：lden在clk上升沿为1时装入dnxt，为0时保持；仿真中lden不允许为X/Z。
    input  wire            lden,
    input  wire  [DW-1:0]  dnxt,

    // 寄存器输出：直接来自触发器Q端，没有复位值。
    output logic [DW-1:0]  qout,

    // 时钟：上升沿采样；本原语没有复位端口。
    input  wire            clk
);

    // 寄存器本体：只在加载使能有效时更新，否则保持。
    always_ff @(posedge clk) begin : DFFL_PROC
        if (lden) begin
            qout <= `STD_DLY dnxt;
        end
    end

`ifndef STD_FPGA_SOURCE
`ifndef STD_DISABLE_ASSERTION
// synopsys translate_off
    // 仿真检查：加载使能为X/Z时寄存器是否更新不可确定，出现时立即终止仿真。
    std_xchecker #(
        .DW (1)  // 只检查1bit加载使能lden。
    ) u_lden_xchecker (
        // 被检查信号：本寄存器的加载使能。
        .i_dat (lden),

        // 时钟：与寄存器同沿采样。
        .clk   (clk)
    );
// synopsys translate_on
`endif
`endif

endmodule

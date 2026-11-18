// =============================================================================
// 模块：std_xchecker
// 功能：仿真专用X/Z检查器。在clk上升沿检查i_dat，任一位为X/Z时断言失败并终止仿真。
// 说明：整个模块位于translate_off区域内，综合工具看不到它；定义STD_FPGA_SOURCE或
//       STD_DISABLE_ASSERTION时不编译。例化处必须使用相同的宏条件和translate_off包裹。
//       检查从仿真第0个上升沿开始，不受复位屏蔽，测试平台须在第一个时钟沿前驱动确定值。
// =============================================================================
`include "std_defines.svh"

`ifndef STD_FPGA_SOURCE
`ifndef STD_DISABLE_ASSERTION
// synopsys translate_off
module std_xchecker #(
    parameter int DW = 32  // 被检查信号的总位宽，单位为bit，合法值为正整数。
) (
    // 被检查数据：任一位为X/Z时断言失败。
    input  wire  [DW-1:0]  i_dat,

    // 时钟：在上升沿采样被检查数据。
    input  wire            clk
);

    // 归约异或把任一X/Z位传播为X；!==按四态比较，只有出现X/Z时才失败。
    CHECK_THE_X_VALUE : assert property (
        @(posedge clk) ((^i_dat) !== 1'bx)
    ) else begin
        $fatal(1, "std_xchecker: X/Z value detected at %m");
    end

endmodule
// synopsys translate_on
`endif
`endif

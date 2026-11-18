// =============================================================================
// 模块：std_ltch
// 功能：高电平透明的通用锁存器原语。lden为1时qout跟随dnxt，为0时保持最后的值。
// 适用：只在经评审确认需要锁存器的场合使用，如时间借用数据通路；门控时钟请使用
//       std_clkgate，不得用本原语自行搭建。上电后直到第一次透明前输出为X。
// 端口顺序：(lden, dnxt, qout)是单行位置例化的固定顺序，不得调整。
// =============================================================================
`include "std_defines.svh"

module std_ltch #(
    parameter int DW = 32  // 锁存器位宽，单位为bit，合法值为正整数。
) (
    // 透明控制与数据：lden为1时透明，为0时锁存；仿真中lden不允许为X/Z。
    input  wire            lden,
    input  wire  [DW-1:0]  dnxt,

    // 锁存输出：透明期间跟随dnxt，锁存期间保持。
    output logic [DW-1:0]  qout
);

    // 锁存器本体：只在透明期间更新，lden为0时保持。
    always_latch begin : LTCH_PROC
        if (lden) begin
            qout <= dnxt;
        end
    end

`ifndef STD_FPGA_SOURCE
`ifndef STD_DISABLE_ASSERTION
// synopsys translate_off
    // 仿真检查：用final延迟断言在信号稳定后检查透明控制，出现X/Z时立即终止仿真。
    always_comb begin : LTCH_XCHECK_PROC
        CHECK_THE_X_VALUE : assert final (!$isunknown(lden)) else begin
            $fatal(1, "std_ltch: X/Z value detected on lden at %m");
        end
    end
// synopsys translate_on
`endif
`endif

endmodule

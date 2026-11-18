// =============================================================================
// 模块：std_dfflrs
// 功能：带加载使能、低有效异步复位的通用寄存器原语，复位值固定为全1。
// 时序：rst_n为0时立即置为全1；rst_n为1时，clk上升沿lden为1则装入dnxt，否则保持。
// 说明：等价于RST_VAL为全1的std_dfflr，供复位值全1的寄存器直接表达意图。
// 端口顺序：(lden, dnxt, qout, clk, rst_n)是单行位置例化的固定顺序，不得调整。
// =============================================================================
`include "std_defines.svh"

module std_dfflrs #(
    parameter int DW = 32  // 寄存器位宽，单位为bit，合法值为正整数。
) (
    // 加载控制与数据：lden在clk上升沿为1时装入dnxt，为0时保持；仿真中lden不允许为X/Z。
    input  wire            lden,
    input  wire  [DW-1:0]  dnxt,

    // 寄存器输出：直接来自触发器Q端，复位期间为全1。
    output logic [DW-1:0]  qout,

    // 时钟／复位：clk上升沿采样；rst_n低有效异步复位，释放须已在clk域同步。
    input  wire            clk,
    input  wire            rst_n
);

    // 寄存器本体：复位优先置全1，其次按加载使能决定装入或保持。
    always_ff @(posedge clk or negedge rst_n) begin : DFFLRS_PROC
        if (!rst_n) begin
            qout <= {DW{1'b1}};
        end else if (lden) begin
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

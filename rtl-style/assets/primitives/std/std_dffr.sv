// =============================================================================
// 模块：std_dffr
// 功能：无加载使能、低有效异步复位的通用寄存器原语，复位值由RST_VAL给定（默认全0）。
// 时序：rst_n为0时立即装入RST_VAL；rst_n为1时每个clk上升沿无条件装入dnxt。
// 适用：每拍都更新的控制信号，如同步器级、边沿检测延迟级和复位同步链。
// 端口顺序：(dnxt, qout, clk, rst_n)是单行位置例化的固定顺序，不得调整。
// =============================================================================
`include "std_defines.svh"

module std_dffr #(
    parameter int            DW      = 32,  // 寄存器位宽，单位为bit，合法值为正整数。
    parameter logic [DW-1:0] RST_VAL = '0   // 异步复位期间装入的值，位宽等于DW，默认全0。
) (
    // 下一值输入：复位释放后每个clk上升沿无条件装入。
    input  wire  [DW-1:0]  dnxt,

    // 寄存器输出：直接来自触发器Q端，复位期间等于RST_VAL。
    output logic [DW-1:0]  qout,

    // 时钟／复位：clk上升沿采样；rst_n低有效异步复位，释放须已在clk域同步。
    input  wire            clk,
    input  wire            rst_n
);

    // 寄存器本体：复位优先；复位释放后每拍装入下一值。
    always_ff @(posedge clk or negedge rst_n) begin : DFFR_PROC
        if (!rst_n) begin
            qout <= RST_VAL;
        end else begin
            qout <= `STD_DLY dnxt;
        end
    end

endmodule

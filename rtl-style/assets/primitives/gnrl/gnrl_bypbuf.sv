// =============================================================================
// 模块：gnrl_bypbuf
// 功能：带旁路的缓冲器，用于切断ready组合路径而不增加空载延迟。
// 时序：
//   - 内部FIFO为空且下游o_rdy为1时，输入数据同拍旁路到输出，没有额外延迟。
//   - 下游反压时，输入数据存入内部FIFO，之后优先输出FIFO中的数据，保证先入先出。
//   - i_rdy只取决于内部FIFO是否已满，不依赖o_rdy，从而切断下游ready到上游的组合路径。
// 说明：o_vld和o_dat在旁路时组合来自i_vld和i_dat，前向路径仍有组合逻辑。
// =============================================================================
`include "std_defines.svh"

module gnrl_bypbuf #(
    parameter int DP = 8,   // 内部FIFO深度，单位为条目；合法值为正整数，DP=1时内部FIFO切断反压。
    parameter int DW = 32   // 数据位宽，单位为bit，合法值为正整数。
) (
    // 输入通道：i_vld与i_rdy同为1的上升沿接收i_dat；i_rdy只由内部FIFO是否已满决定。
    input  wire            i_vld,
    output logic           i_rdy,
    input  wire  [DW-1:0]  i_dat,

    // 输出通道：o_vld与o_rdy同为1的上升沿完成输出；FIFO非空时优先输出FIFO数据。
    output logic           o_vld,
    input  wire            o_rdy,
    output logic [DW-1:0]  o_dat,

    // 时钟／复位：全部接口属clk域；rst_n低有效异步复位，复位后缓冲为空。
    input  wire            clk,
    input  wire            rst_n
);

    logic           fifo_i_vld;  // 送入内部FIFO的写有效：输入有效且本拍没有旁路。
    logic           fifo_i_rdy;  // 内部FIFO未满，可接收写入。
    logic           fifo_o_vld;  // 内部FIFO非空。
    logic           fifo_o_rdy;  // 内部FIFO读出就绪，直接取下游o_rdy。
    logic [DW-1:0]  fifo_o_dat;  // 内部FIFO队首数据。
    logic           byp;         // 旁路条件：输入有效、下游就绪且FIFO为空。

    // 内部FIFO：反压时暂存输入；CUT_READY固定为1，保证DP=1时也不形成ready组合路径。
    gnrl_fifo #(
        .CUT_READY (1),   // 固定切断反压路径，这是本模块存在的目的。
        .MSKO      (0),   // 输出由fifo_o_vld选择，不需要额外屏蔽。
        .DP        (DP),  // 透传缓冲深度。
        .DW        (DW)   // 透传数据位宽。
    ) u_bypbuf_fifo (
        // 写入通道：非旁路的输入数据进入FIFO。
        .i_vld (fifo_i_vld),
        .i_rdy (fifo_i_rdy),
        .i_dat (i_dat),

        // 读出通道：FIFO队首数据，下游就绪时弹出。
        .o_vld (fifo_o_vld),
        .o_rdy (fifo_o_rdy),
        .o_dat (fifo_o_dat),

        // 时钟／复位：与本模块相同。
        .clk   (clk),
        .rst_n (rst_n)
    );

    // 输入就绪：只看FIFO是否已满，不依赖o_rdy。
    assign i_rdy = fifo_i_rdy;

    // 旁路判定：FIFO为空且下游可接收时，输入直接送出，不写入FIFO。
    assign byp = i_vld & o_rdy & (~fifo_o_vld);

    // FIFO读写：下游就绪即弹出FIFO队首；只有不旁路时输入才写入FIFO。
    assign fifo_o_rdy = o_rdy;
    assign fifo_i_vld = i_vld & (~byp);

    // 输出：FIFO或输入任一有效即有效；FIFO非空时优先输出FIFO数据以保持顺序。
    assign o_vld = fifo_o_vld | i_vld;
    assign o_dat = fifo_o_vld ? fifo_o_dat : i_dat;

// synopsys translate_off
    // 参数检查：DP=0时内部FIFO变为直通，旁路判定与FIFO有效形成组合环，必须至少一个条目。
    initial begin : PARAM_CHECK_PROC
        if (DP < 1) begin
            $fatal(1, "gnrl_bypbuf: DP=%0d is illegal, must be >= 1 at %m", DP);
        end
    end
// synopsys translate_on

endmodule

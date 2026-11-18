// =============================================================================
// 模块：std_rst_sync
// 功能：复位同步器，实现低有效复位的“异步置位、同步释放”。
// 时序：rst_n_a拉低时rst_n_sync立即拉低；rst_n_a释放后，rst_n_sync在第DP个clk上升沿
//       变为1。test_mode为1时旁路同步链，rst_n_sync直接等于rst_n_a，供扫描测试控制复位。
// 约束：每个时钟域使用各自的复位同步器，输出只给本clk域的触发器做异步复位。
// =============================================================================
`include "std_defines.svh"

module std_rst_sync #(
    parameter int DP = 2  // 复位释放同步级数；合法值不小于2，高频或高可靠场合取3。
) (
    // 时钟：目标复位域时钟，复位释放与其上升沿对齐。
    input  wire   clk,

    // 复位输入：低有效异步复位，任意时刻拉低立即生效，释放时刻可与clk异步。
    input  wire   rst_n_a,

    // 测试控制：扫描测试期间为1，旁路同步链；功能模式下保持为0。
    input  wire   test_mode,

    // 同步复位输出：低有效，异步拉低、同步释放，给clk域触发器的rst_n使用。
    output logic  rst_n_sync
);

    logic [DP-1:0] rst_sync_r;    // 复位同步链寄存器，复位期间全0，释放后从[0]开始逐拍移入1。
    logic [DP-1:0] rst_sync_nxt;  // 同步链下一值：整体左移一位并在[0]移入1。

    // 同步链移位：复位释放后每拍向高位移入1，第DP拍最高位变为1。
    assign rst_sync_nxt = {rst_sync_r[DP-2:0], 1'b1};

    // 同步链寄存器：以rst_n_a异步清零，实现复位立即生效。
    std_dffr #(.DW(DP), .RST_VAL('0)) u_rst_sync_dffr (rst_sync_nxt, rst_sync_r, clk, rst_n_a);

    // 复位输出：功能模式取同步链最高位；测试模式直接旁路到外部复位。
    assign rst_n_sync = test_mode ? rst_n_a : rst_sync_r[DP-1];

// synopsys translate_off
    // 参数检查：同步级数少于2时无法提供亚稳态恢复时间，仿真开始即报错。
    initial begin : PARAM_CHECK_PROC
        if (DP < 2) begin
            $fatal(1, "std_rst_sync: DP=%0d is illegal, must be >= 2 at %m", DP);
        end
    end
// synopsys translate_on

endmodule

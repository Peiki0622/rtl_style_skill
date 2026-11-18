// =============================================================================
// 模块：gnrl_async_fifo
// 功能：异步FIFO，写端与读端位于两个独立时钟域，两侧均为valid/ready握手。
// 结构：
//   - 读写指针各为AW+1位二进制计数器，最高位为回绕标志；每侧同时保存其格雷码寄存器。
//   - 格雷码指针经std_sync同步到对侧，每次只变化一位，多位同步不会产生错误中间值。
//   - 存储体为DP个不复位的std_dffl，位于写时钟域；读端按二进制读地址组合选择。
// 时序：
//   - 写入：i_vld与i_rdy同为1的wclk上升沿写入；满时i_rdy为0。
//   - 读出：o_vld为1表示非空，o_dat为队首数据；与o_rdy同为1的rclk上升沿弹出。
//   - 写入的数据经过SYNC_DP到SYNC_DP+1个rclk周期后才在读端可见；空满判断是保守的，
//     对侧指针的同步延迟只会让FIFO暂时显得更满或更空，不会上溢或下溢。
// 约束：DP必须是不小于2的2的幂。两侧复位必须同时有效；存储体到读端o_dat的路径是
//       跨时钟域路径，须按项目CDC规范约束最大延迟。
// =============================================================================
`include "std_defines.svh"

module gnrl_async_fifo #(
    parameter int DP      = 8,   // FIFO深度，单位为条目；合法值为不小于2的2的幂。
    parameter int DW      = 32,  // 数据位宽，单位为bit，合法值为正整数。
    parameter int SYNC_DP = 2    // 格雷码指针跨域同步级数，合法值不小于2。
) (
    // 写时钟域：wclk上升沿采样；wrst_n低有效异步复位，须已在wclk域同步释放。
    input  wire            wclk,
    input  wire            wrst_n,

    // 写入通道（wclk域）：i_vld与i_rdy同为1的上升沿写入i_dat；未被接收时上游保持。
    input  wire            i_vld,
    output logic           i_rdy,
    input  wire  [DW-1:0]  i_dat,

    // 读时钟域：rclk上升沿采样；rrst_n低有效异步复位，须已在rclk域同步释放。
    input  wire            rclk,
    input  wire            rrst_n,

    // 读出通道（rclk域）：o_vld为1时o_dat为队首数据；与o_rdy同为1的上升沿弹出。
    output logic           o_vld,
    input  wire            o_rdy,
    output logic [DW-1:0]  o_dat
);

    // AW：DP非法（小于2）时取1，仅用于保证展开并让参数检查报错，不代表接受该配置。
    localparam int AW = (DP > 1) ? $clog2(DP) : 1;  // 存储体地址位宽，等于log2(DP)。
    localparam int PW = AW + 1;                      // 指针位宽：地址位加一位回绕标志，区分空满。

    logic           wen;                 // 写握手：本拍写入一条数据（wclk域）。
    logic [PW-1:0]  wptr_bin_r;          // 写指针二进制值（wclk域）。
    logic [PW-1:0]  wptr_bin_nxt;        // 写指针二进制下一值：加1。
    logic [PW-1:0]  wptr_gray_r;         // 写指针格雷码寄存器（wclk域），直接送往读域同步。
    logic [PW-1:0]  wptr_gray_nxt;       // 写指针格雷码下一值，由二进制下一值转换。
    logic [PW-1:0]  rptr_gray_wsync;     // 读指针格雷码同步到wclk域后的值。
    logic [PW-1:0]  full_cmp;            // 满比较值：同步读指针的最高两位取反，其余位不变。
    logic           fifo_full;           // 满标志（wclk域）。
    logic [DP-1:0]  waddr_dec;           // 写地址独热译码：第k位为1表示写地址等于k。
    logic [DP-1:0]  fifo_rf_en;          // 各条目写使能：写握手且写地址等于该条目。
    logic [DW-1:0]  fifo_rf_r [DP];      // 存储体，位于wclk域，各条目不复位。

    logic           ren;                 // 读握手：本拍弹出一条数据（rclk域）。
    logic [PW-1:0]  rptr_bin_r;          // 读指针二进制值（rclk域）。
    logic [PW-1:0]  rptr_bin_nxt;        // 读指针二进制下一值：加1。
    logic [PW-1:0]  rptr_gray_r;         // 读指针格雷码寄存器（rclk域），直接送往写域同步。
    logic [PW-1:0]  rptr_gray_nxt;       // 读指针格雷码下一值，由二进制下一值转换。
    logic [PW-1:0]  wptr_gray_rsync;     // 写指针格雷码同步到rclk域后的值。
    logic           fifo_empty;          // 空标志（rclk域）。

    // ---------------------------------------------------------------------
    // 写时钟域：写指针、满判断和存储体写入
    // ---------------------------------------------------------------------
    // 写握手：未满才接收。
    assign wen   = i_vld & i_rdy;
    assign i_rdy = ~fifo_full;

    // 写指针：写握手时加1，二进制与格雷码同拍更新；格雷码由二进制右移一位异或得到。
    assign wptr_bin_nxt  = wptr_bin_r + 1'b1;
    assign wptr_gray_nxt = wptr_bin_nxt ^ (wptr_bin_nxt >> 1);
    std_dfflr #(.DW(PW)) u_wptr_bin_dfflr (wen, wptr_bin_nxt, wptr_bin_r, wclk, wrst_n);
    std_dfflr #(.DW(PW)) u_wptr_gray_dfflr (wen, wptr_gray_nxt, wptr_gray_r, wclk, wrst_n);

    // 读指针同步：读域格雷码寄存器输出同步到写域，用于满判断。
    std_sync #(
        .DP      (SYNC_DP),  // 透传同步级数配置。
        .DW      (PW),       // 同步整个格雷码指针，每次最多一位变化。
        .RST_VAL ('0)        // 与读指针复位值一致，复位释放后不出现假满。
    ) u_rptr_gray_wsync (
        // 异步输入：读域格雷码指针寄存器。
        .din_a (rptr_gray_r),

        // 同步输出：写域可见的读指针。
        .dout  (rptr_gray_wsync),

        // 时钟／复位：写时钟域。
        .clk   (wclk),
        .rst_n (wrst_n)
    );

    // 满判断：写指针比读指针多走一整圈时，格雷码最高两位相反、其余位相同。
    if (PW > 2) begin : g_full_cmp_wide
        assign full_cmp = {~rptr_gray_wsync[PW-1:PW-2], rptr_gray_wsync[PW-3:0]};
    end else begin : g_full_cmp_narrow
        // DP=2时指针只有两位，两位全部取反即为满比较值。
        assign full_cmp = ~rptr_gray_wsync;
    end
    assign fifo_full = (wptr_gray_r == full_cmp);

    // 存储体：写地址译码为独热码，写握手时把数据写入写地址指向的条目。
    assign waddr_dec = {{(DP-1){1'b0}}, 1'b1} << wptr_bin_r[AW-1:0];
    for (genvar i = 0; i < DP; i = i + 1) begin : g_fifo_rf
        assign fifo_rf_en[i] = wen & waddr_dec[i];

        // 条目寄存器：不复位，读端只在非空时读取已写入的条目。
        std_dffl #(.DW(DW)) u_fifo_rf_dffl (fifo_rf_en[i], i_dat, fifo_rf_r[i], wclk);
    end

    // ---------------------------------------------------------------------
    // 读时钟域：读指针、空判断和数据读出
    // ---------------------------------------------------------------------
    // 读握手：非空才输出有效。
    assign o_vld = ~fifo_empty;
    assign ren   = o_vld & o_rdy;

    // 读指针：读握手时加1，二进制与格雷码同拍更新。
    assign rptr_bin_nxt  = rptr_bin_r + 1'b1;
    assign rptr_gray_nxt = rptr_bin_nxt ^ (rptr_bin_nxt >> 1);
    std_dfflr #(.DW(PW)) u_rptr_bin_dfflr (ren, rptr_bin_nxt, rptr_bin_r, rclk, rrst_n);
    std_dfflr #(.DW(PW)) u_rptr_gray_dfflr (ren, rptr_gray_nxt, rptr_gray_r, rclk, rrst_n);

    // 写指针同步：写域格雷码寄存器输出同步到读域，用于空判断。
    std_sync #(
        .DP      (SYNC_DP),  // 透传同步级数配置。
        .DW      (PW),       // 同步整个格雷码指针，每次最多一位变化。
        .RST_VAL ('0)        // 与写指针复位值一致，复位释放后FIFO为空。
    ) u_wptr_gray_rsync (
        // 异步输入：写域格雷码指针寄存器。
        .din_a (wptr_gray_r),

        // 同步输出：读域可见的写指针。
        .dout  (wptr_gray_rsync),

        // 时钟／复位：读时钟域。
        .clk   (rclk),
        .rst_n (rrst_n)
    );

    // 空判断：读指针追上同步后的写指针时为空。
    assign fifo_empty = (rptr_gray_r == wptr_gray_rsync);

    // 数据读出：按读地址选择存储体条目；该条目在写指针同步到读域前已经写稳。
    assign o_dat = fifo_rf_r[rptr_bin_r[AW-1:0]];

// synopsys translate_off
    // 参数检查：格雷码空满判断要求深度为不小于2的2的幂。
    initial begin : PARAM_CHECK_PROC
        if ((DP < 2) || ((DP & (DP - 1)) != 0)) begin
            $fatal(1, "gnrl_async_fifo: DP=%0d is illegal, must be a power of 2 and >= 2 at %m",
                   DP);
        end
        if (SYNC_DP < 2) begin
            $fatal(1, "gnrl_async_fifo: SYNC_DP=%0d is illegal, must be >= 2 at %m", SYNC_DP);
        end
    end
// synopsys translate_on

endmodule

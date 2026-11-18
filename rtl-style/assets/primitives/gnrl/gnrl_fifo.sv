// =============================================================================
// 模块：gnrl_fifo
// 功能：同步FIFO，valid/ready握手，读写同一时钟域。
// 结构：存储体为DP个不复位的std_dffl；读写指针为独热码，读出为独热与或选择，避免二进制
//       译码；占用量为温度计码，o_vld和满标志都直接取自寄存器位。
// 时序：
//   - 写入：i_vld与i_rdy同为1的上升沿写入；读出：o_vld与o_rdy同为1的上升沿弹出。
//   - 先入先出，写入的数据最早在下一拍出现在o_dat，没有同拍旁路。
//   - DP=1时：CUT_READY=0允许满时同拍读写，满吞吐，但o_rdy组合传到i_rdy；CUT_READY=1时
//     只有空才接收，切断反压路径，吞吐率每两拍一笔。
//   - DP>1时：i_rdy只取决于是否已满，CUT_READY不起作用；满时即使同拍读出也不接收写入。
// 说明：DP=0时为组合直通。MSKO=1时o_vld为0的周期o_dat强制为0，屏蔽存储体中的X。
// =============================================================================
`include "std_defines.svh"

module gnrl_fifo #(
    parameter int CUT_READY = 0,   // 反压切断开关，仅DP=1有效：1切断o_rdy到i_rdy，0满吞吐。
    parameter int MSKO      = 0,   // 输出屏蔽开关：1在o_vld为0时o_dat清零，0不屏蔽。
    parameter int DP        = 8,   // FIFO深度，单位为条目；0为组合直通，合法值为非负整数。
    parameter int DW        = 32   // 数据位宽，单位为bit，合法值为正整数。
) (
    // 写入通道：i_vld与i_rdy同为1的上升沿写入i_dat；未被接收时上游保持i_vld和i_dat。
    input  wire            i_vld,
    output logic           i_rdy,
    input  wire  [DW-1:0]  i_dat,

    // 读出通道：o_vld为1表示FIFO非空，o_dat为队首数据；与o_rdy同为1的上升沿弹出。
    output logic           o_vld,
    input  wire            o_rdy,
    output logic [DW-1:0]  o_dat,

    // 时钟／复位：全部接口属clk域；rst_n低有效异步复位，复位后FIFO为空。
    input  wire            clk,
    input  wire            rst_n
);

    // DP_SAFE：DP=0（直通）时取1，仅用于保证未选中的生成分支能够展开，直通配置不使用。
    localparam int DP_SAFE = (DP > 0) ? DP : 1;  // 存储条目数与指针宽度，DP>0时等于DP。

    if (DP == 0) begin : g_dp_eq_0
        // 直通：深度为0时不插入存储，握手与数据全部组合连通。
        assign o_vld = i_vld;
        assign i_rdy = o_rdy;
        assign o_dat = i_dat;
    end else begin : g_dp_gt_0
        localparam logic [DP_SAFE-1:0] PTR_RST_VAL = 1;  // 独热指针复位值：第0位为1，指向条目0。

        logic           wen;                 // 写握手：本拍写入一条数据。
        logic           ren;                 // 读握手：本拍弹出一条数据。
        logic [DP-1:0]  wptr_vec_q;          // 独热写指针，指向下一次写入的条目。
        logic [DP-1:0]  wptr_vec_d;          // 写指针下一值：循环左移一位。
        logic [DP-1:0]  rptr_vec_q;          // 独热读指针，指向队首条目。
        logic [DP-1:0]  rptr_vec_d;          // 读指针下一值：循环左移一位。
        logic [DP-1:0]  cnt_vec_q;           // 温度计码占用量，第k位为1表示条目数大于k。
        logic [DP-1:0]  cnt_vec_d;           // 占用量下一值：只写时左移入1，只读时右移入0。
        logic           cnt_vec_en;          // 占用量更新使能：只写或只读时更新，同拍读写时不变。
        logic           fifo_full;           // 满标志：条目数等于DP。
        logic [DP-1:0]  fifo_rf_en;          // 各条目写使能：写握手且写指针指向该条目。
        logic [DW-1:0]  fifo_rf_q [DP_SAFE]; // 存储体，各条目不复位，由占用量限定有效性。
        logic [DW-1:0]  mux_rdat;            // 按独热读指针选出的队首数据。

        // 握手：写入受i_rdy限制，读出受o_vld限制，保证不上溢也不下溢。
        assign wen = i_vld & i_rdy;
        assign ren = o_vld & o_rdy;

        if (DP == 1) begin : g_ptr_dp_eq_1
            // 单条目：指针恒指向第0个条目；只写时占用量置1，只读时清0。
            assign wptr_vec_d   = 1'b1;
            assign rptr_vec_d   = 1'b1;
            assign cnt_vec_d    = wen;
        end else begin : g_ptr_dp_gt_1
            // 多条目：指针循环左移，最高位回到第0位；占用量按读写方向移位。
            assign wptr_vec_d   = {wptr_vec_q[DP-2:0], wptr_vec_q[DP-1]};
            assign rptr_vec_d   = {rptr_vec_q[DP-2:0], rptr_vec_q[DP-1]};
            assign cnt_vec_d    = wen ? {cnt_vec_q[DP-2:0], 1'b1} : {1'b0, cnt_vec_q[DP-1:1]};
        end

        // 写指针：复位指向第0个条目，每次写握手前进一格。
        std_dfflr #(.DW(DP), .RST_VAL(PTR_RST_VAL))
            u_wptr_vec_dfflr (wen, wptr_vec_d, wptr_vec_q, clk, rst_n);

        // 读指针：复位指向第0个条目，每次读握手前进一格。
        std_dfflr #(.DW(DP), .RST_VAL(PTR_RST_VAL))
            u_rptr_vec_dfflr (ren, rptr_vec_d, rptr_vec_q, clk, rst_n);

        // 占用量：复位为空；只写或只读时更新，同拍读写时条目数不变。
        assign cnt_vec_en = wen ^ ren;
        std_dfflr #(.DW(DP)) u_cnt_vec_dfflr (cnt_vec_en, cnt_vec_d, cnt_vec_q, clk, rst_n);

        // 空满：o_vld取占用量最低位，满标志取最高位，均直接来自寄存器。
        assign fifo_full = cnt_vec_q[DP-1];
        assign o_vld     = cnt_vec_q[0];

        if (DP == 1) begin : g_rdy_dp_eq_1
            if (CUT_READY == 1) begin : g_cut_ready
                // 切断反压：只有为空才接收，i_rdy不依赖o_rdy。
                assign i_rdy = ~fifo_full;
            end else begin : g_no_cut_ready
                // 不切断反压：为空，或本拍唯一条目正被读出时都可接收。
                assign i_rdy = (~fifo_full) | ren;
            end
        end else begin : g_rdy_dp_gt_1
            // 多条目：只按是否已满决定，i_rdy不依赖o_rdy。
            assign i_rdy = ~fifo_full;
        end

        // 存储体：每个条目只在写握手且写指针指向它时装入。
        for (genvar i = 0; i < DP; i = i + 1) begin : g_fifo_rf
            assign fifo_rf_en[i] = wen & wptr_vec_q[i];

            // 条目寄存器：不复位，由占用量和读指针保证只读出已写入的值。
            std_dffl #(.DW(DW)) u_fifo_rf_dffl (fifo_rf_en[i], i_dat, fifo_rf_q[i], clk);
        end

        // 读出选择：独热读指针按位与后逐项相或，没有优先级链。
        always_comb begin : RD_MUX_PROC
            mux_rdat = '0;
            for (int j = 0; j < DP; j = j + 1) begin
                mux_rdat = mux_rdat | ({DW{rptr_vec_q[j]}} & fifo_rf_q[j]);
            end
        end

        if (MSKO == 1) begin : g_mask_output
            // 输出屏蔽：FIFO为空时输出0，避免未写入条目的X向下游传播。
            assign o_dat = {DW{o_vld}} & mux_rdat;
        end else begin : g_no_mask_output
            // 不屏蔽：数据通路以o_vld限定使用，节省与门。
            assign o_dat = mux_rdat;
        end
    end

// synopsys translate_off
    // 参数检查：深度不能为负。
    initial begin : PARAM_CHECK_PROC
        if (DP < 0) begin
            $fatal(1, "gnrl_fifo: DP=%0d is illegal, must be >= 0 at %m", DP);
        end
    end
// synopsys translate_on

endmodule

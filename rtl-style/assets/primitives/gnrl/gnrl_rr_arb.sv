// =============================================================================
// 模块：gnrl_rr_arb
// 功能：N路轮询（round-robin）仲裁器，组合输出独热授权，优先级寄存器循环轮转。
// 算法：
//   - pri_mask_r标记“上次被授权者之后”的请求位。先在屏蔽后的请求中取最低位；
//     屏蔽后没有请求时，再在全部请求中取最低位，实现从上次授权者之后开始的循环查找。
//   - 取最低位使用x & ~(x - 1)，没有逐位优先级链。
// 时序：gnt与req同拍组合产生，至多一位为1；只有gnt_ack为1的上升沿才轮转优先级，
//       因此授权未被接受时下一拍仍优先同一请求者。复位后第0路优先级最高。
// =============================================================================
`include "std_defines.svh"

module gnrl_rr_arb #(
    parameter int N = 4  // 请求路数，合法值为正整数；N=1时授权直接等于请求。
) (
    // 时钟／复位：全部接口属clk域；rst_n低有效异步复位，复位后第0路优先级最高。
    input  wire            clk,
    input  wire            rst_n,

    // 请求与授权：req各位独立；gnt为本拍组合授权结果，至多一位为1，没有请求时全0。
    input  wire  [N-1:0]   req,
    output logic [N-1:0]   gnt,

    // 授权确认：本拍授权被下游接受时为1，上升沿把最高优先级移到被授权者之后一路。
    input  wire            gnt_ack
);

    if (N == 1) begin : g_n_eq_1
        // 单路：没有竞争，请求即授权，不需要优先级寄存器。
        assign gnt = req;
    end else begin : g_n_gt_1
        localparam logic [N-1:0] ONE = 1;  // N位常数1，用于取最低位和生成屏蔽，保证运算位宽为N。

        logic [N-1:0] pri_mask_r;    // 优先级屏蔽寄存器：为1的位是上次授权者之后的请求位。
        logic [N-1:0] pri_mask_nxt;  // 屏蔽下一值：本次授权位之上的所有位。
        logic         pri_mask_ena;  // 屏蔽更新使能：存在授权且被确认。
        logic [N-1:0] req_masked;    // 屏蔽后的请求：只保留上次授权者之后的请求。
        logic [N-1:0] gnt_masked;    // 屏蔽请求中的最低位。
        logic [N-1:0] gnt_unmasked;  // 全部请求中的最低位。
        logic [N-1:0] gnt_shl;       // 授权左移一位，最高位移出丢弃。

        // 候选授权：分别在屏蔽请求和全部请求中取最低的为1位。
        assign req_masked   = req & pri_mask_r;
        assign gnt_masked   = req_masked & (~(req_masked - ONE));
        assign gnt_unmasked = req & (~(req - ONE));

        // 最终授权：屏蔽后仍有请求则从上次授权者之后选；否则回绕到全部请求中最低位。
        assign gnt = (|req_masked) ? gnt_masked : gnt_unmasked;

        // 屏蔽更新：保留授权位之上的位；授权在最高位时左移结果为0，减1得全1，取反后屏蔽为0，
        // 下一轮从第0路开始。
        assign gnt_shl      = {gnt[N-2:0], 1'b0};
        assign pri_mask_nxt = ~(gnt_shl - ONE);
        assign pri_mask_ena = gnt_ack & (|req);

        // 优先级屏蔽寄存器：复位为0，即第0路优先；授权被确认时轮转。
        std_dfflr #(.DW(N)) u_pri_mask_dfflr (pri_mask_ena, pri_mask_nxt, pri_mask_r, clk, rst_n);
    end

endmodule

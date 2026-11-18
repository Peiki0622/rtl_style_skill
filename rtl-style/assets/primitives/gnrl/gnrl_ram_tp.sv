// =============================================================================
// 模块：gnrl_ram_tp
// 功能：两端口（一写一读）同步RAM行为模型，读写口独立地址、同一时钟，写口支持写掩码。
// 时序：wen为1的上升沿按wem把wdat写入waddr；ren为1的上升沿读出raddr处数据，下一拍
//       出现在rdat，并保持到下一次读操作。
// 读写冲突：同一拍读写同一地址时，本模型读出写入前的旧值；实际存储宏的冲突行为因
//       工艺而异，设计不得依赖该行为，须在上层避免或旁路。
// 实现：本模块是两端口存储宏的唯一替换点，项目应把模块体替换为编译器生成的存储宏并
//       保持端口与读延迟不变。存储阵列不复位，未写入地址读出X。
// =============================================================================
`include "std_defines.svh"

module gnrl_ram_tp #(
    parameter int DP = 256,  // 存储深度，单位为字；合法值不小于2。
    parameter int DW = 32,   // 字宽，单位为bit；必须能被MW整除。
    parameter int MW = 4     // 写掩码位数，每位控制DW/MW个bit；1表示整字写入。
) (
    // 时钟：读写口共用，所有操作在上升沿发生；存储阵列和读数据寄存器都不复位。
    input  wire                   clk,

    // 写口：wen为1时写入；wem第k位为1时写入wdat[k*DW/MW +: DW/MW]，为0时该段保持。
    input  wire                   wen,
    input  wire  [$clog2(DP)-1:0] waddr,
    input  wire  [MW-1:0]         wem,
    input  wire  [DW-1:0]         wdat,

    // 读口：ren为1的上升沿读出raddr处数据，rdat在下一拍有效并保持到下一次读操作。
    input  wire                   ren,
    input  wire  [$clog2(DP)-1:0] raddr,
    output logic [DW-1:0]         rdat
);

    localparam int LW = DW / MW;     // 每个写掩码位控制的位宽，DW不能被MW整除时为非法配置。

    logic [DW-1:0] mem_q [DP];  // 存储阵列行为模型，不复位。
    logic [DW-1:0] rd_dat;      // 按raddr组合选出的存储字，读使能时装入读数据寄存器。

    // 写操作：按写掩码逐段更新，未选中的段保持原值。
    always_ff @(posedge clk) begin : MEM_WR_PROC
        if (wen) begin
            for (int k = 0; k < MW; k = k + 1) begin
                if (wem[k]) begin
                    mem_q[waddr][k*LW +: LW] <= `STD_DLY wdat[k*LW +: LW];
                end
            end
        end
    end

    // 读操作：按读地址选出存储字，读使能的上升沿装入读数据寄存器，其余周期保持；
    // 同拍写入在该沿之后才更新存储阵列，不影响本次读出。
    assign rd_dat = mem_q[raddr];
    std_dffl #(.DW(DW)) u_rdat_dffl (ren, rd_dat, rdat, clk);

// synopsys translate_off
    // 参数检查：深度至少为2，字宽须能被掩码位数整除。
    initial begin : PARAM_CHECK_PROC
        if (DP < 2) begin
            $fatal(1, "gnrl_ram_tp: DP=%0d is illegal, must be >= 2 at %m", DP);
        end
        if ((MW < 1) || ((DW % MW) != 0)) begin
            $fatal(1, "gnrl_ram_tp: DW=%0d is not divisible by MW=%0d at %m", DW, MW);
        end
    end
// synopsys translate_on

endmodule

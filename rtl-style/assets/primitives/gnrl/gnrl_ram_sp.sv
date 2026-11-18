// =============================================================================
// 模块：gnrl_ram_sp
// 功能：单端口同步RAM行为模型，读写共用一个地址口，支持按写掩码分段写入。
// 时序：cs为1且we为1的上升沿按wem写入din；cs为1且we为0的上升沿读出addr处数据，
//       下一拍出现在dout，并保持到下一次读操作。写操作不改变dout。
// 实现：ASIC／FPGA流程中本模块是存储宏的唯一替换点，项目应把模块体替换为编译器生成的
//       SRAM或FPGA块RAM并保持端口与读延迟不变。存储阵列不复位，未写入地址读出X。
// =============================================================================
`include "std_defines.svh"

module gnrl_ram_sp #(
    parameter int DP = 256,  // 存储深度，单位为字；合法值不小于2。
    parameter int DW = 32,   // 字宽，单位为bit；必须能被MW整除。
    parameter int MW = 4     // 写掩码位数，每位控制DW/MW个bit；1表示整字写入。
) (
    // 时钟：所有操作在上升沿发生；存储阵列和读数据寄存器都不复位。
    input  wire                   clk,

    // 访问命令：cs为1时本拍有访问；we为1写、为0读；addr为字地址，须小于DP。
    input  wire                   cs,
    input  wire                   we,
    input  wire  [$clog2(DP)-1:0] addr,

    // 写数据：wem第k位为1时写入din[k*DW/MW +: DW/MW]，为0时该段保持原值；读操作忽略。
    input  wire  [MW-1:0]         wem,
    input  wire  [DW-1:0]         din,

    // 读数据：读操作的下一拍有效，之后保持到下一次读操作。
    output logic [DW-1:0]         dout
);

    localparam int LW = DW / MW;     // 每个写掩码位控制的位宽，DW不能被MW整除时为非法配置。

    logic [DW-1:0] mem_q [DP];  // 存储阵列行为模型，不复位。
    logic          rd_en;       // 读使能：片选有效且为读操作。
    logic [DW-1:0] rd_dat;      // 按addr组合选出的存储字，读使能时装入读数据寄存器。

    // 写操作：按写掩码逐段更新，未选中的段保持原值。
    always_ff @(posedge clk) begin : MEM_WR_PROC
        if (cs && we) begin
            for (int k = 0; k < MW; k = k + 1) begin
                if (wem[k]) begin
                    mem_q[addr][k*LW +: LW] <= `STD_DLY din[k*LW +: LW];
                end
            end
        end
    end

    // 读操作：按地址选出存储字，读命令的上升沿装入读数据寄存器，其余周期保持。
    assign rd_en  = cs & (~we);
    assign rd_dat = mem_q[addr];
    std_dffl #(.DW(DW)) u_dout_dffl (rd_en, rd_dat, dout, clk);

// synopsys translate_off
    // 参数检查：深度至少为2，字宽须能被掩码位数整除。
    initial begin : PARAM_CHECK_PROC
        if (DP < 2) begin
            $fatal(1, "gnrl_ram_sp: DP=%0d is illegal, must be >= 2 at %m", DP);
        end
        if ((MW < 1) || ((DW % MW) != 0)) begin
            $fatal(1, "gnrl_ram_sp: DW=%0d is not divisible by MW=%0d at %m", DW, MW);
        end
    end
// synopsys translate_on

endmodule

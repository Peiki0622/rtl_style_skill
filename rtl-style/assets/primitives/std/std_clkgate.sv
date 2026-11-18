// =============================================================================
// 模块：std_clkgate
// 功能：门控时钟单元（ICG）。clk_in为低时由锁存器采样使能，再与clk_in相与，
//       保证门控输出没有毛刺。test_mode为1时强制打开时钟，供扫描测试使用。
// 实现：ASIC流程中本模块是工艺ICG单元的唯一替换点，项目应把模块体替换为工艺库的
//       集成门控单元并保持端口不变；FPGA流程（定义STD_FPGA_SOURCE）直接透传时钟。
// 约束：FPGA透传时clock_en不起作用，被门控逻辑在时钟常开时也必须功能正确，即门控
//       只用于降低功耗，不承担功能上的保持作用。
// =============================================================================
`include "std_defines.svh"

module std_clkgate (
    // 输入时钟：被门控的源时钟。
    input  wire   clk_in,

    // 测试控制：test_mode为1时无条件打开时钟，扫描测试期间保持为1。
    input  wire   test_mode,

    // 门控使能：clk_in域信号，在clk_in低电平期间建立，为1时下一个高电平脉冲通过。
    input  wire   clock_en,

    // 输出时钟：门控后的时钟，只在使能锁存为1时输出clk_in的高电平脉冲。
    output logic  clk_out
);

`ifdef STD_FPGA_SOURCE
    // FPGA流程：不做门控，避免在通用逻辑上产生时钟；门控仅为功耗优化，不影响功能。
    assign clk_out = clk_in;
`else
    logic enb;  // 低电平透明锁存的门控使能，clk_in高电平期间保持稳定，避免输出毛刺。

    // 使能锁存：clk_in为低时透明，跟随测试模式与功能使能的或；clk_in为高时保持。
    always_latch begin : CLKGATE_LTCH_PROC
        if (!clk_in) begin
            enb <= clock_en | test_mode;
        end
    end

    // 时钟输出：锁存后的使能在clk_in高电平期间不变，与clk_in相与后输出完整脉冲。
    assign clk_out = enb & clk_in;
`endif

endmodule

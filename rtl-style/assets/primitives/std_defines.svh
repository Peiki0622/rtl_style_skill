// =============================================================================
// 文件：std_defines.svh
// 说明：std_／gnrl_原语库共用的编译宏开关，只定义宏，不包含任何硬件。
//
// 外部可定义的开关（均默认不定义）：
//   STD_SIM_DELAY         ：仅RTL仿真时定义，原语寄存器输出带#1延时，便于在波形中区分
//                           采样沿前后的值；综合、形式验证和门级流程禁止定义。
//                           #1为一个仿真时间单位：原语文件不写`timescale，须由编译选项统一
//                           指定（如VCS的-timescale=1ns/1ps），且最短时钟周期须大于该延时。
//   STD_FPGA_SOURCE       ：FPGA流程定义，std_clkgate退化为时钟直通，X检查断言不编译。
//   STD_DISABLE_ASSERTION ：关闭原语内置的X检查断言，例如仿真器不支持SVA时。
//
// 本文件内部派生的宏：
//   STD_DLY               ：原语寄存器非阻塞赋值使用的延时，定义STD_SIM_DELAY时为#1，否则为空。
// =============================================================================
`ifndef STD_DEFINES_SVH
`define STD_DEFINES_SVH

`ifdef STD_SIM_DELAY
    `define STD_DLY #1
`else
    `define STD_DLY
`endif

`endif

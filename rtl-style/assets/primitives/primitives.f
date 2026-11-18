// std_／gnrl_原语库文件列表。使用前设置环境变量STD_PRIM_ROOT为本文件所在目录，
// 例如：export STD_PRIM_ROOT=<项目>/rtl/common/primitives，然后
//   vcs -sverilog -timescale=1ns/1ps -f $STD_PRIM_ROOT/primitives.f <其他文件>
// 原语文件不写`timescale；测试平台或其他文件写了`timescale时，必须用-timescale统一指定默认值。
// 综合工具不读取本文件时，按相同顺序加入源文件，并把STD_PRIM_ROOT加入头文件搜索路径。
+incdir+${STD_PRIM_ROOT}

// 单元级原语
${STD_PRIM_ROOT}/std/std_xchecker.sv
${STD_PRIM_ROOT}/std/std_dff.sv
${STD_PRIM_ROOT}/std/std_dffr.sv
${STD_PRIM_ROOT}/std/std_dffrs.sv
${STD_PRIM_ROOT}/std/std_dffl.sv
${STD_PRIM_ROOT}/std/std_dfflr.sv
${STD_PRIM_ROOT}/std/std_dfflrs.sv
${STD_PRIM_ROOT}/std/std_ltch.sv
${STD_PRIM_ROOT}/std/std_clkgate.sv
${STD_PRIM_ROOT}/std/std_clk_mux2.sv
${STD_PRIM_ROOT}/std/std_sync.sv
${STD_PRIM_ROOT}/std/std_rst_sync.sv
${STD_PRIM_ROOT}/std/std_pulse_sync.sv

// 通用功能块
${STD_PRIM_ROOT}/gnrl/gnrl_pipe_stage.sv
${STD_PRIM_ROOT}/gnrl/gnrl_fifo.sv
${STD_PRIM_ROOT}/gnrl/gnrl_bypbuf.sv
${STD_PRIM_ROOT}/gnrl/gnrl_cdc_tx.sv
${STD_PRIM_ROOT}/gnrl/gnrl_cdc_rx.sv
${STD_PRIM_ROOT}/gnrl/gnrl_async_fifo.sv
${STD_PRIM_ROOT}/gnrl/gnrl_rr_arb.sv
${STD_PRIM_ROOT}/gnrl/gnrl_ram_sp.sv
${STD_PRIM_ROOT}/gnrl/gnrl_ram_tp.sv

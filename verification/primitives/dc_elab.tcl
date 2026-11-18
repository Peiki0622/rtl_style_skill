# =============================================================================
# 原语库DC可综合性检查：逐个分析并展开std_／gnrl_原语，检查推断出的存储单元类型。
# 用法：在任务目录中执行
#   STD_PRIM_ROOT=<原语库目录> dc_shell -f <本文件>
# 只使用GTECH展开，不需要工艺库；结果用于确认可综合、推断的触发器／锁存器类型
# 和是否出现意外锁存器，不代表时序或面积结论。
# =============================================================================
set prim_root $env(STD_PRIM_ROOT)

set_app_var search_path [concat [list $prim_root] $search_path]
set_app_var hdlin_infer_multibit default_none
set_app_var target_library ""
set_app_var link_library "*"
define_design_lib WORK -path ./WORK

# 与primitives.f保持相同顺序。
set prim_files [list \
    std/std_xchecker.sv \
    std/std_dff.sv \
    std/std_dffr.sv \
    std/std_dffrs.sv \
    std/std_dffl.sv \
    std/std_dfflr.sv \
    std/std_dfflrs.sv \
    std/std_ltch.sv \
    std/std_clkgate.sv \
    std/std_clk_mux2.sv \
    std/std_sync.sv \
    std/std_rst_sync.sv \
    std/std_pulse_sync.sv \
    gnrl/gnrl_pipe_stage.sv \
    gnrl/gnrl_fifo.sv \
    gnrl/gnrl_bypbuf.sv \
    gnrl/gnrl_cdc_tx.sv \
    gnrl/gnrl_cdc_rx.sv \
    gnrl/gnrl_async_fifo.sv \
    gnrl/gnrl_rr_arb.sv \
    gnrl/gnrl_ram_sp.sv \
    gnrl/gnrl_ram_tp.sv \
]

set full_paths [list]
foreach f $prim_files {
    lappend full_paths [file join $prim_root $f]
}

if {![analyze -format sverilog $full_paths]} {
    echo "PRIM_DC_RESULT: FAIL analyze"
    quit
}

# 每项为“顶层 参数字符串”；空参数表示默认参数，其余覆盖边界配置。
set elab_list [list \
    [list std_dff        ""] \
    [list std_dffr       "DW=>4,RST_VAL=>4'hA"] \
    [list std_dffrs      ""] \
    [list std_dffl       ""] \
    [list std_dfflr      "DW=>4,RST_VAL=>4'h5"] \
    [list std_dfflrs     ""] \
    [list std_ltch       ""] \
    [list std_clkgate    ""] \
    [list std_clk_mux2   ""] \
    [list std_sync       "DP=>3,DW=>2"] \
    [list std_rst_sync   ""] \
    [list std_pulse_sync ""] \
    [list gnrl_pipe_stage "DP=>1,CUT_READY=>0"] \
    [list gnrl_pipe_stage "DP=>1,CUT_READY=>1"] \
    [list gnrl_pipe_stage "DP=>0"] \
    [list gnrl_fifo      "DP=>4,MSKO=>1"] \
    [list gnrl_fifo      "DP=>1,CUT_READY=>1"] \
    [list gnrl_fifo      "DP=>2"] \
    [list gnrl_fifo      "DP=>0"] \
    [list gnrl_bypbuf    ""] \
    [list gnrl_cdc_tx    ""] \
    [list gnrl_cdc_rx    ""] \
    [list gnrl_async_fifo ""] \
    [list gnrl_async_fifo "DP=>2"] \
    [list gnrl_rr_arb    ""] \
    [list gnrl_rr_arb    "N=>1"] \
    [list gnrl_ram_sp    "DP=>16,DW=>16,MW=>2"] \
    [list gnrl_ram_tp    "DP=>16,DW=>16,MW=>2"] \
]

set fail_cnt 0
foreach item $elab_list {
    set top   [lindex $item 0]
    set param [lindex $item 1]
    echo "PRIM_DC_ELAB: $top ($param)"
    if {$param eq ""} {
        set ok [elaborate $top]
    } else {
        set ok [elaborate $top -parameters $param]
    }
    if {!$ok} {
        echo "PRIM_DC_RESULT: FAIL elaborate $top ($param)"
        incr fail_cnt
        continue
    }
    current_design [get_object_name [current_design]]
    link
    check_design -summary
}

if {$fail_cnt == 0} {
    echo "PRIM_DC_RESULT: PASS"
} else {
    echo "PRIM_DC_RESULT: FAIL $fail_cnt"
}
quit

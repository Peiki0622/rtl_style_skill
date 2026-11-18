#!/usr/bin/env python3
# =============================================================================
# 原语库变异检查：逐个向原语副本注入典型错误，确认对应测试平台能够发现。
# 每个变异只改一处，编译运行对应测试平台；测试平台报告PASS即视为漏检。
# 用法：verification/primitives/run_mutation.py [输出目录]
#   输出目录默认 runs/verification/primitives/mutation_<时间戳>，不覆盖旧结果。
# =============================================================================
import os
import shutil
import subprocess
import sys
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PRIM = os.path.join(REPO, "rtl-style", "assets", "primitives")
TB_DIR = os.path.join(REPO, "verification", "primitives")

# (名称, 文件, 原文本, 替换文本, 测试平台)
MUTATIONS = [
    ("dfflr_ignore_rst_val", "std/std_dfflr.sv",
     "qout <= RST_VAL;", "qout <= '0;", "tb_std_prims"),
    ("dffl_ignore_lden", "std/std_dffl.sv",
     "if (lden) begin", "if (1'b1) begin", "tb_std_prims"),
    ("clkgate_no_latch", "std/std_clkgate.sv",
     "assign clk_out = enb & clk_in;", "assign clk_out = (clock_en | test_mode) & clk_in;", "tb_std_prims"),
    ("rst_sync_one_stage", "std/std_rst_sync.sv",
     "rst_n_a : rst_sync_q[DP-1];", "rst_n_a : rst_sync_q[0];", "tb_std_prims"),
    ("pulse_sync_rise_only", "std/std_pulse_sync.sv",
     "assign dst_pulse = dst_tgl_sync ^ dst_tgl_q;", "assign dst_pulse = dst_tgl_sync & (~dst_tgl_q);", "tb_std_prims"),
    ("pipe_cut_not_cut", "gnrl/gnrl_pipe_stage.sv",
     "assign i_rdy = ~vld_q;", "assign i_rdy = (~vld_q) | vld_clr;", "tb_gnrl_stream"),
    ("fifo_dp1_nocut_drop_ren", "gnrl/gnrl_fifo.sv",
     "assign i_rdy = (~fifo_full) | ren;", "assign i_rdy = ~fifo_full;", "tb_gnrl_stream"),
    ("fifo_cnt_en_or", "gnrl/gnrl_fifo.sv",
     "assign cnt_vec_en = wen ^ ren;", "assign cnt_vec_en = wen | ren;", "tb_gnrl_stream"),
    ("fifo_bit35_stuck0", "gnrl/gnrl_fifo.sv",
     "assign o_dat = mux_rdat;", "assign o_dat = mux_rdat & (~(DW'(1) << 35));", "tb_gnrl_stream"),
    ("bypbuf_input_priority", "gnrl/gnrl_bypbuf.sv",
     "assign o_dat = fifo_o_vld ? fifo_o_dat : i_dat;", "assign o_dat = i_vld ? i_dat : fifo_o_dat;", "tb_gnrl_stream"),
    ("async_fifo_full_no_invert", "gnrl/gnrl_async_fifo.sv",
     "assign full_cmp = {~rptr_gray_wsync[PW-1:PW-2], rptr_gray_wsync[PW-3:0]};",
     "assign full_cmp = {rptr_gray_wsync[PW-1], ~rptr_gray_wsync[PW-2], rptr_gray_wsync[PW-3:0]};", "tb_gnrl_cdc"),
    ("cdc_rx_ignore_buf_rdy", "gnrl/gnrl_cdc_rx.sv",
     "assign i_rdy_set = buf_rdy & i_vld_sync & (~i_rdy_q);", "assign i_rdy_set = i_vld_sync & (~i_rdy_q);", "tb_gnrl_cdc"),
    ("rr_arb_mask_includes_self", "gnrl/gnrl_rr_arb.sv",
     "assign pri_mask_d   = ~(gnt_shl - ONE);", "assign pri_mask_d   = ~(gnt - ONE);", "tb_gnrl_misc"),
    ("ram_tp_write_first", "gnrl/gnrl_ram_tp.sv",
     "assign rd_dat = mem_q[raddr];",
     "assign rd_dat = (wen && (waddr == raddr) && (&wem)) ? wdat : mem_q[raddr];",
     "tb_gnrl_misc"),
]


def main():
    out_dir = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(
        REPO, "runs", "verification", "primitives", "mutation_" + time.strftime("%Y%m%d_%H%M%S"))
    if os.path.exists(out_dir):
        print("输出目录已存在，拒绝覆盖：" + out_dir, file=sys.stderr)
        return 1
    os.makedirs(out_dir)
    escaped = 0
    lines = []
    for name, rel, old, new, tb in MUTATIONS:
        work = os.path.join(out_dir, name)
        prim = os.path.join(work, "primitives")
        shutil.copytree(PRIM, prim)
        path = os.path.join(prim, rel)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if text.count(old) != 1:
            lines.append("%-30s SKIP(pattern count=%d)" % (name, text.count(old)))
            escaped += 1
            continue
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace(old, new))
        env = dict(os.environ, STD_PRIM_ROOT=prim)
        cmd = ("vcs -full64 -sverilog -timescale=1ns/1ps -f {p}/primitives.f {tb} -top {top} "
               "-o simv -l compile.log > /dev/null 2>&1 && ./simv +ntb_random_seed=1 -l sim.log > /dev/null 2>&1"
               ).format(p=prim, tb=os.path.join(TB_DIR, tb + ".sv"), top=tb)
        try:
            subprocess.run(cmd, shell=True, cwd=work, env=env, timeout=1800)
        except subprocess.TimeoutExpired:
            # 超时说明变异导致仿真挂死，测试平台未能给出结论，按漏检处理。
            escaped += 1
            lines.append("%-30s ERROR   (timeout, see %s)" % (name, work))
            continue
        sim_log = os.path.join(work, "sim.log")
        if not os.path.exists(sim_log):
            # 编译失败不能证明测试平台发现了错误，按漏检处理。
            escaped += 1
            lines.append("%-30s ERROR   (compile failed, see %s)" % (name, work))
            continue
        with open(sim_log, encoding="utf-8", errors="replace") as f:
            passed = "TB_RESULT: PASS" in f.read()
        if passed:
            escaped += 1
            lines.append("%-30s ESCAPED (%s passed)" % (name, tb))
        else:
            lines.append("%-30s KILLED  (%s)" % (name, tb))
    with open(os.path.join(out_dir, "summary.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("summary: " + os.path.join(out_dir, "summary.txt"))
    return 1 if escaped else 0


if __name__ == "__main__":
    sys.exit(main())

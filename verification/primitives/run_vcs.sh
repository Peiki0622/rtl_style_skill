#!/usr/bin/env bash
# =============================================================================
# 原语库VCS回归：每个测试平台分别在“无仿真延时”和“定义STD_SIM_DELAY”两种模式下编译运行，
# 另跑X检查负向测试：lden注入X（预期std_xchecker终止）和锁存器使能为Z（预期std_ltch终止）。
# 用法：verification/primitives/run_vcs.sh [输出目录]
#   输出目录默认 runs/verification/primitives/<时间戳>，不覆盖旧结果。
# =============================================================================
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tb_dir="${repo_root}/verification/primitives"
export STD_PRIM_ROOT="${repo_root}/rtl-style/assets/primitives"
out_dir="${1:-${repo_root}/runs/verification/primitives/$(date +%Y%m%d_%H%M%S)}"
seed="${SEED:-1}"

if [ -e "${out_dir}" ]; then
    echo "输出目录已存在，拒绝覆盖：${out_dir}" >&2
    exit 1
fi
mkdir -p "${out_dir}"

summary="${out_dir}/summary.txt"
{
    echo "date: $(date -Iseconds)"
    echo "vcs: $(vcs -ID 2>/dev/null | grep -m1 -i 'version' || echo unknown)"
    echo "seed: ${seed}"
    echo "prim_root: ${STD_PRIM_ROOT}"
} > "${summary}"

fail=0

# run_one <名称> <顶层> <测试平台文件> <期望：pass|fatal:<日志中须出现的文本>> [额外编译选项...]
run_one() {
    local name="$1"
    local top="$2"
    local tb_file="$3"
    local expect="$4"
    shift 4
    local work="${out_dir}/${name}"
    mkdir -p "${work}"
    (
        cd "${work}" || exit 1
        vcs -full64 -sverilog -timescale=1ns/1ps \
            -f "${STD_PRIM_ROOT}/primitives.f" "${tb_file}" -top "${top}" \
            "$@" -o simv -l compile.log > /dev/null 2>&1
        if [ ! -x simv ]; then
            exit 2
        fi
        ./simv +ntb_random_seed="${seed}" -l sim.log > /dev/null 2>&1
        exit 0
    )
    local rc=$?
    local result
    if [ "${rc}" -ne 0 ]; then
        result="FAIL(compile)"
    elif [ "${expect}" = "pass" ]; then
        if grep -q "^TB_RESULT: PASS" "${work}/sim.log" && ! grep -q "^Error-" "${work}/sim.log"; then
            result="PASS"
        else
            result="FAIL"
        fi
    else
        if grep -q "${expect#fatal:}" "${work}/sim.log" && ! grep -q "^TB_RESULT: PASS" "${work}/sim.log"; then
            result="PASS(expected fatal)"
        else
            result="FAIL(no xcheck fatal)"
        fi
    fi
    case "${result}" in
        PASS*) ;;
        *) fail=1 ;;
    esac
    printf '%-32s %s\n' "${name}" "${result}" | tee -a "${summary}"
}

for tb in tb_std_prims tb_gnrl_stream tb_gnrl_cdc tb_gnrl_misc; do
    run_one "${tb}_nodly" "${tb}" "${tb_dir}/${tb}.sv" pass
    run_one "${tb}_simdly" "${tb}" "${tb_dir}/${tb}.sv" pass +define+STD_SIM_DELAY
done
run_one "tb_std_prims_xcheck_neg" tb_std_prims "${tb_dir}/tb_std_prims.sv" \
    "fatal:std_xchecker: X/Z value detected" +define+TB_XCHECK_NEG
run_one "tb_std_prims_ltch_z_neg" tb_std_prims "${tb_dir}/tb_std_prims.sv" \
    "fatal:std_ltch: X/Z value detected" +define+TB_LTCH_Z_NEG

echo "summary: ${summary}"
exit "${fail}"

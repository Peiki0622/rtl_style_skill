#!/usr/bin/env bash
# =============================================================================
# 原语库DC展开检查：在独立输出目录中运行dc_elab.tcl，并汇总结果。
# 用法：verification/primitives/run_dc.sh [输出目录]
#   输出目录默认 runs/verification/primitives/dc_<时间戳>，不覆盖旧结果。
# 判定：所有配置展开成功；锁存器只出现在std_ltch和std_clkgate中；check_design没有
#       多驱动、无驱动、未解析引用或组合环。
# =============================================================================
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export STD_PRIM_ROOT="${repo_root}/rtl-style/assets/primitives"
out_dir="${1:-${repo_root}/runs/verification/primitives/dc_$(date +%Y%m%d_%H%M%S)}"

if [ -e "${out_dir}" ]; then
    echo "输出目录已存在，拒绝覆盖：${out_dir}" >&2
    exit 1
fi
mkdir -p "${out_dir}"
out_dir="$(cd "${out_dir}" && pwd)"

(
    cd "${out_dir}" || exit 1
    dc_shell -f "${repo_root}/verification/primitives/dc_elab.tcl" > dc.log 2>&1
)

summary="${out_dir}/summary.txt"
{
    echo "date: $(date -Iseconds)"
    grep -m1 -E "^ *Version" "${out_dir}/dc.log" || echo "dc version: unknown"
    grep -E "^PRIM_DC_RESULT" "${out_dir}/dc.log" || echo "PRIM_DC_RESULT: MISSING"
    echo "latches (design :: register):"
    awk '/^PRIM_DC_ELAB/{top=$2} /\| Latch/{print "  " top " :: " $2}' "${out_dir}/dc.log"
    echo "check_design lint categories (design :: item count):"
    awk '/^PRIM_DC_ELAB/{top=$2 " " $3} /\(LINT-[0-9]+\) +[0-9]+ *$/{print "  " top " :: " $0}' "${out_dir}/dc.log" | sed 's/  */ /g'
} > "${summary}"
cat "${summary}"

if ! grep -q "^PRIM_DC_RESULT: PASS" "${out_dir}/dc.log"; then
    exit 1
fi
if awk '/^PRIM_DC_ELAB/{top=$2} /\| Latch/{print top}' "${out_dir}/dc.log" | grep -v -E "^(std_ltch|std_clkgate)$" | grep -q .; then
    echo "unexpected latch found" >&2
    exit 1
fi
# 严重的check_design问题：多驱动、无驱动、未解析引用和组合环必须为0。
if grep -E "\(LINT-[0-9]+\) +[0-9]+ *$" "${out_dir}/dc.log" | grep -i -E "multiple driver|no driver|unresolved|loop" | grep -q .; then
    echo "serious check_design issue found" >&2
    exit 1
fi
echo "summary: ${summary}"

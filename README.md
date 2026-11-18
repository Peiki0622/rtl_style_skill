# RTL Style Skill

面向 Codex 的 Verilog / SystemVerilog 编码与审阅技能，侧重工业界常用的原语化寄存器写法、清楚的硬件职责划分、严格排版和中文时序注释。

A Codex skill for Verilog/SystemVerilog RTL writing and review, with a bundled std_/gnrl_ primitive library (DFF family, synchronizers, clock gate, reset sync, pipe stage, FIFOs, CDC, arbiter, RAM), explicit blocks, one port per line, three-part FSMs, and detailed Chinese comments.

## 适用范围

适用于编写、修改、重构、排版和审阅 RTL 及相关测试平台。主要约束包括：

- 参与综合的逻辑中不写时序过程块，每个寄存器都例化 `std_dff*` 原语，按 `xxx_q`（当前值）、`xxx_d`（下一值）、`xxx_en`（更新使能）命名；同步器、复位同步、门控时钟、FIFO、跨时钟域和 RAM 都使用自带的 `std_／gnrl_` 原语库。不参与综合的检查代码（`translate_off` 或 `` `ifndef SYNTHESIS `` 内）可以使用 `always_ff`。
- 所有条件分支使用 `begin/end`，采用 4 空格缩进。
- 端口、参数和例化连接逐项分行，接口按实际功能分组；`std_dff*` 和 `std_ltch` 原语采用单行位置例化。
- 例化端口连接中不直接写逻辑表达式，先用具名组合信号计算再连接，便于 Verdi 追踪。
- 参数、派生常量和参数覆盖项附中文用途说明。
- 状态机按状态寄存器（原语实例）、下一状态计算、输出译码划分职责；状态用 `typedef enum` 声明，原语输出经同宽 `logic` 向量显式转换为枚举。
- 状态声明和转移注释说明真实行为、握手条件与周期关系。
- 可综合 RTL 不使用用户自定义 `function`；测试平台可按需使用。
- 风格整理保持原有功能、接口和时序，按变更范围完成验证。

这些是本技能的风格选择，不是 SystemVerilog 语言的通用限制。技能不负责纯文字规格书，也不用于批量重排第三方库或生成网表。它不是自动格式化器或逻辑等价验证工具。

## 文件结构

```text
rtl_style_skill/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── rtl-style/
│   ├── SKILL.md                     # 技能入口与完整约束
│   ├── agents/openai.yaml           # 界面元数据与自动选择策略
│   ├── references/
│   │   ├── style-examples.md        # 排版与三段式状态机示例
│   │   └── primitives.md            # 原语库部署、目录、选型与例化写法
│   └── assets/primitives/           # 随技能分发的原语库源码
│       ├── std_defines.svh          # 宏开关：STD_SIM_DELAY、STD_FPGA_SOURCE、STD_DISABLE_ASSERTION
│       ├── primitives.f             # 仿真文件列表（使用 STD_PRIM_ROOT）
│       ├── std/                     # 单元级原语：DFF族、锁存器、ICG、时钟MUX、同步器、复位同步、脉冲同步、X检查
│       └── gnrl/                    # 通用功能块：pipe_stage、fifo、bypbuf、cdc_tx/rx、async_fifo、rr_arb、ram_sp/tp
└── verification/primitives/         # 原语自检：测试平台、VCS回归、DC展开与变异检查脚本（不随技能安装）
```

## 安装

本技能包含 Markdown、YAML 和随技能分发的原语库 SystemVerilog 源码，安装只需复制目录，无需 EDA 软件。执行 RTL 编译、仿真或综合时，仍需项目自己的工具环境。

在 Bash 中运行：

```bash
git clone https://github.com/Peiki0622/rtl_style_skill.git
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
# 如果已有同名技能，先比较并备份自己的修改；以下命令遇到已有目录会停止。
(
    set -e
    destination="${CODEX_HOME:-$HOME/.codex}/skills/rtl-style"
    if [ -e "$destination" ]; then
        echo "目标技能已存在，请先比较并备份：$destination" >&2
        exit 1
    fi
    cp -R rtl_style_skill/rtl-style "$destination"
)
```

若网络环境要求代理，请按自己的网络配置访问 GitHub。仓库不包含个人代理或 SSH 配置。

## 使用

在支持技能的 Codex 环境中显式调用 `$rtl-style`，例如：

```text
请使用 $rtl-style 整理当前模块和对应测试平台的端口、参数注释与状态机注释。
保持接口、状态编码和逐周期行为不变，按项目要求验证并报告结果。
```

技能允许自动选择；用户明确指令优先。完整规则见 [SKILL.md](rtl-style/SKILL.md)，需要具体写法时阅读 [风格示例](rtl-style/references/style-examples.md)。示例中的状态数和报告周期仅属于示例协议。

## 原语库

| 类别 | 原语 |
|---|---|
| 寄存器／锁存器 | `std_dff`、`std_dffr`、`std_dffrs`、`std_dffl`、`std_dfflr`、`std_dfflrs`、`std_ltch` |
| 时钟／复位 | `std_clkgate`、`std_clk_mux2`、`std_rst_sync` |
| 跨时钟域 | `std_sync`、`std_pulse_sync`、`gnrl_cdc_tx`、`gnrl_cdc_rx`、`gnrl_async_fifo` |
| 流控／缓冲 | `gnrl_pipe_stage`、`gnrl_fifo`、`gnrl_bypbuf` |
| 仲裁／存储 | `gnrl_rr_arb`、`gnrl_ram_sp`、`gnrl_ram_tp` |
| 仿真检查 | `std_xchecker` |

原语划分和若干结构（DFF 族命名、`set/clr/ena/nxt` 写法、独热指针 FIFO、四相握手 CDC）参考了 [riscv-mcu/e203_hbirdv2](https://github.com/riscv-mcu/e203_hbirdv2)（Apache-2.0）的 `rtl/e203/general`，源码按本技能风格重新编写，并增加了 `RST_VAL` 参数、`STD_SIM_DELAY` 宏控制的仿真延时、异步 FIFO、脉冲同步、复位同步、轮询仲裁和 RAM 模型。部署与使用见 [primitives.md](rtl-style/references/primitives.md)。

## 维护与验证

修改时同步检查技能规则与示例，确认相对链接有效、YAML 可解析，并按实际 RTL 变更运行项目检查。技能结构校验不代表生成 RTL 已通过仿真、综合或等价验证。

修改原语库后运行自检（需要 VCS 和 Design Compiler，输出在被 Git 忽略的 `runs/` 下，不覆盖旧结果）：

```bash
# VCS 回归：4 个测试平台 × {无延时, STD_SIM_DELAY}，外加 X 检查负向测试
verification/primitives/run_vcs.sh

# DC 展开：确认可综合，且只在 std_ltch／std_clkgate 中推断锁存器
verification/primitives/run_dc.sh

# 变异检查：逐个注入典型错误，确认测试平台全部能发现
verification/primitives/run_mutation.py
```

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

本仓库采用 [MIT License](LICENSE)。

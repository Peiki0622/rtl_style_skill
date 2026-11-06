# RTL Style Skill

面向 Codex 的 Verilog / SystemVerilog 编码与审阅技能，侧重清楚的硬件职责划分、严格排版和中文时序注释。

A Codex skill for Verilog/SystemVerilog RTL writing and review, with explicit blocks, one port per line, three-part FSMs, and detailed Chinese comments.

## 适用范围

适用于编写、修改、重构、排版和审阅 RTL 及相关测试平台。主要约束包括：

- 所有条件分支使用 `begin/end`，采用 4 空格缩进。
- 端口、参数和例化连接逐项分行，接口按实际功能分组。
- 参数、派生常量和参数覆盖项附中文用途说明。
- 状态机按状态寄存器、下一状态计算、输出译码划分职责。
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
└── rtl-style/
    ├── SKILL.md                     # 技能入口与完整约束
    ├── agents/openai.yaml           # 界面元数据与自动选择策略
    └── references/style-examples.md # 排版与三段式状态机示例
```

## 安装

本技能仅包含 Markdown 和 YAML，无需 EDA 软件即可安装。执行 RTL 编译、仿真或综合时，仍需项目自己的工具环境。

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

## 维护与验证

修改时同步检查技能规则与示例，确认相对链接有效、YAML 可解析，并按实际 RTL 变更运行项目检查。技能结构校验不代表生成 RTL 已通过仿真、综合或等价验证。

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

本仓库采用 [MIT License](LICENSE)。

# 贡献指南

欢迎通过 Issue 反馈规则歧义，或通过 Pull Request 提交改进。

- 说明修改解决的具体问题，必要时给出最小 RTL 片段和预期行为。
- 规则修改放在 `rtl-style/SKILL.md`，对应示例放在 `rtl-style/references/style-examples.md`，原语说明放在 `rtl-style/references/primitives.md`，避免重复维护完整规则。
- 修改或新增 `rtl-style/assets/primitives/` 中的原语时，保持 `std_／gnrl_` 前缀、固定端口顺序、X 检查与宏开关约定，同步更新 `primitives.f`、`primitives.md` 和 `verification/primitives/` 中的测试，并说明 `run_vcs.sh`、`dc_elab.tcl`、`run_mutation.py` 的实际结果。
- 保留技能的适用范围；风格调整不应隐式改变接口、状态编码或输出周期。
- 检查 Markdown 链接与 YAML 格式。若修改完整 RTL 示例，说明实际执行的编译或仿真检查；片段应清楚标明其用途。
- 不提交密钥、个人环境配置、未获授权的设计、PDK、第三方网表、波形、仿真数据库或日志。

提交贡献表示你有权以本仓库 MIT 许可证提供该内容。

# DST Agent Skills

45 个面向 **Don't Starve Together (DST) 模组开发**的 Agent Skill 集合 —— 覆盖 Prefab / Component / Brain / StateGraph / Action / 网络 / 存档 / 世界生成 / UI / 资源管线等全部领域。

45 Agent Skills for **Don't Starve Together (DST) mod development** — prefabs, components, brains, stategraphs, actions, networking, persistence, worldgen, UI, and asset pipelines.

兼容 **Claude Code**、Codex、Cursor、Gemini CLI 等支持 [Agent Skills 规范](https://agentskills.io) 的智能体，通过 [`skills.sh`](https://skills.sh) 生态（`npx skills`）安装扩展。

Works with Claude Code, Codex, Cursor, Gemini CLI and other agents following the [Agent Skills spec](https://agentskills.io).

## 安装 / Install

```bash
# 全部安装到全部已检测到的智能体
npx skills add <owner>/<repo> --all

# 只装到 Claude Code
npx skills add <owner>/<repo> --skill '*' -a claude-code

# 只装指定技能
npx skills add <owner>/<repo> --skill dst-component-authoring --skill dst-networking-rpc
```

## 结构 / Layout

```
└── dst-* / 45 个技能，每个目录一个 SKILL.md
    ├── SKILL.md        —— 触发条件 + 工作流 + 不变量 + 验证
    ├── references/     —— 详细契约文档（按需读取）
    ├── assets/         —— 可复制模板（lua / shader 等）
    └── scripts/        —— 确定性脚本（快照、扫描等）
```

每个 `SKILL.md` 的 description 均以「触发优先 + 中文触发词 + 代码信号」组织，降低相似技能之间的选择歧义。

## 使用约定

- **技能按需调用**：模型只在匹配触发条件时加载对应技能（部分技能的 description 含中文触发词与专属信号，帮助命中）。
- **源码基线**：技能默认以 `data/scripts` 为只读参考，可修改默认路径；所有改动应落在用户指定的 Mod 目录。
- **中文/英文混合**：说明文字为中文，代码标识符保持原样；交互语言由智能体语言设置决定。
- **`/dst` 命令（可选）**：本仓库附带 `/.claude/commands/dst.md`——一个 Claude Code 分发入口，你只需输入 `/dst <任务>`，模型自动挑对技能。该文件是 Claude Code 专用命令，不影响其他智能体，也不会被本仓库的技能发现逻辑误读（已验证只发现 45 个技能）。

## 继承说明 / Notes

本仓库由 `Downloads/饥荒模组SKILLS`（Codex 版本）迁移而来：

- 删除了 Codex 专用的 `agents/openai.yaml` 残留。
- 重写了全部 45 个 `description` 为「`Use when … + 中文触发 + 信号」触发优先格式。
- 全部通过 `npx skills add <本目录> --list` 验证（45/45 可发现）。

Skills are installed on-demand by description triggers designed to be mutually exclusive. Source root defaults to `D:\steam\steamapps\common\Don't Starve Together\data\scripts` (top-left adjustable per skill); all changes should land in your target Mod directory.

## 使用示例

```bash
# 搜技能
npx skills find dst --owner <owner>

# 不安装直接用
npx skills use <owner>/<repo> --skill dst-stategraph-authoring
```

## License / 许可

本仓库以 **GNU General Public License v3.0 或更高版本** 授权（**SPDX: GPL-3.0-or-later**）。

- 完整协议文本见根目录 [`LICENSE`](./LICENSE)，版权声明见 [`COPYING`](./COPYING) 与 [`NOTICE`](./NOTICE)。
- 本仓库为作者自有作品：含 SKILL.md、参考模板与辅助脚本，不含第三方受许可保护的游戏素材，也不包含任何来自 Don't Starve Together / Klei 的受许可代码或数据。
- 以 GPL-3.0-or-later 发布意味着：你可以自由使用、修改与再分发，但基于本仓库的衍生作品必须以相同许可证发布。

This repository is licensed under the **GNU GPL v3.0-or-later** (SPDX: GPL-3.0-or-later). See [`LICENSE`](./LICENSE), [`COPYING`](./COPYING) and [`NOTICE`](./NOTICE). The content is the author's own work and contains no third-party or game-licensed assets; derivative works must be licensed under the same terms.
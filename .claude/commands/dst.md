---
description: 分发到对应的 DST 模组技能（dst-*）
---

<!--
  不要看上我的菊 Agent Skills — /dst 分发命令
  Original author: alt

  This command file is part of the 不要看上我的菊 Agent Skills package,
  licensed under the GNU General Public License v3.0-or-later (SPDX:
  GPL-3.0-or-later). See the LICENSE file in the repository root.

  本命令文件是 不要看上我的菊 Agent Skills 发布包的一部分，
  以 GNU GPL v3.0 或更高版本（SPDX: GPL-3.0-or-later）授权，全文见仓库根目录 LICENSE。
-->

用户执行了 /dst，任务内容：$ARGUMENTS

这是 DST 模组开发任务。**必须按下述流程执行，禁止跳过或简化任何一步。**

> 若任务内容为空，先让用户补充具体任务再分发，不要自行臆造任务。

## 硬性要求（先读这里）

1. **必须调用 Skill 工具**，加载与本任务最匹配的 **1-2 个技能**（精确全名，如 `dst-component-authoring`）。**加载技能之后才能回答**——禁止仅凭下面的目录描述直接作答。
2. **加载自检**：加载后确认该技能 SKILL.md 正文（尤其「工作流」章节）已进入上下文；若未见正文，视为加载失败，先重新加载再继续，禁止凭目录行直接执行。
3. 拿不准匹配哪个时，加载 `dst-source-research` 兜底，不要空想。
4. 加载后，严格按该技能 SKILL.md 的「工作流 → 源码锚点 → 不变量 → 验证」执行；references/、assets/、scripts/ 按需使用。
5. 以当前安装的 DST 源码 `D:\steam\steamapps\common\Don't Starve Together\data\scripts` 为事实依据。
6. 修改只落在用户指定的 Mod 目录，不改游戏源码。
7. 完成后按所选技能的要求验证，并说明用了哪些技能。

> **例外**：`modtool-automation` 是工具链技能，不属于 DST 源码范畴，无需源码锚点验证；其执行依据为 SKILL.md 中的「接口锚点 → 不变量 → 验证」。

## 第一步：分发

根据下面的技能目录，调用 Skill 工具加载对应**精确全名**。只加载真正相关的，不要贪多。

## 技能目录（按触发关键词匹配）

### 核心基础
- dst-source-research — 查源码、追踪调用链、验证原版契约（信号：data/scripts、rg、modutil.lua）
- dst-mod-scaffolding — 新建模组、modinfo、入口、目录结构、配置文件
- dst-lua-runtime — Lua 环境、GLOBAL、require/modimport、闭包、Class 继承
- dst-hooking-compatibility — PostInit/PostConstruct 钩子、方法包装、多模组兼容
- dst-prefab-authoring — Prefab、实体构造、SetPristine、主客机分支
- dst-component-authoring — Component、Replica、生命周期、OnSave/OnLoad、组件动作
- dst-events-tasks-lifecycle — ListenForEvent、DoTaskInTime/DoPeriodicTask、回调清理、定时器
- dst-networking-rpc — netvar、Replica、AddModRPCHandler/AddClientModRPCHandler/AddShardModRPCHandler、不同步
- dst-persistence-migration — OnSave/OnLoad/LoadPostPass/LongUpdate、存档迁移、回滚
- dst-action-authoring — AddAction、AddComponentAction、BufferedAction、ActionHandler、动作不执行
- dst-stategraph-authoring — State、EventHandler/TimeEvent/ActionHandler、攻击/卡动画、预测
- dst-brain-authoring — Brain、行为树、PriorityNode、寻敌/跟随/游荡
- dst-debugging-testing — 报错/崩溃/nil/堆栈/不同步、最小复现、回归测试
- dst-api-update-diff — 游戏更新后的 API 差异、兼容性评估、快照对比

### 玩法
- dst-inventory-equipment-containers — 物品、装备、耐久、燃料、容器、背包
- dst-combat-weapons-projectiles — 战斗、武器、护甲、位面伤害、投射物、范围攻击
- dst-creature-boss-authoring — 整只生物/Boss 的跨系统编排（Prefab+Brain+SG+战斗+掉落）
- dst-character-authoring — 可玩角色的跨系统编排（属性+台词+立绘+专属机制）
- dst-skilltree-authoring — 角色技能树、节点、解锁、激活回调
- dst-crafting-tech-prototypers — 配方、科技、制作站、解锁条件
- dst-food-cooking — 食物、料理、锅、食谱书、香料
- dst-building-deployment-physics — 建筑、Placer、部署、碰撞、物理、燃烧
- dst-status-buffs-survival — Buff/Debuff、饥饿/理智/血量/温度/潮湿
- dst-followers-mounts-pets — 随从、宠物、坐骑、驯化、骑乘
- dst-plants-farming-regrowth — 植物、农作物、生长、再生
- dst-world-systems-events-weather — 世界系统、季节、天气、昼夜、生成器
- dst-ocean-boats-fishing — 海洋、船、航行、海钓、平台坐标

### 世界 / UI / 资源
- dst-worldgen-authoring — 世界生成、任务集/房间/拓扑/锁钥
- dst-worldgen-layouts-retrofit — 静态布局、Setpiece、旧存档 Retrofit
- dst-tiles-map-minimap — 地皮、Tile、地图、小地图、铺地
- dst-shards-caves-portals — 分片、洞穴、传送、跨服迁移
- dst-scenarios-setpieces-cutscenes — 场景、布景、演出、过场
- dst-ui-widget-authoring — Widget 控件、布局、焦点、手柄导航
- dst-hud-screens-input — HUD、Screen、弹窗、输入
- dst-client-frontend-mods — 纯客户端模组、建服前端扩展
- dst-assets-animation-atlas — 动画、Build、Bank、图集、纹理
- dst-fx-vfx-authoring — 特效、粒子、Bloom
- dst-audio-camera-effects — 音效、相机震动、镜头表现
- dst-localization-speech — 本地化、角色台词、PO 翻译
- dst-skins-symbol-overrides — 外观变体、Build 切换、Symbol 覆盖
- dst-shader-authoring — .vs/.ps/.ksh、后处理、VFX shader
- modtool-automation — DST Mod Tool 自动化、Lua 脚本注入、截图 diff、动画导入/导出

### 工程化
- dst-performance-profiling — 性能卡顿、FindEntities/OnUpdate 热点、优化
- dst-dedicated-server-testing — 专服、Master/Caves 分片测试
- dst-workshop-release — Steam Workshop 发布
- dst-mod-review-refactoring — 模组审查与重构

### 易混淆配对速查（双命中时优先加载两个，先做更高层面的那个）

- **特效 vs 着色器**：粒子/光效/拖尾 → `dst-fx-vfx-authoring`；写 .ksh/.vs/.ps、后处理滤镜 → `dst-shader-authoring`。都涉及但以视觉表现为目标时优先 fx，以渲染代码为目标时优先 shader。
- **布景 vs 布局**：一次性演出/过场/剧情 → `dst-scenarios-setpieces-cutscenes`；往老存档静态铺物件、地图布局 → `dst-worldgen-layouts-retrofit`。
- **血量/伤害类**：武器/攻击/投射物/减伤公式 → `dst-combat-weapons-projectiles`；Buff/Debuff/持续伤害/温度潮湿 → `dst-status-buffs-survival`；现象是"打不死/不掉血"找原因 → `dst-debugging-testing`。
- **跟随类**：AI 行为树里的追随/巡逻 → `dst-brain-authoring`；宠物/坐骑/驯化/忠诚关系 → `dst-followers-mounts-pets`。
- **不同步类**：RPC/复制/netvar 设计 → `dst-networking-rpc`；已成事实的不同步故障排查 → `dst-debugging-testing`。
- **界面类**：自定义控件/列表/布局 → `dst-ui-widget-authoring`；HUD/屏幕/输入/弹窗 → `dst-hud-screens-input`。
- **做武器/装备**：`dst-inventory-equipment-containers`（装备栏/耐久/容器）+ `dst-combat-weapons-projectiles`（伤害数值）双加载。
- **Mod Tool 自动化 vs 动画资源**：用 DST Mod Tool 自动化导入/编辑/导出动画 → `modtool-automation`；手写动画资源（.ani/.bank）或做图集 → `dst-assets-animation-atlas`。涉及工具链操作（script --stdin、截图 diff）时优先 modtool-automation。

## 第二步：执行

1. 用 Skill 工具加载选中技能（**精确全名**），加载后再动手。
2. 严格按该技能 SKILL.md 的「工作流 → 源码锚点 → 不变量 → 验证」执行；references/、assets/、scripts/ 按需使用。
3. 以当前安装的 DST 源码 `D:\steam\steamapps\common\Don't Starve Together\data\scripts` 为事实依据。
4. 修改只落在用户指定的 Mod 目录，不改游戏源码。
5. 完成后按所选技能的要求验证，并说明用了哪些技能。

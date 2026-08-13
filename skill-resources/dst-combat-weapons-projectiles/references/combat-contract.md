# DST 战斗契约速查（对照真实源码）

以本机安装的 `components/` 为基准。下文所有函数签名均已在本机源码核对。

## 1. Combat 组件（components/combat.lua）

由服务器持有并计算命中。默认值在 `defaults` 表。

- `combat:SetDefaultDamage(dmg)` —— combat.lua:222。基础伤害（原始值）。
- `combat:SetAttackPeriod(period)` —— combat.lua:120。攻击间隔（秒）。
- `combat:SetRange(attack, hit)` —— combat.lua:148。`attack` 是发起攻击的施法/命中距离，`hit` 是命中判定距离；留空时取默认。
- `combat:SetRetargetFunction(period, fn)` —— combat.lua:275。按周期重选目标。
- 伤害计算入口 `combat:DoAttack()`（combat.lua:1095）与受击入口 `combat:GetAttacked()`（combat.lua:568）；两者与 `health:DoDelta()` 不能在同一命中里叠加。
- 阵营/敌意由 `combat.hostile` 与伤害类型交互决定；友伤取决于世界设置与攻击者阵营。

## 2. Weapon 组件（components/weapon.lua）

- `weapon:SetDamage(dmg)` —— weapon.lua:44。
- `weapon:SetRange(attack, hit)` —— weapon.lua:48。
- `weapon:SetProjectile(prefabname)` —— weapon.lua:65。指定攻击时抛出的投射物。
- `weapon:SetProjectileOffset(offset)` —— weapon.lua:69。

## 3. Health 组件（components/health.lua）

- `health:SetMaxHealth(amount)` —— health.lua:503。
- `health:DoDelta(amount, cause)` —— health.lua:613。直接改血。
- `health:SetInvincible(bool)`、`health:SetCanRevive(bool)` 见 health.lua 其它方法；死亡走 `OnDeath`。

## 4. 投射物 Projectile（components/projectile.lua）

直线投掷，无重力。原版范例：`prefabs/boomerang.lua:131-139`。

```lua
inst:AddComponent("projectile")
inst.components.projectile:SetSpeed(10)
inst.components.projectile:SetCanCatch(true)          -- 可被接住
inst.components.projectile:SetOnThrownFn(OnThrown)
inst.components.projectile:SetOnHitFn(OnHit)
inst.components.projectile:SetOnMissFn(OnMiss)
inst.components.projectile:SetOnCaughtFn(OnCaught)
```

- `SetSpeed` projectile.lua:90；`SetCanCatch` :129；`SetOnThrownFn` :109；`SetOnHitFn` :113；`SetOnMissFn` :121；`SetOnCaughtFn` :125。
- `SetStimuli` :97、`SetRange` :101、`SetHitDist` :105、`SetHoming` :133、`SetLaunchOffset` :137。
- 投掷动作由 SG 调 `projectile:Throw()` 或武器射击逻辑触发，命中回调在服务器端结算。

## 5. 复杂投射物 ComplexProjectile（components/complexprojectile.lua）

带重力的抛物线弹道。范例：`prefabs/boat_cannon.lua`、`prefabs/birds_mutant.lua`。

```lua
inst:AddComponent("complexprojectile")
inst.components.complexprojectile:SetHorizontalSpeed(speed)
inst.components.complexprojectile:SetGravity(g)
inst.components.complexprojectile:SetOnLaunch(OnLaunch)
inst.components.complexprojectile:SetOnHit(OnHit)
inst.components.complexprojectile:SetOnUpdate(OnUpdate)
```

- `SetHorizontalSpeed` complexprojectile.lua:41；`SetHorizontalSpeedForDistance` :45（按距离反推速度，配合 `CalculateMinimumSpeedForDistance` :74）；`SetGravity` :50；`SetOnLaunch` :62；`SetOnHit` :66；`SetOnUpdate` :70。
- 发射 `Launch(targetPos, attacker, owningweapon)` :123；取消 `Cancel()` :172；手动命中 `Hit(target)` :180。
- **所有权传递**：`Launch` 的第三参 `owningweapon` 决定击杀归属，投射物命中后必须 `complexprojectile:Hit(target)` 或自然落地走 OnMiss，否则任务/回调泄漏。

## 6. 位面伤害（components/planardamage.lua、planardefense.lua）

- `planardamage`：`SetBaseDamage` / `SetBonusDamage` 对应原始与加成位面伤害。
- `planardefense`：`SetPlanarDefense(amount)` 减免位面伤害。
- 位面伤害不与普通护甲百分比减免叠加；对照 `planardamage.lua` 与 `planardefense.lua` 实际字段再配置。

## 7. 最小可运行武器 prefab（对照原版 axe.lua）

```lua
-- 服务器分支：SetPristine 后、return 前
inst:AddComponent("weapon")
inst.components.weapon:SetDamage(TUNING.AXE_DAMAGE)   -- 或自定数值
inst:AddComponent("combat")
inst.components.combat:SetDefaultDamage(TUNING.AXE_DAMAGE)
inst.components.combat:SetAttackPeriod(1.0)
inst.components.combat:SetRange(1.0, 2.0)
```

## 8. 验证清单

- 无甲 / 有甲 / 位面防御三种情况伤害符合公式。
- 高延迟下不会双重命中（DoAttack 与 GetAttacked 不同时结算）。
- 投射物命中、落空、被移除、跨平台路径均干净退出（无残留任务/拖尾）。
- PvP 与世界设置下友伤符合预期。

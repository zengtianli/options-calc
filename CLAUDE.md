# options-calc · 期权决策台（iOS）

`~/Apps/ios/options-calc` — **`~/Apps/ios` 形态的首个住户**（2026-08-18 立）。
父级规则见 `~/Apps/CLAUDE.md`，全局偏好见 `~/.claude/CLAUDE.md`。

## 一句话

四种卖方结构（备兑开仓 / 现金担保 put / 信用价差 / 铁鹰）的到期损益、真占用、
年化各口径、盈利概率与 EV。装在 iPhone 上盘中查。

## 三条硬规矩

### ① 算式是**移植**的，不是重写的

源 = `~/Dev/stations/apps-site/webapps/options.html` 第 422–647 行
（`CORE-START`…`CORE-END`，纯计算层无 DOM）。`Sources/Calc.swift` 逐行照搬。

**要改算式，先改源那边，再同步过来** —— 反过来改这边会让两个面悄悄分叉，
而分叉的表现是「网页和手机算出来的数不一样」，用户先撞上、你后知道。

### ② 回归两侧共读同一份用例

```bash
# Xcode 走总部 SSOT 现挑（原文钉在 Xcode-27.0.0-Beta.5 这个具体版本号上，
# 下一个 beta 落地即变成 missing DEVELOPER_DIR path）
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh && xcode_env_use macosx
xcrun swiftc -O Sources/Calc.swift ref/main.swift -o ref/regress
./ref/regress >| ref/actual.json && node ref/diff.js
# → 8 用例 / 397 个数值(容差 1e-9) + 83 段文案(逐字)
```

`ref/cases.json` 是**唯一用例源**，`ref/gen.js`（跑真 options.html）与 `ref/main.swift`
（跑真 Calc.swift）都读它。此前两边各写一份参数，「逐字相同」全靠人盯 —— 那种情况下
「全部一致」可能是假的（两边喂的输入本来就不同）。

**文案必须逐字对，不能只对数值。** 早先只对数值时，209 值全绿的同时：cc 的告警少了
「这张 call 的」五个字、`Int(n)` 把 1.5 张截断成 1 张（而同一组 legs 里还印着「多 150 股」）。
加上文案层后**第一次跑就又抓到**千分位 `$2,370` vs `$2370`。

### ③ 装机走脚本，别手点 Xcode

```bash
./install-to-iphone.sh          # 挑 Xcode → 找设备 → 取 Team → 编签 → 装 → 启动
```

免费 Personal Team：**证书 7 天到期，到期 app 打不开，重跑这条即续**；同时最多 3 个自签 app。

## 两个踩出来的坑（改脚本前先读）

**手机系统比 Xcode 新 → `connected (no DDI)`，装不上。**
iPhone 17 / iOS 27.0 配 Xcode 26.6（iOS SDK 26.5）就是这个症状。
脚本因此**按 iOS SDK 版本自动挑 Xcode，不写死路径** —— 挑选逻辑不在本仓，
在总部 SSOT `~/Dev/tools/dev/lib/tools/macapp/xcode_env.{py,sh}`（本文件与 README 的
重跑命令都 `source` 它，一个 Xcode 路径字面量都不留）。

> 2026-08-19 补：26.6 那个 `.app` 现已被 macOS 27.0 判为不支持、**GUI 打不开**
> （弹 `This version of Xcode isn't supported in this version of macOS`），只剩 CLI 工具链可用。
> SSOT 选择器会自然跳过它（`xcode_env.py list` 实测标它卡在 **G3 host-os-support**）——
> **但别依赖「它排最后」这个巧合**：判据是 SDK 版本与宿主支持性，不是「哪个还能打开」。
> 2026-09-01 补：Beta 5 与 26.6 均已删（26.6 是死重：G3 永久跳过、TestFlight 也走 Beta 6），盘上只剩 `Xcode-27.0.0-Beta.6.app`；27 正式版出来后 App Store 装回。

**设备探测三条判据缺一不可**（`~/Dev/tools/dev/lib/tools/macapp/ios/detect_device.py`，由 `~/Dev/tools/dev/lib/tools/macapp/ios/test-device-detect.py` 11 例双向验）：
`reality == physical`（少了会挑中**模拟器**，实测踩过：手机拔线后脚本挑走 iPhone 17 Pro
模拟器，一路编到「找不到 .app」才炸、报错还指向别处）· 排除 `unavailable`/`disconnected`
· `deviceType` 或 `marketingName` 任一含 iPhone。

**探测逻辑只有一份**（`~/Dev/tools/dev/lib/tools/macapp/ios/detect_device.py`），脚本与测试都调它。曾经是脚本内嵌一份、
测试抄一份，注释还写着「与…逐字相同」—— 那正是会漂的写法。

## 构建两条路，产物等价

| | `./build.sh`（swiftc） | `xcodebuild`（真工程） |
|---|---|---|
| 用途 | 快速迭代 + 装模拟器 | 真机、签名 |
| 图标 | 自己调 `actool` 编进去 | Xcode 自动 |

> `swiftc` 那条**不经 actool**，图标不会自己进 `.app`。`build.sh` 里已显式调用并
> fail-closed 校验（缺 `Assets.car`/PNG 即 `exit 1`）。

`OptionsSpike.xcodeproj` 由 `project.yml` 经 xcodegen 生成，**不进仓**：
改 yml 忘了重生成，工程和规格就悄悄不一致。改配置改 `project.yml`，然后
`xcodegen generate --spec project.yml`。

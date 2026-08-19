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
export DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer
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
脚本因此**按 iOS SDK 版本自动挑 Xcode，不写死路径**。

**设备探测三条判据缺一不可**（`detect_device.py`，由 `test-device-detect.py` 11 例双向验）：
`reality == physical`（少了会挑中**模拟器**，实测踩过：手机拔线后脚本挑走 iPhone 17 Pro
模拟器，一路编到「找不到 .app」才炸、报错还指向别处）· 排除 `unavailable`/`disconnected`
· `deviceType` 或 `marketingName` 任一含 iPhone。

**探测逻辑只有一份**（`detect_device.py`），脚本与测试都调它。曾经是脚本内嵌一份、
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

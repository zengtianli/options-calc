# iOS spike · 期权决策台（抛弃式）

2026-08-18。目的**不是**做产品，是验一件事：**不办 $99，能不能把 Swift 跑到 iPhone 上。**

## 结论

| | 结论 | 证据 |
|---|---|---|
| 裸 `swiftc` 编 iOS | ✅ 能 | `vtool` → `platform IOSSIMULATOR`，`otool -L` 链接 UIKit 非 AppKit |
| 手搓 `.app` 装模拟器 | ✅ 能 | `simctl install`/`launch`，四档逐屏核对数值 |
| `xcodebuild` 走真工程 | ✅ 能 | `BUILD SUCCEEDED`（补齐平台包之后） |
| 需要 $99 证书 | ❌ 模拟器不需要 | 模拟器不校验签名 |
| **装到真 iPhone** | ✅ **已实测装上** | iPhone 17 / iOS 27.0，`devicectl device info apps` 里查得到；证书 `Apple Development: zengtianli2@126.com (YYDKN95YU5)` |

> 更正一条早先的说法：「裸 swiftc 做 iOS 走不通」**说宽了**。真机走不通，模拟器走得通。

## 两条构建路径，产物现在等价

| | `./build.sh`（swiftc） | `xcodebuild`（真工程） |
|---|---|---|
| 用途 | 快速迭代、装模拟器 | 真机、签名、以后上架 |
| 图标 | ✅ 自己调 `actool` 编进去 | ✅ Xcode 自动 |
| 警告 | 0 | 0 |

> `swiftc` 那条**不经 actool**，图标不会自己进 `.app`。这是独立复核挖出来的：
> 此前 `build.sh` 全文没有 `Resources/` 与 `actool`，图标只躺在 `Assets.xcassets` 里从未进过产物，
> 而 README 却标着「✅ 图标」。现已补上，且 actool 失败即 `exit 1`（不静默产一个没图标的包）。
> 主屏截图 `shots/springboard-icon.png` 实测图标正常显示。

## 真机路径：已打通

一条命令搞定，**不用在 Xcode 里点任何东西**：

```bash
bash ~/Apps/ios/options-calc/install-to-iphone.sh
```

它做六件事：挑 Xcode → 找设备 → 读 Team ID → 编译并现场申请签名 → 装 → 启动。
每步都有前置门，缺什么直接说缺什么。

**只需要人做两件（各一次）**：
1. **打开 `/Applications/Xcode-27.0.0-Beta.5.app`** → Settings → Apple Accounts → 登录 Apple ID
   （别双击 `/Applications/Xcode.app`：那是 26.6，macOS 27.0 判它不支持，会弹
   `This version of Xcode isn't supported in this version of macOS`，报错完全不提「换另一个」）
2. 装完后手机上：设置 → 通用 → VPN 与设备管理 → 开发者应用 → 你的 Apple ID → **信任**
   （不点这一下，app 装得进去但打不开；`devicectl` 会明说
   `its profile has not been explicitly trusted by the user`）

### 两个把我卡住过的坑

**① 手机系统比 Xcode 新 → `connected (no DDI)`，装不上。**
iPhone 17 是 iOS 27.0，而 `/Applications/Xcode.app` 是 26.6（iOS SDK 26.5），
`devicectl list devices` 显示 `connected (no DDI)`。换成 `Xcode-27.0.0-Beta.5.app`
（iOS SDK 27.0）后，同一台设备立刻变成干净的 `connected`。
→ 脚本因此**不写死 Xcode 路径**，按「iOS SDK 版本最高」自动挑。
2026-08-18 起这段算法已上提为总部 SSOT `~/Dev/tools/dev/lib/tools/macapp/xcode_env.{py,sh}`，
并补了一道本文件当初没有的门：**Xcode 自带的 macOS 宿主 SDK 不能老于正在跑的 macOS** ——
光看 `-showsdks` 排除不掉 26.6（它 rc=0、SDK 列表完整），只有这道门能把它判出局。

> ⚠ **2026-08-19 订正**（上文默认「盘上两个 Xcode 都能用，只差 SDK 新旧」，这个前提已不成立）：
> `/Applications/Xcode.app`(26.6) 已被 macOS 27.0 判为不支持，**GUI 打不开**（双击弹
> `This version of Xcode isn't supported in this version of macOS`；其 Info.plist
> `LSMinimumSystemVersion=26.2`，属兼容性拉黑不是版本号拦截）。它的**命令行工具链仍可用**
> （`DEVELOPER_DIR=…/Xcode.app xcodebuild -version` rc=0），所以是「GUI 已死、只剩 CLI 半条命」，
> 不是单纯的「旧」。占盘 **3.5 G**（`du -sh` 实测；模拟器 runtime 不在 .app 里，删它并不释放那 8.5 G）。本机唯一完整可用的是 `Xcode-27.0.0-Beta.5.app` ——
> 上文的「两个都在盘上」现在只剩一个半。
> 实证：`python3 ~/Dev/tools/dev/lib/tools/macapp/xcode_env.py list` 把 26.6 标为卡在
> **G3 host-os-support**（宿主 macOS SDK 26.5 < 正在跑的 macOS 27.0）。

**② 证书不是登录时生成的，是首次真机构建时生成的。**
脚本最初有一道「先查 Apple Development 证书是否存在」的前置门 —— 这道门是错的，
它会把正常的首次流程挡在外面（登录后证书确实还不存在，`security find-identity` = 0）。
证书由 `xcodebuild -allowProvisioningUpdates` 现场申请。同理 Team ID 也读不到证书里，
要从 Xcode 偏好 `IDEProvisioningTeamByIdentifier` 读。

### 免费账号的两个限制，以及怎么绕

| 限制 | 绕法 |
|---|---|
| 证书 **7 天到期** | ① 重跑 `./install-to-iphone.sh`（手动，要 Mac 在手边；2026-08-19 订正：原写「Xcode 重新 ⌘R」已非现行做法，且真要走 GUI 只能开 `Xcode-27.0.0-Beta.5.app`）② SideStore 后台自动续签 |
| **同时最多 3 个 app** | LiveContainer（把 app 托管在一个容器里，只有容器占签名位） |

自动续签这条路的真实代价（源：用户给的抖音教程，已抽帧 + whisper 转录逐句核）：

- **要把 Apple ID 和密码填进第三方桌面工具**，且必须与设备登录的 ID 一致
- **依赖一个第三方 anisette 服务器**。原话：「如果 7 天内无法得到续签那么就会掉签，所有的已签名应用都会打不开」
  —— 所谓「永久签名」= **7 天内一定要续上**，不是证书真的变长
- LiveContainer 托管的 app **权限比证书低，无法进入后台运行**（视频自己说的）
- 当前 iOS 26.4+ 的安装入口是 **iloader** 而不是直接装 SideStore ——
  SideStore `0.6.3` release body 第一行原文：
  「⚠️**Please Reinstall With iloader**⚠️ If you have updated to iOS 26.4+ and are receiving VPN errors.」

> 这条路适合「收 app 的人没有 Mac」。如果对方有 Mac，⌘R 更简单也更少活动部件。

## 环境缺口（本轮补掉了）

`xcodebuild` 一开始编不过：

```
Assets.xcassets: error: No simulator runtime version from ["23E244"]
available to use with iphonesimulator SDK version 23F81a
```

装的模拟器 runtime 是 26.4，Xcode 26.6 的 SDK 是 26.5，**actool 要求两者匹配**。
跑 `xcodebuild -downloadPlatform iOS` 补了 8.52 GB（免费），之后 `xcodebuild` 与 `actool` 都通了。

> 2026-08-19 复核：**换 Xcode-27.0.0-Beta.5（iOS SDK 27.0）后无需再下一次平台包** ——
> `xcrun simctl list runtimes` 实测 iOS **26.4 / 26.5 / 27.0** 三个 runtime 均已在盘，
> 「runtime 与 SDK 版本必须匹配」这个条件对 26.6(SDK 26.5) 与 Beta.5(SDK 27.0) 都已满足。
> 上面这条坑记录本身没错，但它停在「只有 26.5」的世界观里，别据此以为换 Xcode 还要再下 8.5 GB。

> ⚠ 排查中另有一个**偶发**现象：同一份 project.yml 连跑两次，第一次 `BUILD SUCCEEDED`、
> 第二次 `Found no destinations`。据此做的一轮二分曾误判「INFOPLIST_KEY_* 破坏 destination 解析」，
> **该结论已被重跑证伪**。遇到 `Found no destinations` **先原样重跑一次再怀疑配置**。

## 算式不是重写的，是移植的

源 = `~/Dev/stations/apps-site/webapps/options.html` 第 422–647 行（`CORE-START`…`CORE-END`）。
Swift 版 `Sources/Calc.swift` 逐行照搬。

对账（`ref/`）：**两侧共读同一份 `ref/cases.json`**（此前两边各写一份参数，「逐字相同」全靠人盯，
独立复核点名了这个隐患：如果两边喂的输入本来就不同，那句「全部一致」是假的）。

```
对账 8 条用例 / 397 个数值(容差 rel<=1e-9) + 83 段文案(逐字)  → ✅ 全部一致
```

**反向验证做过**：把源注释警告的 bug（`integrate` 掉 `1/sd`）种回去重编，对账立刻红且只红在
依赖积分的 `pProfit`/`ev` 上，其余值不动 —— 抓得住也定位得准。

### 三个「全绿仍漏掉」的教训

1. **回归只喂写死参数，UI 用自己的默认值**。初版 UI 共享 `n = 2`，而源 DEFAULTS 是 `cc/csp: 2`、
   **`vert/ic: 5`** → 铁鹰那屏所有金额都是基准的 2/5。而**保本点、盈利概率、行权价与 n 无关，
   照样全对** —— 只核那几个数会判成「全对」。是逐屏读截图核**金额**才暴露的。
2. **对账只覆盖数值不覆盖文案**，于是 `Calc.swift` 的 cc 告警少了「这张 call 的」五个字、
   `Int(n)` 把 n=1.5 截断成「空 1 张 call」（同组还印着「多 150 股」，自相矛盾），209 值照样全绿。
   把文案纳入逐字对账后，**第一次跑就又抓到一条**：JS 用 `toLocaleString()` 有千分位 `$2,370`，
   Swift 的 `%.0f` 是 `$2370`。
3. 结论：**扩覆盖面比眼尖可复制。** 前两条都不是靠仔细看代码发现的，是靠让机器能看见。

### 四档屏幕核对（`shots/tab-*.png`，全部与 `ref/expected.json` 一致）

| 档 | 占用 | 权利金 | 最大盈利 | 最大亏损 | 保本 | 年化 | 盈利概率 | EV |
|---|---|---|---|---|---|---|---|---|
| 备兑开仓 | 19110 | 890 | 1290 | −18310 | 91.55 | 31.2/26.9/125.3% | 85.5% | 836.13 |
| 现金担保 put | 18768 | 232 | 232 | −18768 | 93.84 | 15.0/18.4% | 77.4% | −15.50 |
| 信用价差 | 2035 | 465 | 465 | −2035 | 105.93 | 278.0% | 77.6% | 22.58 |
| 铁鹰 | 2370 | 315 | 315 | −2185 | 89.37 / 110.63 | 161.7% | 81.6% | 4.57 |

## 怎么重跑

```bash
cd ~/Apps/ios/options-calc          # 2026-08-18 订正：原文写的 ~/Dev/_scratch/ios-options-spike 已不存在
# Xcode 走总部 SSOT 现挑，不写死也不用 sudo 改 xcode-select
source ~/Dev/tools/dev/lib/tools/macapp/xcode_env.sh && xcode_env_use macosx

# 1) 算式回归（macOS 上跑，秒级）
xcrun swiftc -O Sources/Calc.swift ref/main.swift -o ref/regress
./ref/regress >| ref/actual.json && node ref/diff.js

# 2) swiftc 路径：编 + 装 + 跑（零警告，含图标）
./build.sh
DEV=9A90AB0B-6CD8-4C62-9BC3-2CADE6E835F6      # iPhone 17 Pro
xcrun simctl boot "$DEV" 2>/dev/null; open -a Simulator
xcrun simctl install "$DEV" build/OptionsSpike.app
xcrun simctl launch "$DEV" cyou.tianli.optionsspike
# 确定性落到某一档 + 直接看结果区：--kind=<cc|csp|vert|ic> --results-only

# 3) xcodebuild 路径（真机要走这条）
xcodegen generate --spec project.yml          # 改了 project.yml 之后
xcodebuild -project OptionsSpike.xcodeproj -scheme OptionsSpike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .dd build
```

## 已知遗留

- ✅ 真机已验（2026-08-18 实测装上 iPhone 17 / iOS 27.0，证书
  `Apple Development: zengtianli2@126.com (YYDKN95YU5)`）—— **原写的「⏸ 真机未验（卡在
  Apple ID 登录 + 插线）」已作废**（2026-08-19 订正）：它与本文件开头结论表第 4 行
  「装到真 iPhone ✅ 已实测装上」直接打架，是分叉会话重写 README 时留下的残渣。
- 没有启动图（`INFOPLIST_KEY_UILaunchScreen_Generation: YES` 让 Xcode 自动生成；
  `build.sh` 那条用 `UILaunchScreen` 空字典）

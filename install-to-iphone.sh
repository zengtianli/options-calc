#!/bin/bash
# 把 app 装到真 iPhone。前提:已在 Xcode 里登录 Apple ID(GUI,只需一次)。
#
# 注意:免费账号的 Apple Development 证书**不是登录时生成的**,是第一次为真机构建
# (xcodebuild -allowProvisioningUpdates)时由 Xcode 现场申请的。所以本脚本不预先
# 检查证书存在与否 —— 那道门会把正常的首次流程挡在外面。
#
# 免费 Personal Team 的两个硬限制(与本脚本无关):
#   · 证书 7 天到期 —— 到期后 app 打不开,重跑本脚本即可续
#   · 同时最多 3 个自签 app
set -uo pipefail
cd "$(dirname "$0")"
BUNDLE=cyou.tianli.optionsspike
die() { printf '\n❌ %s\n' "$1" >&2; exit 1; }

# ── [1] 挑 Xcode:按「iOS SDK 版本 >= 设备系统版本」选,不写死路径 ──────────────
# (2026-08-18 实证:手机 iOS 27.0 + Xcode 26.6 → devicectl 报 `connected (no DDI)`,
#  装不上;换 Xcode 27 beta 后同一台设备立刻变成干净的 `connected`。)
echo "[1/6] 挑 Xcode"
best=""; bestsdk=""
for x in /Applications/Xcode*.app; do
  [ -d "$x" ] || continue
  sdk=$(DEVELOPER_DIR="$x/Contents/Developer" xcodebuild -showsdks 2>/dev/null \
        | sed -n 's/.*-sdk iphoneos\([0-9.]*\).*/\1/p' | sort -V | tail -1)
  [ -n "$sdk" ] || continue
  printf "      %-34s iOS SDK %s\n" "$(basename "$x")" "$sdk"
  if [ -z "$bestsdk" ] || [ "$(printf '%s\n%s\n' "$bestsdk" "$sdk" | sort -V | tail -1)" = "$sdk" ]; then
    best="$x"; bestsdk="$sdk"
  fi
done
[ -n "$best" ] || die "盘上找不到带 iOS SDK 的 Xcode。"
export DEVELOPER_DIR="$best/Contents/Developer"
echo "      ✅ 用 $(basename "$best")  (iOS SDK $bestsdk)"

# ── [2] 找真机 ────────────────────────────────────────────────────────────────
echo "[2/6] 找连着的 iPhone"
J=$(mktemp)
xcrun devicectl list devices --json-output "$J" >/dev/null 2>&1 || true
read -r UDID DEVNAME DEVOS <<<"$(python3 detect_device.py "$J" 2>/dev/null)"
if [ -z "${UDID:-}" ]; then
  echo "      devicectl 当前看到:"; xcrun devicectl list devices 2>/dev/null | sed 's/^/        /'
  die "没有处于 connected 的 iPhone。逐条确认:
   ① 数据线插上(首次别用 WiFi)
   ② iPhone 解锁,弹「信任此电脑」点信任并输密码
   ③ 设置 → 隐私与安全性 → 拉到底 → 开发者模式 → 打开(要重启手机)
   ④ 若状态是「connected (no DDI)」:手机系统比 Xcode 新,装对应版本的 Xcode"
fi
echo "      ✅ ${DEVNAME//_/ }  iOS $DEVOS  ($UDID)"

# ── [3] 取 Team ID ────────────────────────────────────────────────────────────
# 首次为真机构建前**还没有证书**,所以不能从证书里读 team。Xcode 登录后会把
# team 写进自己的偏好(IDEProvisioningTeamByIdentifier),从那里读才对。
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  echo "[3/6] 取 Team ID"
  DEVELOPMENT_TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamID *= *\([A-Z0-9]*\).*/\1/p' | head -1)
  [ -n "$DEVELOPMENT_TEAM" ] || die "读不出 Team ID。
   → 确认 Xcode → Settings → Apple Accounts 里已登录且能看到你的账号。
   → 或手动指定: DEVELOPMENT_TEAM=<你的TeamID> bash $0"
  TEAMNAME=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamName *= *"\(.*\)".*/\1/p' | head -1)
  echo "      ✅ $DEVELOPMENT_TEAM  ${TEAMNAME:-}"
fi

# ── [4] 编 + 让 Xcode 现场申请证书与 profile ──────────────────────────────────
echo "[4/6] 编译 + 申请签名(首次会慢,证书就是这一步生成的)"
LOG=$(mktemp)
xcodebuild -project OptionsSpike.xcodeproj -scheme OptionsSpike \
  -destination "id=$UDID" -derivedDataPath .dd-device \
  -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic \
  ${DEVELOPMENT_TEAM:+DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"} \
  build >"$LOG" 2>&1
if [ $? -ne 0 ]; then
  grep -E 'error:|Provisioning|requires a development team|Signing' "$LOG" | head -12 | sed 's/^/      /'
  die "编译/签名失败,完整日志: $LOG
   常见原因:
   · 「requires a development team」→ 有多个 team 分不清,用 DEVELOPMENT_TEAM=<ID> 重跑;
     查 ID: security find-identity -v -p codesigning
   · 「Unable to log in with account」→ Xcode → Settings → Apple Accounts 重登一次
   · 「maximum number of apps for free development profiles」→ 免费账号同时最多 3 个自签 app,
     去手机上删掉一个别的自签 app"
fi
echo "      ✅ BUILD SUCCEEDED"
APP=$(find .dd-device -name 'OptionsSpike.app' -path '*iphoneos*' 2>/dev/null | head -1)
[ -n "$APP" ] || die "编出来了但找不到 .app,日志: $LOG"

# ── [4] 装 ────────────────────────────────────────────────────────────────────
echo "[5/6] 安装到手机"
xcrun devicectl device install app --device "$UDID" "$APP" >"$LOG.ins" 2>&1 \
  || { tail -10 "$LOG.ins" | sed 's/^/      /'; die "安装失败,日志: $LOG.ins"; }
echo "      ✅ 已安装"

# ── [5] 启动 ──────────────────────────────────────────────────────────────────
echo "[6/6] 启动"
if xcrun devicectl device process launch --device "$UDID" "$BUNDLE" >"$LOG.run" 2>&1; then
  echo "      ✅ 已启动"
else
  echo "      ⚠ 自动启动没成功(不影响安装)。多半是还没信任开发者证书:"
  echo "        iPhone → 设置 → 通用 → VPN 与设备管理 → 开发者应用 → 信任"
fi

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 手机主屏找「期权决策台」。

⚠ 首次打开若提示「不受信任的开发者」:
   设置 → 通用 → VPN 与设备管理 → 开发者应用 → 你的 Apple ID → 信任

⏳ 免费证书 7 天到期,到时 app 打不开。续期 = 重跑本脚本:
   bash $(pwd)/install-to-iphone.sh
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

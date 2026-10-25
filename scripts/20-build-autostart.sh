#!/bin/bash
# ============================================================
# 20 构建并安装「定时启动」
#
#   ./20-build-autostart.sh            编译 → 安装 → 解除 stopped 态
#   ./20-build-autostart.sh --apk      跳过编译，直接装 apk/ 里的现成 APK
#
# 关键：必须带 -PlauncherApplicationId=com.ktcp.launcher.autostart 编译。
# 固件有 HOME 前缀白名单（com.ktcp.launcher*），不带这个参数会装成
# com.skyworthdigital.autostart，成为另一个应用且过不了白名单。
# Java 命名空间仍是 com.skyworthdigital.autostart，所以组件全名是
# com.ktcp.launcher.autostart/com.skyworthdigital.autostart.ReminderService
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

APP="$REPO_ROOT/apps/TVAutoStart"
AUTOSTART_VER="v4.2"          # 升版本时改这一行，apk/ 里的文件名跟着变
APK="$REPO_ROOT/apk/tvautostart-$AUTOSTART_VER.apk"

if [ "$1" != "--apk" ]; then
  command -v java >/dev/null 2>&1 || die "需要 JDK 17"
  [ -n "$ANDROID_HOME" ] || [ -n "$ANDROID_SDK_ROOT" ] || die "需要设置 ANDROID_HOME 指向 Android SDK"
  info "编译（首次约 1 分钟，增量约 20 秒）…"
  (cd "$APP" && ./gradlew assembleRelease -PlauncherApplicationId="$AUTOSTART_PKG") || die "编译失败"
  # 产物同步回 apk/，保证仓库里那份就是刚编译出来的
  cp "$APP/app/build/outputs/apk/release/app-release.apk" "$APK"
  info "已更新 $APK"
fi

[ -f "$APK" ] || die "找不到 APK：$APK"

conn
info "安装 $APK"
"$ADB" -s "$BOX" install -r "$APK" | tr -d '\r' | sed 's/^/  /'

# 侧装应用默认是 stopped 态，收不到广播也起不来，必须清一次
sh "monkey -p $AUTOSTART_PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
sh "dumpsys deviceidle whitelist +$AUTOSTART_PKG" >/dev/null 2>&1

echo "  安装结果：$(sh "pm list packages $AUTOSTART_PKG")"
ok "定时启动已安装。下一步：./30-set-autostart.sh <目标包名> <名称> <秒数>"

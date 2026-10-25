#!/bin/bash
# ============================================================
# 21 构建并安装 Aerial 桌面（并设为默认桌面）
#
#   ./21-build-aerial.sh            clone 上游 → 打补丁 → 编译 → 安装 → 设为 HOME
#   ./21-build-aerial.sh --apk      跳过编译，直接装 apk/ 里的现成 APK 并设为 HOME
#
# 上游：https://github.com/pengchujin/aerial-tv
# 本仓库只保留改动（patches/aerial-tv-p3.patch），不复制上游 96MB 源码。
#
# 补丁做了两件事：
#   1. applicationId 改成 com.ktcp.launcher.aerial（固件 HOME 前缀白名单要求 com.ktcp.launcher*）
#      Java 命名空间仍是 app.orchard.tv，所以组件名是 com.ktcp.launcher.aerial/app.orchard.tv.MainActivity
#   2. 加 AutostartBridge：开机首次进桌面时显式拉起「定时启动」的服务
#      （这台固件屏蔽所有第三方 BOOT_COMPLETED 广播，只有桌面自己能带它起来）
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

UPSTREAM="https://github.com/pengchujin/aerial-tv"
PINNED_COMMIT="f1c8ea97"         # 1.49 的提交；补丁只依赖 3 处上下文，换版本一般能直接复用
AERIAL_VER="1.49"
WORK="${AERIAL_SRC:-$REPO_ROOT/../aerial-tv}"
PATCH="$REPO_ROOT/patches/aerial-tv-p3.patch"
APK="$REPO_ROOT/apk/aerial-tv-$AERIAL_VER-p3.apk"

if [ "$1" != "--apk" ]; then
  command -v java >/dev/null 2>&1 || die "需要 JDK 17"
  [ -n "$ANDROID_HOME" ] || [ -n "$ANDROID_SDK_ROOT" ] || die "需要设置 ANDROID_HOME 指向 Android SDK"

  if [ ! -d "$WORK/.git" ]; then
    info "clone 上游 → $WORK"
    git clone "$UPSTREAM" "$WORK" || die "clone 失败"
  fi
  (cd "$WORK" && git checkout -q "$PINNED_COMMIT") || warn "无法切到 $PINNED_COMMIT，用当前 HEAD 试试"

  info "应用补丁"
  (cd "$WORK" && git apply --check "$PATCH" 2>/dev/null && git apply "$PATCH") \
    || (cd "$WORK" && git apply --3way "$PATCH") \
    || die "补丁应用失败，检查上游版本是否变了"

  info "编译（首次约 9 分钟，增量约 2 分钟）…"
  (cd "$WORK" && ./gradlew assembleStandardRelease) || die "编译失败"
  APK="$(find "$WORK/app/build/outputs/apk/standard/release" -name '*.apk' | head -1)"
  [ -n "$APK" ] || die "没找到编译产物"
  cp "$APK" "$REPO_ROOT/apk/aerial-tv-$AERIAL_VER-p3.apk"
  APK="$REPO_ROOT/apk/aerial-tv-$AERIAL_VER-p3.apk"
fi

conn
info "安装 $APK"
"$ADB" -s "$BOX" install -r "$APK" | tr -d '\r' | sed 's/^/  /'
sh "monkey -p $AERIAL_PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1

# 设 HOME 之前先确认它能被解析（白名单是否放行）
if ! sh "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" | grep -q "$AERIAL_PKG"; then
  die "白名单没放行 $AERIAL_PKG。确认 applicationId 是否真的改成了 com.ktcp.launcher*"
fi

info "设为默认桌面"
sh "cmd package set-home-activity --user 0 $AERIAL_HOME" | sed 's/^/  /'
sh "pm disable-user --user 0 $OFFICIAL_LAUNCHER" | sed 's/^/  /'
echo "  当前 HOME：$(home_now)"

# 装包会把系统的 screensaver_components 重置回广告组件，重新装一次 Aerial 后必须补回来
info "恢复屏保"
restore_dream

ok "Aerial 已设为默认桌面。重启验证：./99-deploy-all.sh --reboot 或直接拔电源重启"
warn "固件每次开机都会把屏保写回广告组件，重启后跑一次 ./10-optimize.sh 或本条命令补回"
warn "别用 Aerial 控制中心的「检查更新」，它会下载官方 app.orchard.tv 包装成第二个应用"

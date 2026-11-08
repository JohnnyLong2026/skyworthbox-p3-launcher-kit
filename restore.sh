#!/usr/bin/env bash
# ============================================================
# 还原：把盒子恢复到接近出厂的状态
#
#   bash restore.sh              全部还原（参数 + 应用 + 官方桌面）
#   bash restore.sh --params     只还原系统参数与屏保
#   bash restore.sh --apps       只把停用/卸载的应用恢复
#   bash restore.sh --home       只把默认桌面还给官方
#   bash restore.sh --uninstall  卸掉 Aerial 并恢复官方桌面
#
# 盒子地址同上：BOX_TARGET=192.168.1.x:5555 bash restore.sh
# ============================================================
set -u
cd "$(dirname "$0")" || exit 1

die()  { echo "[错误] $*" >&2; exit 1; }
info() { echo "[信息] $*"; }
ok()   { echo "[完成] $*"; }

[ -f box.conf ] && . ./box.conf
BOX="${BOX_TARGET:-192.168.1.100:5555}"

find_adb() {
  command -v adb 2>/dev/null && return
  [ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ] && { echo "$ANDROID_HOME/platform-tools/adb"; return; }
  [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ] && { echo "$ANDROID_SDK_ROOT/platform-tools/adb"; return; }
  local w="${LOCALAPPDATA:-}/Microsoft/WinGet/Packages"
  [ -d "$w" ] && find "$w" -maxdepth 4 -name adb.exe -path "*platform-tools*" 2>/dev/null | head -1
}
ADB="$(find_adb)"
[ -n "$ADB" ] || die "找不到 adb"

conn() {
  "$ADB" connect "$BOX" >/dev/null 2>&1
  sleep 1
  "$ADB" -s "$BOX" shell "echo ok" >/dev/null 2>&1 || die "连不上 $BOX"
}
sh_() {
  local out
  out="$("$ADB" -s "$BOX" shell "$*" 2>&1 | tr -d '\r')"
  case "$out" in
    *"device offline"*|*"device '"*"' not found"*|*"cannot connect to"*|*"no devices/emulators found"*)
      die "与 $BOX 的连接中断（盒子多半休眠了，唤醒后重跑）" ;;
  esac
  printf '%s\n' "$out"
}

OFFICIAL_LAUNCHER="com.skyworthdigital.sky2dlauncherv4"
AERIAL_PKG="com.ktcp.launcher.aerial"
AUTOSTART_PKG="com.ktcp.launcher.autostart"

list_of() {
  [ -f "$1" ] || return 0
  grep -v '^[[:space:]]*#' "$1" | sed 's/#.*//; s/^package://' | tr -d '\r' | xargs -n1 2>/dev/null | grep -v '^$'
}
home_now() { sh_ "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1" | awk '{print $NF}'; }

# 整行精确匹配，不过管道（grep -q 命中即退出会让上游收到 SIGPIPE）
pkg_present() {
  case $'\n'"$(sh_ "pm list packages")"$'\n' in
    *$'\n'"package:$1"$'\n'*) return 0 ;;
  esac
  return 1
}

restore_params() {
  info "还原系统参数"
  sh_ "settings put global window_animation_scale 1.0"
  sh_ "settings put global transition_animation_scale 1.0"
  sh_ "settings put global animator_duration_scale 1.0"
  sh_ "settings put global heads_up_notifications_enabled 1"
  sh_ "settings put global assisted_gps_enabled 1"
  sh_ "settings put global wifi_wakeup_enabled 1"
  if [ -s config/backup-screensaver.txt ]; then
    local old; old="$(tr -d '\r' < config/backup-screensaver.txt)"
    [ -n "$old" ] && sh_ "settings put secure screensaver_components $old" && echo "  屏保还原为：$old"
  fi
  ok "参数已还原"
}

restore_apps() {
  local p
  info "启用被停用的应用"
  for p in $(sh_ "pm list packages -d" | sed 's/package://' | tr -d '\r'); do
    sh_ "pm enable $p" >/dev/null 2>&1 && echo "  已启用：$p"
  done
  # suspend 是叠在 disable 之上的另一层，不解掉包仍收不到任何组件调用
  info "解除 suspend"
  for p in $(list_of config/stubborn-list.txt); do
    sh_ "pm unsuspend $p" >/dev/null 2>&1 && echo "  已解除：$p"
  done
  info "装回已卸载的系统应用"
  for p in $(list_of config/uninstall-list.txt); do
    if pkg_present "$p"; then echo "  已存在：$p"; continue; fi
    sh_ "pm install-existing $p" | sed 's/^/  /'
  done
  ok "应用已还原"
}

restore_home() {
  info "恢复官方桌面"
  sh_ "pm enable $OFFICIAL_LAUNCHER" | sed 's/^/  /'
  sh_ "cmd package set-home-activity --user 0 $OFFICIAL_LAUNCHER/.MainActivity" | sed 's/^/  /'
  echo "  当前 HOME：$(home_now)"
}

case "${1:-}" in
  --params) restore_params ;;
  --apps)   restore_apps ;;
  --home)   restore_home ;;
  --uninstall)
    conn
    info "卸载定制应用"
    sh_ "pm uninstall $AERIAL_PKG" | sed 's/^/  /'
    sh_ "pm uninstall $AUTOSTART_PKG" | sed 's/^/  /'
    sh_ "rm -rf /storage/self/primary/Android/data/$AERIAL_PKG"
    sh_ "rm -rf /storage/self/primary/Android/data/$AUTOSTART_PKG"
    restore_home
    ok "已卸载并恢复官方桌面" ;;
  "")
    conn
    restore_params
    restore_apps
    restore_home
    ok "盒子已还原" ;;
  *) die "不认识的参数：$1" ;;
esac

#!/bin/bash
# ============================================================
# 40 还原：把盒子恢复到接近出厂的状态
#
#   ./40-restore.sh             还原系统参数 + 启用所有被停用的应用 + 恢复官方桌面
#   ./40-restore.sh --params    只还原系统参数
#   ./40-restore.sh --apps      只启用被停用的应用
#   ./40-restore.sh --home      只把默认桌面还给官方
#   ./40-restore.sh --uninstall 卸载我们装的两个应用（保留官方桌面）
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
conn

restore_params() {
  info "还原系统参数"
  sh "settings put global window_animation_scale 1.0"
  sh "settings put global transition_animation_scale 1.0"
  sh "settings put global animator_duration_scale 1.0"
  sh "settings put global heads_up_notifications_enabled 1"
  sh "settings put global assisted_gps_enabled 1"
  sh "settings put global wifi_wakeup_enabled 1"
  SS="$REPO_ROOT/config/backup-screensaver.txt"
  if [ -f "$SS" ]; then
    old="$(cat "$SS" | tr -d '\r')"
    sh "settings put secure screensaver_components $old"
    echo "  屏保已还原为：$old"
  fi
  ok "参数已还原"
}

restore_apps() {
  info "启用所有被停用的应用"
  for p in $(sh "pm list packages -d" | sed 's/package://' | tr -d '\r'); do
    sh "pm enable $p" >/dev/null 2>&1 && echo "  已启用：$p"
  done
  ok "应用已还原"
}

restore_home() {
  info "恢复官方桌面"
  sh "pm enable $OFFICIAL_LAUNCHER" | sed 's/^/  /'
  sh "cmd package set-home-activity --user 0 $OFFICIAL_LAUNCHER/.MainActivity" | sed 's/^/  /'
  echo "  当前 HOME：$(home_now)"
}

case "$1" in
--params) restore_params ;;
--apps) restore_apps ;;
--home) restore_home ;;
--uninstall)
  info "卸载定制应用"
  sh "pm uninstall $AERIAL_PKG" | sed 's/^/  /'
  sh "pm uninstall $AUTOSTART_PKG" | sed 's/^/  /'
  sh "rm -rf /storage/self/primary/Android/data/$AERIAL_PKG"
  sh "rm -rf /storage/self/primary/Android/data/$AUTOSTART_PKG"
  restore_home
  ok "已卸载并恢复官方桌面" ;;
*)
  restore_params
  restore_apps
  restore_home
  ok "盒子已还原" ;;
esac

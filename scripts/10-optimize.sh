#!/bin/bash
# ============================================================
# 10 系统优化：停用不用的常驻应用 + 调系统参数 + 清垃圾
#
#   ./10-optimize.sh                   按 config/disable-list.txt 停用并调参（自动跳过官方桌面）
#   ./10-optimize.sh --with-launcher   连官方桌面一起停用（仅在已装好第三方桌面后执行！）
#   ./10-optimize.sh --clean           只清理调试残留与缓存，不动应用
#
# 风险说明：停用官方桌面后如果第三方桌面没接管，系统会卡在开机动画。
# 所以脚本默认不动它；要停用它必须先确认 HOME 已经是第三方桌面。
# 所有停用都是 pm disable-user，随时可 ./40-restore.sh 还原。
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
conn

LIST="$REPO_ROOT/config/disable-list.txt"
LOGDIR="$REPO_ROOT/backup"
mkdir -p "$LOGDIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"

# 备份当前状态，方便回滚
sh "pm list packages -d" | sed 's/package://' > "$LOGDIR/disabled-$STAMP.txt"
ok "已备份当前停用清单 → backup/disabled-$STAMP.txt"

if [ "$1" = "--clean" ]; then
  info "只清理垃圾文件"
  sh "rm -f /storage/self/primary/*.png /data/local/tmp/*.png"
  sh "pm trim-caches 999999999999" >/dev/null 2>&1
  ok "调试截图与缓存已清理"
  exit 0
fi

WITH_LAUNCHER=0
[ "$1" = "--with-launcher" ] && WITH_LAUNCHER=1

# ---- 1. 停用清单里的应用 ----
info "开始停用（清单：$LIST）"
# 用 fd 3 读清单：循环体里的 adb 会吃掉 stdin，直接用 < "$LIST" 的话
# 第一次迭代之后 stdin 就被 adb 抢光了，只读到第一行（表现出来是"只停用了第一个包"）
while read -r p <&3; do
  p="$(echo "$p" | tr -d '\r' | sed 's/package://' | sed 's/#.*//' | xargs)"
  [ -z "$p" ] && continue
  case "$p" in \#*) continue;; esac      # 清单里的分组注释

  if [ "$p" = "$OFFICIAL_LAUNCHER" ] && [ "$WITH_LAUNCHER" -eq 0 ]; then
    warn "跳过官方桌面 $p（未加 --with-launcher）"
    continue
  fi
  if [ "$p" = "$OFFICIAL_LAUNCHER" ] && [ "$WITH_LAUNCHER" -eq 1 ]; then
    cur="$(home_now)"
    case "$cur" in
      *"$OFFICIAL_LAUNCHER"*) die "HOME 仍是官方桌面，停它会开不了机。先把 Aerial/其它桌面设为 HOME 再来。";;
    esac
  fi
  if ! sh "pm list packages $p" | grep -q "$p"; then
    warn "$p 未安装，跳过"
    continue
  fi
  if sh "pm list packages -d" | grep -q "$p"; then
    echo "  已停用：$p"
    continue
  fi
  sh "pm disable-user --user 0 $p" | sed 's/^/  /'
done 3< "$LIST"

# ---- 2. 系统参数 ----
info "调整系统参数"
sh "settings put global window_animation_scale 0.5"
sh "settings put global transition_animation_scale 0.5"
sh "settings put global animator_duration_scale 0.5"
sh "settings put global heads_up_notifications_enabled 0"
sh "settings put global assisted_gps_enabled 0"
sh "settings put global wifi_wakeup_enabled 0"
echo "  window/transition/animator = 0.5，悬浮通知、辅助 GPS、WiFi 唤醒 = 关"

# ---- 3. 屏保：系统默认是广告屏保，换成 Aerial 的航拍屏保 ----
if sh "pm list packages $AERIAL_PKG" | grep -q "$AERIAL_PKG"; then
  info "换掉系统广告屏保"
  OLD_SS="$(sh "settings get secure screensaver_components")"
  # 只在还是出厂值时才备份，避免重启后把广告组件当成"原值"反复覆盖备份
  if [ "$OLD_SS" = "$STOCK_DREAM" ] || [ ! -s "$REPO_ROOT/config/backup-screensaver.txt" ]; then
    echo "$OLD_SS" > "$REPO_ROOT/config/backup-screensaver.txt"
    echo "  原值已备份 → config/backup-screensaver.txt（$OLD_SS）"
  fi
  restore_dream
  sh "settings put secure screensaver_enabled 1" >/dev/null
else
  warn "没装 Aerial，保留系统屏保"
fi

# ---- 4. 清理 ----
info "清理调试残留与缓存"
sh "rm -f /storage/self/primary/*.png /data/local/tmp/*.png"
sh "pm trim-caches 999999999999" >/dev/null 2>&1
sh "am force-stop com.android.provision" >/dev/null 2>&1   # 开机向导，device_provisioned=1 后不再需要

# 已停用的应用如果还有进程在跑，顺手杀掉（disable-user 不会杀已有进程）
for p in $(sh "pm list packages -d" | sed 's/package://' | tr -d '\r'); do
  sh "am force-stop $p" >/dev/null 2>&1
done

echo
echo "优化后可用内存：$(sh "cat /proc/meminfo | grep MemAvailable")"
ok "优化完成。回滚：./40-restore.sh"

#!/usr/bin/env bash
# ============================================================
# 60 看门狗：盒子一开机（或固件中途把包恢复）就自动补回停用和屏保
#
#   ./scripts/60-watch-reboot.sh                常驻轮询，默认 30 秒一次
#   ./scripts/60-watch-reboot.sh --once         只检查一次，缺什么补什么，然后退出
#   ./scripts/60-watch-reboot.sh --interval 60  改轮询间隔
#   ./scripts/60-watch-reboot.sh --dry-run      只报告，不动盒子
#
# 为什么需要它：
#   固件会隔一阵子把 6 个包恢复启用（ottstatsv2 / ott.advert.app / skyappupdate /
#   logcollector / voiceassistant / skymediacenter），开机后尤其明显，屏保也一起被抢回广告。
#   盒子自己做不到自愈：pm disable-user 只有 adb shell（UID 2000）有权限，应用进程执行会
#   SecurityException，而第三方开机广播又被固件全拦。所以只能从 PC 这边盯着。
#
# 判定方式不是"有没有重启"，而是"该停的停了没" —— 这样固件在开机后任意时刻恢复都能接住。
# 每次轮询只有 2 次 adb 调用（读停用列表 + 读屏保），没缺就什么都不做，开销可以忽略。
#
# 想让它开机自己跑起来，加到 Windows 计划任务（登录时触发）：
#   schtasks /create /tn "SkyworthBoxWatch" /sc onlogon /f ^
#     /tr "wsl bash -lc 'cd /c/path/to/skyworth-p3-launcher-kit && ./scripts/60-watch-reboot.sh'"
#   或者更简单：把 --once 挂到计划任务的"每天重复"里，每 5 分钟跑一次。
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

LIST="$REPO_ROOT/config/disable-list.txt"
LOG="$REPO_ROOT/backup/watch-reboot.log"
INTERVAL=30
ONCE=0
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1; shift;;
    --dry-run) DRY=1; ONCE=1; shift;;
    --interval) INTERVAL="${2:-30}"; shift 2;;
    -h|--help) sed -n '2,25p' "$0"; exit 0;;
    *) die "不认识的参数：$1（用 --help 看用法）";;
  esac
done
mkdir -p "$(dirname "$LOG")"

# 清单里该停用的包（剥注释、只要 package: 开头的行；官方桌面由 10-optimize.sh 决定，不算）
WANT="$(grep '^package:' "$LIST" | sed 's/^package://' | sed 's/#.*//' | tr -d '\r' | xargs -n1 \
        | grep -v "^$OFFICIAL_LAUNCHER$")"

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

# 返回：缺失的包名，一行一个
missing() {
  local have="$1" p
  while read -r p; do
    [ -z "$p" ] && continue
    echo "$have" | grep -qx "package:$p" || echo "$p"
  done <<< "$WANT"
}

check_once() {
  # Git Bash 每条命令结束会清掉 adb daemon，所以每次轮询都重连
  "$ADB" connect "$BOX" >/dev/null 2>&1
  if ! "$ADB" -s "$BOX" shell "echo ok" >/dev/null 2>&1; then
    echo "  $(date '+%F %T') 连不上 $BOX（关机/休眠/网络）— 下次再试"
    return 0
  fi
  local have ss miss
  have="$("$ADB" -s "$BOX" shell "pm list packages -d" 2>/dev/null | tr -d '\r')"
  ss="$("$ADB" -s "$BOX" shell "settings get secure screensaver_components" 2>/dev/null | tr -d '\r')"
  miss="$(missing "$have")"

  if [ -z "$miss" ] && [ "$ss" = "$AERIAL_DREAM" ]; then
    echo "  $(date '+%F %T') 状态正常：$(echo "$have" | grep -c .) 个包已停用，屏保是 AerialDream"
    return 0
  fi

  [ -n "$miss" ] && log "发现被恢复：$(
    echo "$miss" | tr '\n' ' ')" 
  [ "$ss" != "$AERIAL_DREAM" ] && log "屏保被抢回：${ss:-（空）}"

  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] 上面这些本该补回，本次没动盒子"
    return 0
  fi
  log "补回中：跑 10-optimize.sh"
  BOX_TARGET="$BOX" "$REPO_ROOT/scripts/10-optimize.sh" 2>&1 | grep -E "new state|屏保：|内存" | sed 's/^/    /'
  log "补回完成"
}

info "看门狗启动：$BOX，每 ${INTERVAL}s 检查一次（Ctrl+C 退出）。日志：$LOG"
echo
if [ "$ONCE" -eq 1 ]; then
  check_once
  exit 0
fi

offline=0
while :; do
  check_once
  sleep "$INTERVAL"
done

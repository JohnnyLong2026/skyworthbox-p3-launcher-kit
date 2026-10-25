#!/bin/bash
# ============================================================
# 30 设置定时启动的目标应用与延迟
#
#   ./30-set-autostart.sh <包名> <显示名> <秒数>
#   例：./30-set-autostart.sh com.huawei.himovceie 影视仓 5
#
#   ./30-set-autostart.sh --list    列出可选的目标应用
#   ./30-set-autostart.sh --status  查看当前配置
#   ./30-set-autostart.sh --reset   还原（清空配置，开机不再跳转）
#
# 提醒浮层固定倒计时 9 秒（可在源码 ReminderActivity 的 NOTICE_SECONDS 改）；
# 这里的秒数是「进桌面后等多少秒再弹提醒」。
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
conn

case "$1" in
--list)
  echo "可选目标应用（有 TV 启动入口的第三方应用）："
  for p in $(sh "pm list packages -3" | sed 's/package://' | tr -d '\r'); do
    [ "$p" = "$AUTOSTART_PKG" ] && continue
    [ "$p" = "$AERIAL_PKG" ] && continue
    main="$(sh "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER $p 2>/dev/null | tail -1")"
    [ -z "$main" ] && main="$(sh "cmd package resolve-activity --brief $p 2>/dev/null | tail -1")"
    [ -n "$main" ] && echo "  $p"
  done
  exit 0
  ;;
--status)
  echo "当前配置："
  sh "cat /data/data/$AUTOSTART_PKG/shared_prefs/*.xml 2>/dev/null"
  exit 0
  ;;
--reset)
  sh "am start -n $AUTOSTART_PKG/com.skyworthdigital.autostart.MainActivity --ez reset true" >/dev/null 2>&1
  # 直接清配置更可靠
  sh "pm clear $AUTOSTART_PKG" >/dev/null 2>&1
  ok "已还原：开机后不再跳转任何应用"
  exit 0
  ;;
esac

PKG="$1"; LABEL="$2"; DELAY="$3"
[ -n "$PKG" ] || die "用法：$0 <包名> <显示名> <秒数>   （--list 查看可选应用）"
[ -n "$LABEL" ] || LABEL="$PKG"
[ -n "$DELAY" ] || DELAY=5

sh "pm list packages $PKG" | grep -q "$PKG" || die "$PKG 未安装"

# MainActivity 是 singleTask，二次启动走 onNewIntent，源码里两边都处理了配置注入
sh "am start -n $AUTOSTART_PKG/com.skyworthdigital.autostart.MainActivity \
     --es setup_pkg $PKG --es setup_label $LABEL --ei setup_delay $DELAY" | sed 's/^/  /'

sleep 2
echo "写入结果："
sh "cat /data/data/$AUTOSTART_PKG/shared_prefs/*.xml 2>/dev/null" | sed 's/^/  /'
ok "已设置：进桌面 $DELAY 秒后提醒，倒计时结束跳转 $LABEL（$PKG）"

#!/bin/bash
# ============================================================
# 00 体检：跑一遍，把盒子现状打成一份报告
#   输出：硬件、系统、HOME 归属、内存 Top、第三方应用、已停用清单、定时启动配置
#   只读，不改任何东西
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
conn

echo "==================== 盒子体检报告 ===================="
echo "生成时间 : $(date '+%F %T')"
echo "设备地址 : $BOX"
echo

echo "---- 设备 ----"
echo "型号     : $(sh getprop ro.product.model)"
echo "机型     : $(sh getprop ro.product.device) / $(sh getprop ro.product.board)"
echo "Android  : $(sh getprop ro.build.version.release)  SDK $(sh getprop ro.build.version.sdk)"
echo "序列号   : $(sh getprop ro.serialno)"
echo "分辨率   : $(sh wm size)"
echo "CPU ABI  : $(sh getprop ro.product.cpu.abi)"
echo

echo "---- 存储 ----"
sh "df -h /data 2>/dev/null | tail -1"
echo

echo "---- 内存 ----"
sh "cat /proc/meminfo | grep -E 'MemTotal|MemAvailable|MemFree'"
echo
echo "内存占用 Top 10："
sh "dumpsys meminfo 2>/dev/null | sed -n '/Total PSS by process/,/^$/p' | head -12"
echo

echo "---- 默认桌面 ----"
echo "当前 HOME : $(home_now)"
echo "官方桌面 $OFFICIAL_LAUNCHER 状态："
sh "dumpsys package $OFFICIAL_LAUNCHER 2>/dev/null | grep 'User 0:' | head -1"
echo

echo "---- 第三方应用 ----"
# enabled 数值：0=启用 2=已停用 3=用户停用 4=停用至使用
for p in $(sh "pm list packages -3" | sed 's/package://' | tr -d '\r'); do
  n="$(sh "dumpsys package $p 2>/dev/null | grep 'User 0:' | head -1" | grep -o 'enabled=[0-9]*' | cut -d= -f2)"
  case "$n" in
    0) st="启用" ;;
    2) st="已停用" ;;
    3) st="已停用(用户)" ;;
    4) st="停用至使用" ;;
    *) st="状态 $n" ;;
  esac
  echo "  $p  [$st]"
done
echo

echo "---- 已停用（disable-user）----"
sh "pm list packages -d" | sed 's/package:/  /'
echo

echo "---- 定时启动配置 ----"
if sh "pm list packages $AUTOSTART_PKG" | grep -q "$AUTOSTART_PKG"; then
  sh "cat /data/data/$AUTOSTART_PKG/shared_prefs/*.xml 2>/dev/null"
  echo "  提醒服务是否在跑：$(sh "ps -A | grep -c $AUTOSTART_PKG")"
else
  echo "  未安装 $AUTOSTART_PKG"
fi
echo

echo "---- 系统参数 ----"
for k in window_animation_scale transition_animation_scale animator_duration_scale \
         heads_up_notifications_enabled assisted_gps_enabled wifi_wakeup_enabled adb_enabled; do
  echo "  $k = $(sh "settings get global $k 2>/dev/null")"
done
echo
ok "体检完成（未做任何修改）"

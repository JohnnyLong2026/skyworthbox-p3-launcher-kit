#!/usr/bin/env bash
# 重启后状态体检：HOME / 屏保 / 停用包 / 运行进程 / 内存
# 用法：./scripts/90-check-status.sh [盒子IP]
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/box.conf
IP="${1:-${BOX_TARGET%:*}}"
adb connect "$IP:5555" >/dev/null 2>&1
S() { adb -s "$IP:5555" shell "$@" 2>/dev/null | tr -d '\r'; }

echo "===== 1. 桌面 HOME ====="
S cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1
echo "Aerial: $(S dumpsys package com.ktcp.launcher.aerial 2>/dev/null | grep -m1 'versionName=' | tr -s ' ')"
echo "官方桌面 sky2dlauncherv4: $(S pm list packages -d com.skyworthdigital.sky2dlauncherv4 | grep -q . && echo 已停用 || echo 仍启用)"

echo
echo "===== 2. 屏保 ====="
echo "组件: $(S settings get secure screensaver_components)"
echo "开关: $(S settings get secure screensaver_enabled)"

echo
echo "===== 3. 停用包（$(S pm list packages -d | wc -l) 个）====="
S pm list packages -d | sed 's/package:/  /' | sort

echo
echo "===== 4. 正在运行的应用进程（剩下的就是开机后常驻的）====="
# 一次 ps 拿全表，再用 fd 3 喂给 while：循环体里的 adb 会抢 stdin，直接 < file 会只读到第一行
S ps -A -o PID,USER,NAME > /tmp/psbox.txt 2>/dev/null
S dumpsys activity activities > /tmp/actbox.txt 2>/dev/null
# 只看应用进程：名字带点号（包名），丢掉内核线程 [xxx] 和 android.hardware.* 这类 native 服务
awk '$3 ~ /^[a-z]/ && $3 ~ /\./ && $3 !~ /@/ && $3 !~ /^\[/ && $3 !~ /^android\.hardware\./ && ($2 ~ /^u0_/ || $2 == "system")' /tmp/psbox.txt \
  | awk '{print $2, $3}' | sort -u > /tmp/procs.txt
while read -r u n <&3; do
  pss=$(S dumpsys meminfo "$n" 2>/dev/null | grep -m1 -oE 'TOTAL +[0-9]+' | grep -oE '[0-9]+')
  fg=""; grep -q "$n" /tmp/actbox.txt 2>/dev/null && fg="前台"
  printf "  %-8s %-44s Pss=%-8s %s\n" "$u" "$n" "${pss:-?}KB" "$fg"
done 3< /tmp/procs.txt | sort -t= -k2 -rn | head -25

echo
echo "===== 5. 内存 ====="
S cat /proc/meminfo | grep -E 'MemTotal|MemAvailable|MemFree'
rm -f /tmp/psbox.txt /tmp/procs.txt

#!/bin/bash
# ============================================================
# 公共库：ADB 连接 / 设备信息 / 常用封装
# 所有脚本统一 source 本文件
#
# 用法：source "$(dirname "$0")/lib.sh"
#
# 两个环境坑（本仓库所有脚本都已处理）：
#   1. Git Bash 下 adb daemon 在每条命令结束后会被清掉，所以每条命令开头都要重新 connect
#   2. adb pull/push 的远程路径会被 Git Bash 转成 Windows 路径，所以统一用 adb_pull/adb_push
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX_CONF="$REPO_ROOT/scripts/box.conf"

# ---------- 盒子地址 ----------
# 优先读 scripts/box.conf，其次环境变量 BOX_TARGET
if [ -f "$BOX_CONF" ]; then
  # shellcheck disable=SC1090
  source "$BOX_CONF"
fi
BOX="${BOX_TARGET:-192.168.1.100:5555}"
# 示例地址照抄会连不上，给个明确提示，别让人对着超时日志猜
if [ "$BOX" = "192.168.1.100:5555" ]; then
  echo "[!] 当前用的是示例地址 $BOX，还没改成你自己的盒子 IP。" >&2
  echo "    编辑 scripts/box.conf 的 BOX_TARGET，或用 BOX_TARGET=ip:5555 临时覆盖。" >&2
fi

# ---------- 定位 adb ----------
find_adb() {
  if command -v adb >/dev/null 2>&1; then echo "$(command -v adb)"; return; fi
  [ -n "$ANDROID_HOME" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ] && { echo "$ANDROID_HOME/platform-tools/adb"; return; }
  [ -n "$ANDROID_SDK_ROOT" ] && [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ] && { echo "$ANDROID_SDK_ROOT/platform-tools/adb"; return; }
  # Windows winget 安装的 platform-tools
  local w="$LOCALAPPDATA/Microsoft/WinGet/Packages"
  [ -n "$w" ] && [ -d "$w" ] && {
    local hit
    hit="$(find "$w" -maxdepth 4 -name adb.exe -path "*platform-tools*" 2>/dev/null | head -1)"
    [ -n "$hit" ] && { echo "$hit"; return; }
  }
  echo ""
}

ADB="$(find_adb)"

die() { echo "[错误] $*" >&2; exit 1; }
info() { echo "[信息] $*"; }
ok() { echo "[完成] $*"; }
warn() { echo "[提示] $*"; }

[ -n "$ADB" ] || die "找不到 adb。请安装 Android platform-tools，或设置 ANDROID_HOME 环境变量。"

# ---------- 连接 ----------
# 每条 Bash 命令开头都要调用（Git Bash 会清掉 daemon）
conn() {
  "$ADB" connect "$BOX" >/dev/null 2>&1
  sleep 1
  "$ADB" -s "$BOX" shell "echo ok" >/dev/null 2>&1 \
    || die "连不上 $BOX。确认盒子已开机（休眠时 ADB 无响应，需遥控器唤醒），且已在设置里开启 ADB 网络调试。"
}

# ---------- 执行 ----------
# 用 "$*" 而不是 "$1"：调用处写成 sh getprop ro.product.model（不带引号）也能正确传过去
sh() { "$ADB" -s "$BOX" shell "$*" 2>&1 | tr -d '\r'; }

adb_pull() { MSYS_NO_PATHCONV=1 "$ADB" -s "$BOX" pull "$1" "$2" >/dev/null 2>&1; }
adb_push() { MSYS_NO_PATHCONV=1 "$ADB" -s "$BOX" push "$1" "$2" >/dev/null 2>&1; }

# 当前默认桌面解析结果
home_now() {
  sh "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1" | awk '{print $NF}'
}

# 盒子基本信息
box_model() { sh "getprop ro.product.model" ; }
box_android() { sh "getprop ro.build.version.release" ; }

# ---------- 常量 ----------
OFFICIAL_LAUNCHER="com.skyworthdigital.sky2dlauncherv4"
AERIAL_PKG="com.ktcp.launcher.aerial"
AERIAL_HOME="$AERIAL_PKG/app.orchard.tv.MainActivity"
AERIAL_DREAM="$AERIAL_PKG/app.orchard.tv.dream.AerialDream"
# 出厂屏保：创维广告组件。每次开机固件都会把这个值写回 screensaver_components，
# 所以换屏保不是一次性的，装完 Aerial / 每次重启后都要重设（见 restore_dream）。
# 注意：广告包 ott.advert.app 已经在卸载清单里，这个组件其实不存在了 —— 固件仍然
# 照写不误，结果就是"屏保指向一个不存在的服务"，等于没有屏保。所以每次开机后
# 更要记得 restore_dream 把它改回 AerialDream。
STOCK_DREAM="com.skyworthdigital.ott.advert.app/com.skyworthdigital.ott.advert.app.screensaver.ScreenSaverService"
AUTOSTART_PKG="com.ktcp.launcher.autostart"
AUTOSTART_SVC="com.skyworthdigital.autostart.ReminderService"

# ---------- 顽固包 ----------
# 有一批包光靠 disable-user 停不住：固件会把它们恢复启用，而且它们跑在 system UID 下，
# 开机时系统直接给它们发广播（logcat -b events 里 am_proc_start 照样出现）。
#
# 试过 pm suspend，实测不但没用还更糟：suspend 的包照样被开机广播拉起来，
# 而且拉起来之后退不出去 —— 6 个包全部常驻，合计多占约 107MB（不 suspend 时
# 只有 ottstatsv2 的 15MB 常驻，其余起来后自行退出）。所以脚本不做 suspend，
# 这里只留 unsuspend，用来收拾别人（或以前）误 suspend 过的情况。
STUBBORN_LIST="$REPO_ROOT/config/stubborn-list.txt"

stubborn_packages() {
  [ -f "$STUBBORN_LIST" ] || return 0
  grep -v '^[[:space:]]*#' "$STUBBORN_LIST" | sed 's/#.*//' | tr -d '\r' | xargs -n1 2>/dev/null | grep -v '^$'
}

unsuspend_stubborn() {
  local p n=0
  for p in $(stubborn_packages); do
    [ -z "$p" ] && continue
    sh "pm unsuspend $p" >/dev/null 2>&1 && { echo "  已解除 suspend：$p"; n=$((n+1)); }
  done
  [ "$n" -eq 0 ] && echo "  没有处于 suspend 的包"
  return 0
}

# ---------- 卸载清单 ----------
# 这几个包连停用都保不住：固件云端下发「系统控制列表」后会逐个恢复启用。
# 唯一的解法是让包对 user 0 不存在 —— 云端那步 setApplicationEnabledSetting
# 会抛 Unknown package。卸载前会把 APK 备份到 /sdcard/p3-backup/，随时可
# pm install-existing 装回（40-restore.sh 的 --apps 会做这件事）。
UNINSTALL_LIST="$REPO_ROOT/config/uninstall-list.txt"
BOX_BACKUP_DIR="/sdcard/p3-backup"

uninstall_packages() {
  [ -f "$UNINSTALL_LIST" ] || return 0
  # 和 disable-list 一样带 package: 前缀，这里先剥掉；行内 # 注释也要去掉
  grep -v '^[[:space:]]*#' "$UNINSTALL_LIST" | sed 's/#.*//; s/^package://' | tr -d '\r' | xargs -n1 2>/dev/null | grep -v '^$'
}

# 包当前是否对 user 0 可见（卸载后为否）。
# 用 -x 整行匹配：pm list packages 的参数是前缀匹配，会把 com.a 和 com.ab 混在一起。
pkg_present() { sh "pm list packages" | grep -qx "package:$1"; }

# ---------- 屏保 ----------
# 固件在开机时会把 screensaver_components 写回广告组件，所以这不是一次性设置：
# 装完 Aerial、每次重启之后都要调用一次。已是 Aerial 时什么都不做。
restore_dream() {
  local cur
  cur="$(sh "settings get secure screensaver_components")"
  [ "$cur" = "$AERIAL_DREAM" ] && return 0
  sh "settings put secure screensaver_components $AERIAL_DREAM" >/dev/null
  sh "settings put secure screensaver_enabled 1" >/dev/null
  echo "  屏保：${cur:-（空）} → $AERIAL_DREAM"
}

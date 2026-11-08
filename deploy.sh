#!/usr/bin/env bash
# ============================================================
# 创维小湃 P3（Q5001 / cupid_p2）盒子改造 · 一条命令版
#
#   bash deploy.sh               全流程：装桌面 → 设 HOME → 补权限 → 卸载顽固包 → 系统优化
#   bash deploy.sh --check       只体检，不改任何东西
#   bash deploy.sh --optimize    只重跑优化（重启后补回屏保/停用包，约 10 秒）
#   bash deploy.sh --watch       看门狗：被固件恢复的包和屏保自动补回，Ctrl+C 退出
#   bash deploy.sh --build       从源码编译 Aerial 再装（需 JDK 17 + Android SDK）
#   bash deploy.sh --dry-run     全流程但不动盒子，只报告会做什么
#
# 盒子地址：BOX_TARGET=192.168.1.x:5555 bash deploy.sh
#          或写进 box.conf（BOX_TARGET=...），环境变量优先
#
# 全程免 root：只用 adb shell（uid 2000）能做的 pm/settings 操作。
# 还原：bash restore.sh
# ============================================================
# 不加 pipefail：`adb ... | grep -q` 里 grep 命中即退出，上游 printf 会收到 SIGPIPE，
# pipefail 把整条管道判为 141，is-installed 之类的判断会全部误判成"没有"。
set -u
cd "$(dirname "$0")" || exit 1
ROOT="$PWD"

# ---------------- 基础 ----------------
die()  { echo "[错误] $*" >&2; exit 1; }
info() { echo "[信息] $*"; }
ok()   { echo "[完成] $*"; }
warn() { echo "[提示] $*"; }

[ -f box.conf ] && . ./box.conf
BOX="${BOX_TARGET:-192.168.1.100:5555}"
case "$BOX" in
  192.168.1.100:5555)
    warn "当前是示例地址 $BOX。用 BOX_TARGET=你的盒子IP:5555 覆盖，或改 box.conf"
    ;;
esac

find_adb() {
  command -v adb 2>/dev/null && return
  [ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ] && { echo "$ANDROID_HOME/platform-tools/adb"; return; }
  [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ] && { echo "$ANDROID_SDK_ROOT/platform-tools/adb"; return; }
  local w="${LOCALAPPDATA:-}/Microsoft/WinGet/Packages"
  [ -d "$w" ] && find "$w" -maxdepth 4 -name adb.exe -path "*platform-tools*" 2>/dev/null | head -1
}
ADB="$(find_adb)"
[ -n "$ADB" ] || die "找不到 adb，请装 Android platform-tools 或设置 ANDROID_HOME"

# 每条命令都要重连：Git Bash 下 adb daemon 会在命令结束时被清掉
conn() {
  "$ADB" connect "$BOX" >/dev/null 2>&1
  sleep 1
  "$ADB" -s "$BOX" shell "echo ok" >/dev/null 2>&1 \
    || die "连不上 $BOX。盒子休眠时 ADB 无响应（遥控器唤醒），确认已开 ADB 网络调试。"
}
sh_() {
  local out
  out="$("$ADB" -s "$BOX" shell "$*" 2>&1 | tr -d '\r')"
  # 盒子休眠或掉线时 adb 只回一行错误，命令本身仍返回 0。不拦住的话脚本会
  # 拿空字符串继续判断（例如"没装 Aerial"），给出完全错误的结论。
  case "$out" in
    *"device offline"*|*"device '"*"' not found"*|*"cannot connect to"*|*"no devices/emulators found"*)
      die "与 $BOX 的连接中断（盒子多半休眠了，按遥控器唤醒后重跑）" ;;
  esac
  printf '%s\n' "$out"
}

# Windows 版 adb 不认 /c/foo.apk，会报 failed to stat 但脚本照跑，看着像装好了
win_path() {
  case "$1" in
    /[a-zA-Z]/*) printf '%s:%s' "$(printf '%s' "${1:1:1}" | tr '[:lower:]' '[:upper:]')" "${1:2}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# ---------------- 常量 ----------------
OFFICIAL_LAUNCHER="com.skyworthdigital.sky2dlauncherv4"
AERIAL_PKG="com.ktcp.launcher.aerial"
AERIAL_HOME="$AERIAL_PKG/app.orchard.tv.MainActivity"
AERIAL_DREAM="$AERIAL_PKG/app.orchard.tv.dream.AerialDream"
# 出厂屏保是创维广告组件。固件每次开机都把这个值写回 screensaver_components，
# 而广告包在我们的卸载清单里 —— 结果就是"屏保指向不存在的服务"，等于没屏保。
STOCK_DREAM="com.skyworthdigital.ott.advert.app/com.skyworthdigital.ott.advert.app.screensaver.ScreenSaverService"
AERIAL_VER="1.88"

home_now() { sh_ "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1" | awk '{print $NF}'; }

restore_dream() {
  local cur; cur="$(sh_ "settings get secure screensaver_components")"
  [ "$cur" = "$AERIAL_DREAM" ] && return 0
  sh_ "settings put secure screensaver_components $AERIAL_DREAM" >/dev/null
  sh_ "settings put secure screensaver_enabled 1" >/dev/null
  echo "  屏保：${cur:-（空）} → $AERIAL_DREAM"
}

# 清单解析：剥 package: 前缀与行内注释
list_of() {
  [ -f "$1" ] || return 0
  grep -v '^[[:space:]]*#' "$1" | sed 's/#.*//; s/^package://' | tr -d '\r' | xargs -n1 2>/dev/null | grep -v '^$'
}

# 用 case 做整行匹配，不过管道：pm list packages 是前缀匹配，com.a 会连上 com.ab
pkg_present() {
  case $'\n'"$(sh_ "pm list packages")"$'\n' in
    *$'\n'"package:$1"$'\n'*) return 0 ;;
  esac
  return 1
}
pkg_disabled() {
  case $'\n'"$(sh_ "pm list packages -d")"$'\n' in
    *$'\n'"package:$1"$'\n'*) return 0 ;;
  esac
  return 1
}

# ---------------- 1. 装桌面并设为 HOME ----------------
deploy_aerial() {
  local apk="$ROOT/apk/aerial-tv-$AERIAL_VER-p3.apk"
  if [ "$BUILD" -eq 1 ]; then
    command -v java >/dev/null 2>&1 || die "需要 JDK 17"
    [ -n "${ANDROID_HOME:-}" ] || [ -n "${ANDROID_SDK_ROOT:-}" ] || die "需要 ANDROID_HOME 指向 Android SDK"
    local work="${AERIAL_SRC:-$ROOT/../aerial-tv}"
    [ -d "$work/.git" ] || git clone https://github.com/pengchujin/aerial-tv "$work" || die "clone 失败"
    ( cd "$work" && git checkout -q "v$AERIAL_VER" ) || warn "切不到 v$AERIAL_VER，用当前 HEAD"
    ( cd "$work" && git apply --check "$ROOT/patches/aerial-tv-p3.patch" 2>/dev/null && git apply "$ROOT/patches/aerial-tv-p3.patch" ) \
      || ( cd "$work" && git apply --3way "$ROOT/patches/aerial-tv-p3.patch" ) \
      || die "补丁应用失败，检查上游版本是否变了"
    info "编译中（首次约 9 分钟）…"
    ( cd "$work" && ./gradlew assembleStandardRelease ) || die "编译失败"
    cp "$(find "$work/app/build/outputs/apk/standard/release" -name '*.apk' | head -1)" "$apk"
  fi
  [ -f "$apk" ] || die "找不到 $apk"

  info "安装 $(basename "$apk")"
  "$ADB" -s "$BOX" install -r "$(win_path "$apk")" | tr -d '\r' | sed 's/^/  /'
  sh_ "monkey -p $AERIAL_PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1

  info "设为默认桌面"
  sh_ "cmd package set-home-activity --user 0 $AERIAL_HOME" | sed 's/^/  /'
  # 先设再验：出厂的 resolve 会返回 ResolverActivity（选择器），里面没有任何包名，
  # 设之前查会误判成"白名单没放行"
  sh_ "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" | grep -q "$AERIAL_PKG" \
    || die "HOME 没落到 $AERIAL_PKG。多半是白名单没放行（applicationId 必须以 com.ktcp.launcher 开头）"
  sh_ "pm disable-user --user 0 $OFFICIAL_LAUNCHER" | sed 's/^/  /'
  echo "  当前 HOME：$(home_now)"
  restore_dream
}

# ---------------- 2. 补权限 ----------------
grant_perms() {
  pkg_present "$AERIAL_PKG" || die "没装 $AERIAL_PKG"
  info "运行时权限"
  local perm out
  for perm in android.permission.WRITE_SECURE_SETTINGS android.permission.SYSTEM_ALERT_WINDOW \
              android.permission.PACKAGE_USAGE_STATS android.permission.ACCESS_FINE_LOCATION \
              android.permission.ACCESS_COARSE_LOCATION; do
    out="$(sh_ "pm grant $AERIAL_PKG $perm" | grep -v '^$' || true)"
    [ -z "$out" ] && echo "  ok      $perm" || echo "  跳过    $perm（走 appops）"
  done
  info "appops"
  local op
  for op in WRITE_SETTINGS REQUEST_INSTALL_PACKAGES SYSTEM_ALERT_WINDOW; do
    sh_ "appops set $AERIAL_PKG $op allow" >/dev/null 2>&1; echo "  allow   $op"
  done
  info "通知监听"
  sh_ "settings put secure enabled_notification_listeners $AERIAL_PKG/app.orchard.tv.guard.RevivalListener" >/dev/null 2>&1
  info "守护无障碍服务"
  # 必须把厂商原有的拼在后面，直接覆盖会关掉创维语音助手的无障碍
  local cur guard="$AERIAL_PKG/app.orchard.tv.guard.HomeGuardService"
  cur="$(sh_ "settings get secure enabled_accessibility_services")"
  case ":$cur:" in
    *":$guard:"*) echo "  已在列表里" ;;
    *)
      if [ -z "$cur" ] || [ "$cur" = "null" ]; then sh_ "settings put secure enabled_accessibility_services $guard" >/dev/null 2>&1
      else sh_ "settings put secure enabled_accessibility_services $cur:$guard" >/dev/null 2>&1; fi
      sh_ "settings put secure accessibility_enabled 1" >/dev/null 2>&1
      echo "  已登记" ;;
  esac
  restore_dream
}

# ---------------- 3. 卸载顽固包 ----------------
uninstall_stubborn() {
  local p src ver dst out n=0
  sh_ "mkdir -p /sdcard/p3-backup" >/dev/null 2>&1
  # 用 list_of 解析：注释行与行内 # 说明必须先剥掉，否则会把中文注释当包名去查
  for p in $(list_of config/uninstall-list.txt); do
    if ! pkg_present "$p"; then echo "  已不存在：$p"; continue; fi
    src="$(sh_ "pm path $p" | sed 's/package://' | head -1)"
    ver="$(sh_ "dumpsys package $p 2>/dev/null | grep -m1 versionName" | tr -d ' ' | cut -d= -f2)"
    dst="/sdcard/p3-backup/$p.apk"
    if [ -n "$src" ] && ! sh_ "[ -s $dst ] && echo has" | grep -q has; then
      sh_ "cp $src $dst" >/dev/null 2>&1 && echo "  已备份：$(basename "$dst")（$ver）"
    fi
    if [ "$DRY" -eq 1 ]; then echo "  [dry-run] 将卸载：$p（$ver）"; continue; fi
    out="$(sh_ "pm uninstall -k --user 0 $p")"
    case "$out" in
      *Success*) echo "  已卸载：$p（$ver）"; n=$((n+1)) ;;
      *) warn "$p 卸载失败：$out" ;;
    esac
  done
  echo "  本次卸载 $n 个；还原用 bash restore.sh --apps"
}

# ---------------- 4. 系统优化 ----------------
optimize() {
  local p cur
  printf '%s\n' "  备份停用清单 → backup/disabled-$(date '+%Y%m%d-%H%M%S').txt"
  mkdir -p backup && sh_ "pm list packages -d" | sed 's/package://' > "backup/disabled-$(date '+%Y%m%d-%H%M%S').txt"

  info "停用清单（config/disable-list.txt）"
  # fd 3 读清单：循环体里的 adb 会抢 stdin，用 < file 只读到第一行
  while read -r p <&3; do
    p="$(printf '%s' "$p" | tr -d '\r' | sed 's/package://; s/#.*//' | xargs)"
    [ -z "$p" ] && continue
    case "$p" in \#*) continue;; esac
    if [ "$p" = "$OFFICIAL_LAUNCHER" ]; then
      warn "跳过官方桌面（Home 已交给 Aerial，停它会在桌面崩掉时开不了机）"
      continue
    fi
    pkg_present "$p" || { warn "$p 未安装"; continue; }
    pkg_disabled "$p" && { echo "  已停用：$p"; continue; }
    [ "$DRY" -eq 1 ] && { echo "  [dry-run] 将停用：$p"; continue; }
    sh_ "pm disable-user --user 0 $p" | sed 's/^/  /'
  done 3< config/disable-list.txt

  if [ "$DRY" -eq 0 ]; then
    info "系统参数"
    sh_ "settings put global window_animation_scale 0.5" >/dev/null
    sh_ "settings put global transition_animation_scale 0.5" >/dev/null
    sh_ "settings put global animator_duration_scale 0.5" >/dev/null
    sh_ "settings put global heads_up_notifications_enabled 0" >/dev/null
    sh_ "settings put global assisted_gps_enabled 0" >/dev/null
    sh_ "settings put global wifi_wakeup_enabled 0" >/dev/null
    echo "  动画 0.5x；悬浮通知、辅助 GPS、WiFi 唤醒 关"
  fi

  if pkg_present "$AERIAL_PKG"; then
    info "屏保"
    cur="$(sh_ "settings get secure screensaver_components")"
    if [ "$cur" = "$STOCK_DREAM" ] || [ ! -s config/backup-screensaver.txt ]; then
      printf '%s\n' "$cur" > config/backup-screensaver.txt
      echo "  原值已备份 → config/backup-screensaver.txt"
    fi
    [ "$DRY" -eq 0 ] && restore_dream
  else
    warn "没装 Aerial，屏保保持原样"
  fi

  [ "$DRY" -eq 1 ] && return 0
  info "清理"
  sh_ "rm -f /storage/self/primary/*.png /data/local/tmp/*.png"
  sh_ "pm trim-caches 999999999999" >/dev/null 2>&1
  sh_ "am force-stop com.android.provision" >/dev/null 2>&1
  # disable-user 不杀已有进程
  for p in $(sh_ "pm list packages -d" | sed 's/package://' | tr -d '\r'); do
    sh_ "am force-stop $p" >/dev/null 2>&1
  done
  echo
  echo "  可用内存：$(sh_ "grep MemAvailable /proc/meminfo")"
}

# ---------------- 体检 ----------------
check() {
  echo "======== 盒子体检 ========"
  echo "地址   : $BOX"
  echo "型号   : $(sh_ getprop ro.product.model) / $(sh_ getprop ro.product.device)"
  echo "Android: $(sh_ getprop ro.build.version.release)（SDK $(sh_ getprop ro.build.version.sdk)）  ABI: $(sh_ getprop ro.product.cpu.abi)"
  echo "运行   : $(sh_ uptime | sed 's/^ *//')"
  echo
  echo "-- 桌面 --"
  echo "HOME   : $(home_now)"
  echo "Aerial : $(sh_ "dumpsys package $AERIAL_PKG 2>/dev/null | grep -m1 versionName=" | tr -s ' ')"
  echo "官方桌面: $(pkg_disabled "$OFFICIAL_LAUNCHER" && echo 已停用 || echo 仍启用)"
  echo
  echo "-- 屏保 --"
  echo "组件: $(sh_ settings get secure screensaver_components)"
  echo "启用: $(sh_ settings get secure screensaver_enabled)"
  echo
  echo "-- 已停用（$(sh_ "pm list packages -d" | wc -l) 个）--"
  sh_ "pm list packages -d" | sed 's/package:/  /' | sort
  echo
  echo "-- 已卸载（对 user 0 不存在，云端恢复不了）--"
  sh_ "pm list packages" > /tmp/pkgbox.txt 2>/dev/null
  local p
  for p in $(list_of config/uninstall-list.txt); do
    grep -qx "package:$p" /tmp/pkgbox.txt && echo "  $p  ← 还在" || echo "  $p  ✓ 已卸载"
  done
  echo
  echo "-- 常驻应用进程 --"
  sh_ "ps -A -o USER,NAME" | awk '$2 ~ /\./ && $2 !~ /^\[/ && $1 ~ /^u0_/' | sort -u | \
    while read -r u n; do
      pss="$(sh_ "dumpsys meminfo $n 2>/dev/null | grep -m1 -oE 'TOTAL +[0-9]+'" | grep -oE '[0-9]+')"
      printf "  %-46s Pss=%sKB\n" "$n" "${pss:-?}"
    done | sort -t= -k2 -rn | head -15
  echo
  echo "-- 内存 --"
  sh_ "grep -E 'MemTotal|MemAvailable' /proc/meminfo" | sed 's/^/  /'
  echo
  echo "-- 三方应用 --"
  sh_ "pm list packages -3" | sed 's/package:/  /' | sort
}

# ---------------- 看门狗 ----------------
watch_loop() {
  local list want have ss miss p interval="${INTERVAL:-30}"
  want="$(grep '^package:' config/disable-list.txt | sed 's/^package://; s/#.*//' | tr -d '\r' | xargs -n1 \
          | grep -v "^$OFFICIAL_LAUNCHER$")"
  mkdir -p backup
  info "看门狗：$BOX，每 ${interval}s 查一次（Ctrl+C 退出），日志 backup/watch.log"
  while :; do
    if ! "$ADB" connect "$BOX" >/dev/null 2>&1 || ! "$ADB" -s "$BOX" shell "echo ok" >/dev/null 2>&1; then
      echo "  $(date '+%F %T') 连不上（关机/休眠）— 下次再试"
      [ "${ONCE:-0}" -eq 1 ] && exit 0
      sleep "$interval"; continue
    fi
    have="$("$ADB" -s "$BOX" shell "pm list packages -d" 2>/dev/null | tr -d '\r')"
    ss="$("$ADB" -s "$BOX" shell "settings get secure screensaver_components" 2>/dev/null | tr -d '\r')"
    miss=""
    for p in $want; do echo "$have" | grep -qx "package:$p" || miss="$miss $p"; done
    if [ -z "$miss" ] && [ "$ss" = "$AERIAL_DREAM" ]; then
      echo "  $(date '+%F %T') 正常：$(echo "$have" | grep -c .) 个包已停用，屏保 AerialDream"
      [ "${ONCE:-0}" -eq 1 ] && exit 0
      sleep "$interval"; continue
    fi
    echo "$(date '+%F %T') 被恢复：${miss:-无}；屏保：${ss:-空}" | tee -a backup/watch.log
    if [ "${DRY:-0}" -eq 0 ]; then
      optimize >/dev/null 2>&1
      echo "$(date '+%F %T') 已补回" | tee -a backup/watch.log
    fi
    [ "${ONCE:-0}" -eq 1 ] && exit 0
    sleep "$interval"
  done
}

# ---------------- 主流程 ----------------
BUILD=0; DRY=0; MODE=deploy
while [ $# -gt 0 ]; do
  case "$1" in
    --check)    MODE=check; shift;;
    --optimize) MODE=optimize; shift;;
    --watch)    MODE=watch; shift;;
    --once)     ONCE=1; shift;;
    --dry-run)  DRY=1; shift;;
    --build)    BUILD=1; shift;;
    --interval) INTERVAL="$2"; shift 2;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0;;
    *) die "不认识的参数：$1（--help 看用法）";;
  esac
done

case "$MODE" in
  check)    conn; check ;;
  optimize) conn; info "重跑优化"; optimize; ok "完成" ;;
  watch)    ONCE="${ONCE:-0}" DRY="${DRY:-0}" watch_loop ;;
  deploy)
    conn
    echo "════ 创维小湃 P3 · 一键部署 ════"
    info "① 安装 Aerial 桌面"; deploy_aerial
    info "② 补齐权限";         grant_perms
    info "③ 卸载顽固包";       uninstall_stubborn
    info "④ 系统优化";         optimize
    echo
    ok "部署完成。建议拔电源重启一次验证；重启后跑 bash deploy.sh --optimize 补回屏保"
    warn "固件会周期性把语音助手/媒体中心恢复并抢回屏保，想让状态常驻就跑 bash deploy.sh --watch"
    ;;
esac

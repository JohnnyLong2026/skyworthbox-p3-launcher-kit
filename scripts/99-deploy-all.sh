#!/bin/bash
# ============================================================
# 99 一键全流程：从一台原厂盒子到「Aerial 桌面 + 开机定时启动」
#
#   ./99-deploy-all.sh                         用现成 APK 全流程部署（推荐）
#   ./99-deploy-all.sh --build                 从源码编译后再部署
#   ./99-deploy-all.sh <包名> <名称> <秒数>    顺便设好定时启动目标
#     例：./99-deploy-all.sh com.huawei.himovceie 影视仓 5
#
# 步骤：体检 → 装 Aerial 设 HOME → 补权限 → 装定时启动 → 设跳转目标 → 系统优化 → 重启验证
# 全程免 root，所有改动可 ./40-restore.sh 还原。
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
S="$(cd "$(dirname "$0")" && pwd)"

BUILD=0
if [ "$1" = "--build" ]; then BUILD=1; shift; fi

TARGET_PKG="$1"; TARGET_LABEL="$2"; TARGET_DELAY="${3:-5}"

echo "════════ 创维小湃 P3 桌面定制 · 一键部署 ════════"
echo

# 0 体检
info "① 体检"
"$S/00-doctor.sh" | sed -n '/---- 设备 ----/,/^$/p'

# 1 Aerial 桌面
info "② 安装 Aerial 桌面并设为默认"
if [ "$BUILD" -eq 1 ]; then "$S/21-build-aerial.sh" || die "Aerial 部署失败"
else "$S/21-build-aerial.sh" --apk || die "Aerial 部署失败"; fi

# 2 权限（装完 Aerial 必做，漏了桌面只能当空壳用）
info "③ 补齐 Aerial 权限"
"$S/11-grant-permissions.sh" || die "权限补齐失败"

# 3 定时启动
info "④ 安装定时启动"
if [ "$BUILD" -eq 1 ]; then "$S/20-build-autostart.sh" || die "定时启动部署失败"
else "$S/20-build-autostart.sh" --apk || die "定时启动部署失败"; fi

# 4 跳转目标
if [ -n "$TARGET_PKG" ]; then
  info "⑤ 设置跳转目标"
  "$S/30-set-autostart.sh" "$TARGET_PKG" "$TARGET_LABEL" "$TARGET_DELAY"
else
  warn "⑤ 未指定跳转目标，跳过。稍后自己跑：./30-set-autostart.sh <包名> <名称> <秒数>"
fi

# 5 系统优化（不动官方桌面：它已被 21 脚本单独停用）
info "⑥ 系统优化"
"$S/10-optimize.sh"

# 5 重启
echo
echo "════════════════════════════════════════"
read -r -p "是否现在重启盒子做最终验证？(y/N) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  info "重启中… 约 40 秒后盒子会：自动进 Aerial → $TARGET_DELAY 秒后弹提醒 → 倒计时 9 秒 → 跳转${TARGET_LABEL:-目标应用}"
  sh "reboot" >/dev/null 2>&1
  echo "重启后想看效果：./00-doctor.sh 或 adb shell dumpsys activity activities | grep mResumedActivity"
else
  ok "部署完成（未重启）。下次开机生效"
fi

#!/bin/bash
# ============================================================
# 15 卸载：把固件云端列表反复恢复的那几个包，改成"对 user 0 不存在"
#
#   ./15-uninstall.sh              按 config/uninstall-list.txt 卸载（先备份 APK）
#   ./15-uninstall.sh --dry-run    只报告会卸哪些，不动盒子
#
# 为什么不用停用：固件里的 skycommonpropertymanager 每次开机约 60 秒后拉一份
# 厂商「系统控制列表」，逐个 setApplicationEnabledSetting(ENABLED) 把我们停用的包
# 恢复回来（调用栈见 config/stubborn-list.txt）。包不存在时这一步抛 Unknown package，
# 恢复动作就失效了。实测：卸掉的 4 个重启后依然不存在，留着的 2 个会被恢复。
#
# 卸载只针对 user 0，APK 不会真删：
#   - 脚本先把 APK 复制到盒子的 /sdcard/p3-backup/
#   - 系统自带的那份仍留在 /system
# 还原：./40-restore.sh --apps（内部用 pm install-existing）
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
conn

DRY=0
[ "$1" = "--dry-run" ] && DRY=1

sh "mkdir -p $BOX_BACKUP_DIR" >/dev/null 2>&1
ok "APK 备份目录：$BOX_BACKUP_DIR（PC 侧另有 backup/system-apk/）"

n_done=0
n_skip=0
for p in $(uninstall_packages); do
  if ! pkg_present "$p"; then
    echo "  已不存在：$p"
    n_skip=$((n_skip+1))
    continue
  fi

  src="$(sh "pm path $p" | sed 's/package://' | head -1)"
  ver="$(sh "dumpsys package $p 2>/dev/null | grep -m1 versionName" | tr -d ' ' | cut -d= -f2)"
  dst="$BOX_BACKUP_DIR/$p.apk"

  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] 将备份并卸载：$p（$ver，$src）"
    n_done=$((n_done+1))
    continue
  fi

  # 有了就别重复拷，避免每次覆盖出问题时连备份也没了
  if [ -n "$src" ] && ! sh "[ -s $dst ] && echo has" | grep -q has; then
    sh "cp $src $dst" >/dev/null 2>&1 && echo "  已备份 APK：$(basename "$dst")（$ver）"
  fi

  out="$(sh "pm uninstall -k --user 0 $p")"
  case "$out" in
    *Success*) echo "  已卸载：$p（$ver）"; n_done=$((n_done+1)) ;;
    *)         warn "$p 卸载失败：$out" ;;
  esac
done

echo
if [ "$DRY" -eq 1 ]; then
  ok "dry-run 结束：可卸 $n_done 个，已不存在 $n_skip 个"
else
  ok "卸载完成：本次卸了 $n_done 个，之前已不存在 $n_skip 个"
  echo "  还原：./40-restore.sh --apps"
  echo "  单个还原：adb shell pm install-existing <包名>"
  echo "  备份说明：$BOX_BACKUP_DIR/README.txt（PC：backup/system-apk/README.txt）"
fi

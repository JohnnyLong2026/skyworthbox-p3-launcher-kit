#!/bin/bash
# ============================================================
# 11 给 Aerial 桌面补齐权限（装完 Aerial 之后跑一次）
#
#   ./11-grant-permissions.sh
#
# 为什么要单独一步：这些权限装完不会自动给，缺了它们 Aerial 只能当个空壳——
# 屏保切不了、HOME 被厂商抢回去时救不回来、天气定不了位。
# 出厂重置或重装 Aerial 之后必须重跑（授权跟包走，包卸了就没了）。
#
# 两类权限分开处理：
#   - 运行时权限用 pm grant（WRITE_SECURE_SETTINGS 等 development 级权限 adb 能给）
#   - WRITE_SETTINGS / REQUEST_INSTALL_PACKAGES 不是"可变更"权限，pm grant 会抛
#     SecurityException，得走 appops
#   - 通知监听和「守护」无障碍服务只能在 settings 里登记，且要保留厂商原有的条目
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

conn

[ "$(sh "pm list packages $AERIAL_PKG" | tr -d '\r')" = "package:$AERIAL_PKG" ] \
  || die "没装 $AERIAL_PKG，先跑 ./21-build-aerial.sh"

info "授予运行时权限"
# pm grant 对已授予的权限是幂等的，重复跑不会报错
for perm in \
  android.permission.WRITE_SECURE_SETTINGS \
  android.permission.SYSTEM_ALERT_WINDOW \
  android.permission.PACKAGE_USAGE_STATS \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION
do
  out="$(sh "pm grant $AERIAL_PKG $perm" | grep -v '^$' || true)"
  if [ -z "$out" ]; then
    echo "  ok      $perm"
  else
    # 不是可变更权限（WRITE_SETTINGS 等）会抛异常，交给下面的 appops 处理
    echo "  跳过    $perm（pm grant 不给，走 appops）"
  fi
done

info "appops 补齐（pm grant 不管的两项）"
for op in WRITE_SETTINGS REQUEST_INSTALL_PACKAGES SYSTEM_ALERT_WINDOW; do
  sh "appops set $AERIAL_PKG $op allow" >/dev/null 2>&1
  echo "  allow   $op"
done

info "登记通知监听（guard.RevivalListener）"
sh "settings put secure enabled_notification_listeners $AERIAL_PKG/app.orchard.tv.guard.RevivalListener" >/dev/null 2>&1
echo "  当前：$(sh "settings get secure enabled_notification_listeners")"

info "登记守护无障碍服务（guard.HomeGuardService）"
# 必须把厂商原有的服务拼在后面：直接覆盖会把创维语音助手的无障碍关掉
CUR="$(sh "settings get secure enabled_accessibility_services" | tr -d '\r')"
GUARD="$AERIAL_PKG/app.orchard.tv.guard.HomeGuardService"
case ":$CUR:" in
  *":$GUARD:"*) echo "  已在列表里，不动" ;;
  *)
    if [ -z "$CUR" ] || [ "$CUR" = "null" ]; then
      NEW="$GUARD"
    else
      NEW="$CUR:$GUARD"
    fi
    sh "settings put secure enabled_accessibility_services $NEW" >/dev/null 2>&1
    sh "settings put secure accessibility_enabled 1" >/dev/null 2>&1
    echo "  当前：$(sh "settings get secure enabled_accessibility_services")"
    ;;
esac

info "装回屏保（授权过程会动 secure 表）"
restore_dream

ok "权限已补齐。建议重启一次盒子让 guard 服务真正起来"

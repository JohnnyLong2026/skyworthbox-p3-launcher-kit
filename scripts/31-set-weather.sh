#!/bin/bash
# ============================================================
# 31 设置 Aerial 桌面的天气城市
#
# Aerial 存的是经纬度不是地名，且写在自己的私有目录里（没 root 写不了），
# 官方给的路子是「手机扫码打开的控制页面」HTTP 接口。所以流程是：
#   1. 桌面按 MENU 打开控制中心 → 个性化 → 右下角二维码
#   2. 截图解码二维码拿到带 token 的 URL
#   3. POST /api/weather/city 提交城市名
#
#   ./31-set-weather.sh 北京市           交互式：自己完成 1~3（需要 python + opencv）
#   （城市名写你要的那个，必须能在上游 assets/cities-cn.tsv 里搜到）
#   ./31-set-weather.sh --url <URL> 北京市   直接提交（URL 形如 http://192.168.1.100:8790/abcd1234/）
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

if [ "$1" = "--url" ]; then
  URL="$2"; CITY="${3:-北京市}"
  [ -n "$URL" ] || die "用法：$0 --url http://<盒子IP>:8790/<token>/ 北京市"
else
  CITY="${1:-北京市}"
  URL=""
fi

if [ -z "$URL" ]; then
  conn
  command -v python >/dev/null 2>&1 || die "自动模式需要 python（含 opencv-python）来解码二维码，或改用 --url 手动模式"

  info "打开 Aerial 控制中心（先移焦点到状态栏，否则 MENU 会弹图块菜单）"
  sh "input keyevent KEYCODE_DPAD_UP" >/dev/null 2>&1
  sh "input keyevent KEYCODE_DPAD_UP" >/dev/null 2>&1
  sh "input keyevent KEYCODE_MENU" >/dev/null 2>&1
  sleep 1
  echo
  echo "────────────────────────────────────────────"
  echo " 请用遥控器：控制中心 → 个性化 → 让右下角二维码显示出来"
  echo " 二维码出现后，回到电脑按回车继续（脚本会自动截图解码）"
  echo "────────────────────────────────────────────"
  read -r _

  SHOT="$REPO_ROOT/backup/weather-qr-$(date '+%H%M%S').png"
  mkdir -p "$REPO_ROOT/backup"
  sh "screencap -p /data/local/tmp/w.png"
  adb_pull "/data/local/tmp/w.png" "$SHOT"
  info "截图 → $SHOT"

  URL="$(python "$REPO_ROOT/tools/weather_token.py" "$SHOT" 2>/dev/null | tail -1)"
  [ -n "$URL" ] || die "没解出二维码。手动模式：浏览器打开盒子 IP:8790 看地址，或用 $0 --url <URL> $CITY"
  info "控制页地址：$URL"
fi

# URL 末尾补斜杠
case "$URL" in */) ;; *) URL="$URL/" ;; esac

info "提交城市：$CITY"
curl -s -X POST "${URL}api/weather/city" --data-urlencode "name=$CITY" --max-time 10
echo
ok "天气城市已提交（桌面上看右上角，可能要等一次刷新）"

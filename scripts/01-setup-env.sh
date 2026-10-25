#!/bin/bash
# ============================================================
# 01 环境自检：编译与部署需要的东西是否齐全
# 只是检查并给出安装指引，不自动装
# ============================================================
echo "════════ 环境自检 ════════"
echo

# adb
if command -v adb >/dev/null 2>&1; then
  echo "✓ adb        $(command -v adb)  ($(adb version 2>/dev/null | head -1))"
else
  echo "✗ adb        未找到 → winget install Google.PlatformTools"
fi

# java
if command -v java >/dev/null 2>&1; then
  v="$(java -version 2>&1 | head -1)"
  echo "✓ java       $v"
  echo "$v" | grep -q '"17' || echo "  ! 建议 JDK 17（Aerial 需要）"
else
  echo "✗ java       未找到 → winget install EclipseAdoptium.Temurin.17.JDK"
fi

# Android SDK
if [ -n "$ANDROID_HOME" ]; then
  echo "✓ ANDROID_HOME = $ANDROID_HOME"
  ls "$ANDROID_HOME/platforms" 2>/dev/null | tr '\n' ' ' | sed 's/^/  platforms: /'; echo
  ls "$ANDROID_HOME/build-tools" 2>/dev/null | tr '\n' ' ' | sed 's/^/  build-tools: /'; echo
else
  echo "✗ ANDROID_HOME 未设置 → 装 cmdline-tools 后 sdkmanager 装 platforms;android-34 和 build-tools;34.0.0"
  echo "  （Aerial 需要 platforms;android-36 + build-tools;35.0.0）"
fi

# python（logo 脚本 / 二维码解码用）
if command -v python >/dev/null 2>&1; then
  echo "✓ python     $(python --version 2>&1)"
  python -c "import PIL" 2>/dev/null && echo "  ✓ Pillow" || echo "  - Pillow 未装（make_logo_white.py 需要：pip install pillow）"
  python -c "import cv2" 2>/dev/null && echo "  ✓ opencv（天气二维码解码可用）" || echo "  - opencv 未装（31-set-weather.sh 自动模式需要：pip install opencv-python）"
else
  echo "- python     未找到（只影响 logo 脚本和天气自动模式）"
fi

# 盒子连通性
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
echo
if "$ADB" connect "$BOX" >/dev/null 2>&1 && "$ADB" -s "$BOX" shell "echo ok" >/dev/null 2>&1; then
  echo "✓ 盒子        $BOX 已连通（$(box_model) / Android $(box_android)）"
else
  echo "✗ 盒子        $BOX 连不上。确认：盒子开机（休眠需遥控器唤醒）、ADB 网络调试已开、IP 填在 scripts/box.conf"
fi
echo
echo "仓库内所有脚本都可直接 ./运行；顺序见 README「快速开始」。"

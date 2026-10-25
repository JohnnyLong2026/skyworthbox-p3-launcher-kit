#!/usr/bin/env python3
"""从 Aerial 控制中心「个性化」页的截图里解出带 token 的控制页 URL。

用法：python weather_token.py <截图.png>
输出：http://<盒子IP>:8790/<token>/  （解不出来则无输出）

注意：截图是 1920x1080；如果先裁切过，坐标要按缩放比例换算，
所以对整图直接 detectAndDecode 最稳。
依赖：pip install opencv-python
"""
import sys

import cv2


def main(path: str) -> int:
    img = cv2.imread(path)
    if img is None:
        print(f"读不了图片: {path}", file=sys.stderr)
        return 1

    data, _, _ = cv2.QRCodeDetector().detectAndDecode(img)
    if not data:
        # 有些截图是横向拉伸缩放过的，放大一倍再试一次
        big = cv2.resize(img, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
        data, _, _ = cv2.QRCodeDetector().detectAndDecode(big)
    if not data:
        print("没找到二维码", file=sys.stderr)
        return 2

    print(data.strip())
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))

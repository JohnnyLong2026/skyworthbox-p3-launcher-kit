"""截图脱敏：用 OpenCV inpaint 把指定矩形重建成背景。

为什么用 inpaint 而不是打码/涂抹：桌面壁纸是平滑渐变，Navier-Stokes
修复会沿着等照度线把周围的渐变推过来，填完既没有边界线，也没有色块，
看起来就是原本的背景——适合把截图放到公开仓库时隐去城市名这类小字。

实测参数：radius 10~12、INPAINT_NS 效果最自然（Telea 在大块平滑区
反而会留下淡淡的矩形边）。矩形四边都多留 2px，把抗锯齿的毛边一起吃掉。

用法：
  python redact_screenshot.py 图.png x1 y1 x2 y2 [更多矩形...]
  python redact_screenshot.py 图.png --out 新图.jpg x1 y1 x2 y2

依赖：opencv-python、numpy
"""
import sys
import cv2
import numpy as np


def redact(img, boxes, radius=12, flag=cv2.INPAINT_NS):
    """boxes 为 [(x1, y1, x2, y2), ...]；返回修复后的 BGR 图。"""
    mask = np.zeros(img.shape[:2], np.uint8)
    for x1, y1, x2, y2 in boxes:
        mask[y1:y2, x1:x2] = 255
    return cv2.inpaint(img, mask, radius, flag)


def main():
    args = sys.argv[1:]
    if len(args) < 5:
        raise SystemExit(__doc__)
    path = args[0]
    out = None
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        del args[i:i + 2]
        args.pop(0)
    else:
        args.pop(0)

    nums = [int(v) for v in args]
    if len(nums) % 4:
        raise SystemExit('坐标个数必须是 4 的倍数（每个矩形 4 个数）')
    boxes = [tuple(nums[i:i + 4]) for i in range(0, len(nums), 4)]

    # cv2.imread 在 Windows 下读不了中文路径，走 numpy 中转
    img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise SystemExit(f'读不到图：{path}')

    fixed = redact(img, boxes)
    dst = out or path
    ok, buf = cv2.imencode('.jpg' if dst.lower().endswith('.jpg') else '.png',
                           fixed, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not ok:
        raise SystemExit('编码失败')
    buf.tofile(dst)
    print(f'{dst}  <- {path}  boxes={boxes}')


if __name__ == '__main__':
    main()

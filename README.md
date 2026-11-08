# 创维小湃 P3 盒子改造（Aerial TV 桌面 + 系统瘦身）

把一台封闭的安卓电视盒子（**创维小湃 P3 / Q5001 / cupid_p2**，全志 H616，Android 10，2GB 内存）
改造成**通电即进 [Aerial TV](https://github.com/pengchujin/aerial-tv) 桌面、几秒后自动打开直播软件**的样子。
同时停用 22 个常驻预装应用、卸载 4 个删不掉的——全程**免 root**，只用 `adb shell`，所有改动可一键还原。

> 完整原理、故障排查、已知限制见 **[docs/手册.md](docs/手册.md)**。

---

## 两条命令

```bash
export BOX_TARGET=192.168.1.x:5555    # 你的盒子 IP（设置里先开 ADB 网络调试）
bash deploy.sh                         # 装桌面 → 设 HOME → 补权限 → 卸载顽固包 → 系统优化
bash deploy.sh --optimize              # 重启后跑一次，把屏保补回来
```

重复跑是幂等的，已部署的机器再跑只会补缺。

| 命令 | 用途 | 耗时 |
|---|---|---|
| `bash deploy.sh` | 全流程部署 | 约 1 分钟 |
| `bash deploy.sh --check` | 只体检：HOME / 屏保 / 停用包 / 常驻进程 / 内存 | 约 10 秒 |
| `bash deploy.sh --optimize` | 重启后补回屏保与停用包 | 约 10 秒 |
| `bash deploy.sh --watch` | 看门狗，被固件恢复的包和屏保自动补回 | 常驻 |
| `bash deploy.sh --build` | 从源码编译 Aerial（需 JDK 17 + Android SDK） | 约 9 分钟 |
| `bash restore.sh` | 完全还原到接近出厂 | — |

`--dry-run` 只报告不动盒子，`--interval 60` 改看门狗轮询间隔。

**开机自动打开哪个应用**在 Aerial 里设置（设置 → 开机打开的应用）。补丁已把这次跳转延迟 5 秒——
不加延迟的话桌面一冒头就跳走，看着像根本没进桌面。

---

## 为什么这台机器需要专门适配

四条固件行为决定了整套方案（详见手册第一节）：

1. **HOME 前缀白名单** —— 只有 `com.ktcp.launcher*` 等前缀的包能当默认桌面，所以 Aerial 的
   `applicationId` 改成 `com.ktcp.launcher.aerial`（Java 命名空间仍是 `app.orchard.tv`）。
2. **拦截第三方开机广播** —— 自启只能由桌面自己发起。
3. **每次开机把屏保写回广告组件** —— 所以 `--optimize` 不是一次性动作，而是每次开机后的例行补丁。
4. **云端「系统控制列表」周期性恢复停用的包** —— 最顽固的 4 个改为 `pm uninstall -k --user 0`，
   让云端那一步抛 `Unknown package`，从此恢复不了。

另一个硬约束：用户空间是**纯 32 位**（`armeabi-v7a` / `zygote32`），只带 `arm64-v8a` 的 APK
必然 `INSTALL_FAILED_NO_MATCHING_ABIS`，与签名和安装方式无关。

---

## 目录

```
deploy.sh                  一键部署 / 体检 / 优化 / 看门狗
restore.sh                 一键还原
docs/手册.md                完整手册：原理、维护、排查、限制
config/
  disable-list.txt         22 个停用包
  uninstall-list.txt       4 个卸载包（云端恢复不了的唯一解法）
  stubborn-list.txt        顽固包与云端恢复的调用栈记录
  backup-screensaver.txt   屏保原值（还原用）
apk/aerial-tv-1.88-p3.apk  编译好的桌面，不想编译直接装
patches/aerial-tv-p3.patch 相对上游 v1.88 的全部改动（4 处）
```

上游源码不复制进本仓库，补丁按 tag 定位；跟着上游升级时重新落位并更新版本号即可。

## 已知限制

- 装不了 64 位应用（硬件层面的 32 位用户空间，软件绕不过）。
- 每次开机屏保、语音助手、媒体中心会被固件改回，跑一次 `--optimize` 或挂看门狗。
- 停用官方桌面后没有回退桌面，Aerial 崩溃时需 ADB 救（`bash restore.sh --home`）。
- 不要用 Aerial 控制中心的「检查更新」，它会装成第二个应用抢 HOME。

## 致谢与许可

Aerial TV 由 [pengchujin](https://github.com/pengchujin/aerial-tv) 开发（Apache-2.0）；
停用清单的思路起于 [CleanYourTV](https://github.com/Gathin23/cleanyourtv)。
本仓库只提供设备适配补丁与部署脚本，同样以 Apache-2.0 发布，见 [LICENSE](LICENSE)。

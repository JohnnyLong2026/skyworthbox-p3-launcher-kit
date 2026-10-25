# 更新记录

## v1.3（2026-10-26）精简：只留当前版本，线上线下同步

仓库里攒了几版迭代的产物和探索期的脚本，对拿到这个项目的人是噪音。清掉，只留当前这一套。

**删掉的**

| 文件 | 为什么删 |
|---|---|
| `apk/aerial-tv-1.47-p3.apk` | 已被 1.49 取代 |
| `apk/tvautostart-v4.0.apk` | 已被 v4.2 取代 |
| `tools/logo_d.py`、`logo_proposal.py`、`make_banner.py` | 做图标时的概念稿和比稿，最终采用的方案是 `make_logo_white.py` |
| `tools/github_backup.py` | 当初 git 协议不通时走 REST API 的权宜之计；SSH 已通，不需要了 |

仓库从 6.8MB 降到 3.9MB，`apk/` 只剩 Aerial 1.49 + 定时启动 v4.2 两个成品。

**顺手修的（删了旧 APK 才暴露出来）**

- `scripts/20-build-autostart.sh` 里的产物路径还写死 `tvautostart-v4.0.apk`，
  和 `apk/` 里实际放的 v4.2 对不上。改成 `AUTOSTART_VER="v4.2"` 变量（对齐 `21-build-aerial.sh`
  的 `AERIAL_VER` 写法），并且编译成功后把产物复制回 `apk/`——以前它只用 gradle 的临时产物，
  所以仓库里那份 v4.2 是手工放的，容易和源码脱节。
- `scripts/50-backup-github.sh` 重写：默认走 SSH `git push`，不再要 Token。
  原来的注释和默认分支都建立在「git(443) 不通、只能调 API」的前提上，而 SSH 已经实测可用。
  公钥没登记时脚本会把公钥打出来并告诉你去哪儿加，不再默默失败。
- `docs/07-备份到GitHub.md` 跟着重写：网络情况表、三种方案 → 只留 SSH 一条路，
  故障表换成 SSH 相关的排查项。
- `README.md` 目录树、`docs/07` 清单里对已删文件的描述同步更新。

**线上**

GitHub 上的历史里还留着旧 APK（3MB），所以重建了一次提交历史并强制推送，
现在 clone 下来就是干净的 3.9MB。

## v1.2（2026-10-25）公开发布准备：脱敏 + 补全项目背景

准备把仓库公开分享，做了三件事。

**一、敏感信息脱敏**

| 项 | 处理 |
|---|---|
| 设备序列号 | 从 `docs/06`、`docs/html/硬件信息报告.html` 移除，只保留字段名与读取命令 |
| MAC 地址（eth0/wlan0/p2p0） | 换成 `00:11:22:33:44:xx` 示意值 |
| 局域网 IP | 统一换成 `192.168.1.100` 示例；`scripts/box.conf` 改为示例值并在 `lib.sh` 里检测未改时提示 |
| 常用城市（天气） | 文档/脚本示例统一改成「北京市」；截图里的城市名用 inpaint 抹除 |
| 其他 | 本机路径、账号、token 一律不出现；`patches/` 与源码里无环境相关残留 |

截图脱敏新增 `tools/redact_screenshot.py`：用 OpenCV `inpaint`（Navier-Stokes）重建背景，
在渐变壁纸上既不留边界线也不留色块。试过水平/垂直插值和平移复制，都会在渐变上留下
可见的矩形边——只有 inpaint 是干净的。

**二、README 重写**

- 新增「缘起」：为什么做这个（老人只想开机看到直播 → CleanYourTV 指路 → Aerial）
- 新增「这台盒子」参数表（2GB / 32 位 / 无 root / 百兆网口）
- 新增「改造路线」七阶段总览表，每步标出成败要点
- 新增「关于隐私」一节，公开列出脱敏规则
- 顶部与「最终效果」换成 4 张脱敏截图（桌面 / 浮层 / 设置 / 设计图）

**三、新增 `docs/00-改造全过程.md`**

完整历程：目标怎么定义、怎么判断机器有无改造空间、两道墙（HOME 白名单 / 自启封锁）
分别是试了多少种方法才绕过去的、系统瘦身的原则、体感优化的细节（9 秒时序、图标矢量的
退化弧坑、圆角图块读 banner 不是 icon）、时间线、以及"如果重来一次会先做什么"。

**顺手修的**

- 文件名与内容不符的截图 `autostart-v4-settings.jpg`（实际是桌面，且与 `aerial-desktop.jpg` 重复）已删除
- `scripts/31-set-weather.sh` 的默认城市从具体城市改为「北京市」，注释说明必须是
  `cities-cn.tsv` 里有的名字

## v1.1（2026-10-25）GitHub 备份工具

新增 `scripts/50-backup-github.sh` + `tools/github_backup.py` + `docs/07-备份到GitHub.md`。

本机到 github.com 的 **git(443) 不通**（沙箱代理 502、去掉代理后直连超时），
SSH 22 通但要先登记公钥，只有 **api.github.com 可达**。
所以默认备份路径不用 `git push`，而是走 REST API 的 `blob → tree → commit → ref`：
一个 Token 一条命令完成，仓库不存在会自动创建，重复执行会顺着上一次提交追加（可增量）。

三种方式：`GITHUB_TOKEN=... ./50-backup-github.sh`（推荐）/ `--ssh` / `--zip`。
上传内容 80 个文件 6.3MB，`build/`、`.gradle/`、`local.properties` 已被忽略。

## Aerial 桌面 1.47 → 1.49（2026-10-25）

上游 17 个提交（1.48 + 1.49）。对这台盒子实际有用的：

- **启动更快，控制中心更省资源**，慢机型自动降级特效（1.48 的性能改动）
- 控制中心面板缩小、时钟字距修正、若干动画细节修复
- 更多机型修正画面留边（TCL x32a0 / 小米 HDMI 顺序 / 创维 75A7D / VIDAA launcher）
- **系统屏保没弹出时用 Aerial 自带屏保兜底**（1.49 新增，正好补上固件写回广告屏保的坑）

P3 的三处定制和 1.47 完全一致，补丁 96 行原样复用（`applicationId` 改写 /
`AutostartBridge.kt` / `MainActivity` fresh 分支挂钩子），换版本不用改补丁。

**升级实测（真重启 + adb 重放）**：

```
18:05:40.4  开机进 Aerial 桌面
18:05:44.6  armed from home  grace=1000 delay=5 waitMs=6000
18:05:50.6  提醒浮层弹出
18:08:52.2  （重放）倒计时 9 秒 → 跳转影视仓 LivePlayActivity
```

天气仍是「北京 18°」，图块、设置、自定义壁纸全部保留（包名没变，数据目录不迁移）。

**新发现：固件每次开机都会把 `screensaver_components` 写回广告组件。**
之前以为换屏保是一次性操作，实际重装 Aerial 和每次重启都会失效。已在 `lib.sh` 加
`restore_dream()`，`10-optimize.sh` 和 `21-build-aerial.sh` 都会调用；备份逻辑改成只记出厂值，
不会把广告值当"原值"反复覆盖。文档 `02` 已加说明。

## 定时启动 v4.2（2026-10-25）修复：进桌面到弹窗要等 20 多秒

**症状**：进桌面后要等二十几秒才弹提醒（设置的是 5 秒 + 2 秒缓冲，应该 7 秒）。

**实测时间线（修复前）**：
```
13:35:30.2  Aerial 桌面显示完成
13:35:32.4  ReminderService 被 arm
13:35:56.2  浮层才出现          ← 等了 23.8 秒
```

**两个原因叠加**：

1. **服务被 arm 了两次，后一次覆盖前一次**
   ```
   13:38:21.7  armed from home     action=ACTION_ARM  waitMs=6000
   13:38:25.4  armed from unknown  action=null        waitMs=8000   ← 重设了
   ```
   第二枪来自 `BootReceiver`：它构造 `new Intent(context, ReminderService.class)` **没带 action**，
   服务认不出是谁，于是按"未知来源"加缓冲。这种开机广播平时被固件拦，
   但包不是 stopped 态时**确实会放行**（本次两次重启都收到了）。

2. **兜底缓冲 15 秒 + 单次 `postDelayed` 漂移**
   `Prefs.BOOT_GRACE_MS` 原本是 15 秒（服务 BootReceiver 那条路径等桌面绘制），
   一旦 action 丢失就走 15+5=20 秒起步。而单发 `postDelayed` 在刚开机的繁忙主线程上
   又迟到了约 3 秒，最终成了 23.8 秒。

**修复**：
- `ReminderService` 加幂等：**一次开机只认第一次 arm**，后来的直接被忽略（保留最早死线）
- 计时改用**绝对死线 + 250ms 轮询自校正**（`SystemClock.elapsedRealtime`），迟到不再累积，
  且用 elapsedRealtime 而非 uptime，避免休眠导致的漂移
- `BootReceiver` 启动服务时补上 `ACTION_ARM` 与显式 `EXTRA_WAIT_MS`，不再被当成"未知来源"
- 桌面路径缓冲 2 秒 → **1 秒**（arm 发生在桌面绘制完成之后，不需要留 2 秒）
- 兜底缓冲 15 秒 → **3 秒**（这条路径本来就不该发生，没必要留这么长）

**修复后实测**：
```
13:40:43.0  桌面可见
13:40:45.9  armed from home waitMs=6000
13:40:49.3  BootReceiver 第二次 arm → already armed, ignored
13:40:51.9  浮层弹出（arm 后正好 6.000 秒）
13:41:01.0  跳转影视仓（9 秒倒计时）
```
进桌面到弹窗：**26 秒 → 9 秒**（其中 5 秒是用户设置的延迟）。

## 定时启动 v4.1（2026-10-25）修复：开机后点开设置会启动倒计时

**症状**：开机后手动点开「定时启动」设置界面，会立刻开始跳转倒计时。

**原因**：`MainActivity.onCreate()` 开头有一段 v3.0 时代遗留的"开机握手"判断
（`armFromHomeBoot()`：已配置 + 开机 4 分钟内 + 该次启动未 arm 过）。
它无法区分"桌面拉起"和"用户手动打开"，所以开机窗口内第一次手动点击也会被当成桌面握手，
直接 `startForegroundService(ReminderService)`。

**修复**：删掉这段残留逻辑。开机触发已完全由 Aerial 的 `AutostartBridge` 负责
（它直接向 `ReminderService` 发 `ACTION_ARM`），设置界面不再参与 arm。

**顺带增强**：用户主动打开设置界面时，若桌面已 arm 了一次还没弹出的倒计时，会取消它
（`stopService` → `ReminderService.onDestroy` 清掉 pending callback）。
注意这个取消必须写在 **`onResume()`** 里：Activity 是 singleTask，
界面还在栈里时再打开走的是 `onNewIntent()`，根本不会进 `onCreate()`。

**验证**（重启实测 + 三种场景）：
- 重启后自动链路照常：Aerial → 提醒浮层 → 跳转影视仓 ✓
- 开机 77 秒（在原来的 4 分钟窗口内）手动打开设置 → 18 秒后仍在设置界面，无跳转 ✓
- arm 后打开设置（Activity 未运行 / 已在运行两种路径）→ 跳转均被取消 ✓
- arm 后不干预 → 10 秒后浮层照常弹出 ✓

## v1.0（2026-10-25）首次归档

把散落在工作区里的改造过程整理成可复现的仓库。

### 盒子端最终状态

- 默认桌面：Aerial 1.47 定制版（`com.ktcp.launcher.aerial`），官方桌面已停用（后续已升级到 1.49，见上方）
- 定时启动：v4.2（`com.ktcp.launcher.autostart`），目标 = 影视仓，进桌面 5 秒后提醒，浮层倒计时 9 秒
- 系统：停用 18 个常驻应用、动画 0.5x、关悬浮通知/辅助 GPS/WiFi 唤醒
- 屏保：广告屏保 → Aerial 航拍屏保
- 天气：固定北京市
- 清理：删除调试残留 74 张截图（42MB）+ 各应用缓存

### 本次归档做的整理

- 散落的 adb 命令 → `scripts/` 下 9 个编号脚本，按流程顺序可直接跑
- Aerial 上游 96MB 源码 → 只保留 `patches/aerial-tv-p3.patch`（3 处改动）
- 文档：README + 6 篇分步文档
- 产物：3 个 APK（Aerial 1.47 / 定时启动 v4.2 / v4.0 回滚版）

### 版本历史（改造过程）

| 版本 | 说明 |
|---|---|
| 定时启动 v1.0 | 把自己当桌面，进桌面后倒计时跳转 |
| v2 / v3.0 | 改为浮层提醒；借 CleanYourTV 的 `boot_to_live_tv` 做开机钩子 |
| v3.1 | 桌面换成 Aerial，钩子改为 AutostartBridge |
| v3.2 | 换新 logo（方案 D：浅玻璃盘 + 琥珀刻度 + 箭头） |
| **v4.2** | 进桌面到弹窗从 26 秒缩到 9 秒：一次开机只认第一次 arm、绝对死线自校正计时、兜底缓冲 15s→3s |
| **v4.1** | 修复开机后手动点开设置会启动倒计时；打开设置会取消未弹出的跳转 |
| **v4.0** | Apple TV 风格统一、白色 logo 只留"定时启动"四字、倒计时 9 秒且窗口减半、"取消"改"还原"、设置页与桌面 logo 同源 |
| 桌面 v1.0 → v1.47 | CleanYourTV 桌面 → Aerial 桌面（已卸载 CleanYourTV） |
| 桌面 v1.47 → v1.49 | 跟随上游升级；补丁 96 行原样复用。同时发现固件每次开机重置屏保，新增 `restore_dream()` |

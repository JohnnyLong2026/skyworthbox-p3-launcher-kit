# 03 Aerial 桌面部署

上游：[pengchujin/aerial-tv](https://github.com/pengchujin/aerial-tv)，本仓库基于提交 `2b2eb21`（1.61，versionCode 75）。

## 一键装（用现成 APK）

```bash
./scripts/21-build-aerial.sh --apk
```

## 从源码编译

```bash
export ANDROID_HOME=/path/to/android-sdk
./scripts/21-build-aerial.sh
```

脚本会：clone 上游 → checkout `2b2eb21` → 应用 `patches/aerial-tv-p3.patch` →
`./gradlew assembleStandardRelease` → 安装 → `cmd package set-home-activity` → 停用官方桌面。

首次编译约 9 分钟，增量约 2 分钟。签名用本机 debug key（**不能覆盖官方包升级**，升级必须重新编译）。

## 改了什么（`patches/aerial-tv-p3.patch`）

### 1. `app/build.gradle.kts`：改 applicationId

```diff
-        applicationId = "app.orchard.tv"
+        applicationId = "com.ktcp.launcher.aerial"
```

为了过固件的 HOME 前缀白名单。Java 命名空间保持 `app.orchard.tv`，
所以组件全名是 `com.ktcp.launcher.aerial/app.orchard.tv.MainActivity`。

### 2. 新增 `app/src/main/java/app/orchard/tv/system/AutostartBridge.kt`

开机首次进桌面时，显式拉起「定时启动」的 `ReminderService`：

```kotlin
val intent = Intent(ACTION_ARM).setClassName(HELPER, SERVICE)
runCatching { context.startForegroundService(intent) }
```

注意组件名是**混合的**（安装包名 + Java 命名空间）：

```
com.ktcp.launcher.autostart/com.skyworthdigital.autostart.ReminderService
```

去重逻辑：用 `Settings.Global.BOOT_COUNT` + 3 分钟窗口，每次开机只触发一次。

### 3. `MainActivity.kt`：挂上钩子

```kotlin
if (fresh) AutostartBridge.armOncePerBoot(this)
```

### 4. `MainActivity.kt`：`openBootSource()` 延迟 5 秒

Aerial 设置里配了"开机打开的应用"后，桌面一冒头就 `startActivity`，在这台盒子上看着像
根本没进桌面。加 `BOOT_SOURCE_DELAY_MS = 5_000L`：

```kotlin
lifecycleScope.launch {
    delay(BOOT_SOURCE_DELAY_MS)      // 加在函数里，不是调用处
    ...
}
```

**必须加在函数里**：这台机器是 Home Guard 带 `EXTRA_WOKE` 把桌面拉回来的，实际走的是
`openBootSource("brought back on wake")`，不是 `"boot"` 那条。加在 `"boot"` 调用点上
重启实测完全没效果，logcat 会告诉你走的哪条：

```
I/Aerial: brought back on wake: opening 影视仓, what the TV starts on
```

实测开机时间线：桌面 45.818 Displayed → 52.964 才跳走，差 7.1 秒，其中约 2 秒是
`BOOT_APP_NETWORK_WAIT_MS` 在等网络。

## 天气城市

Aerial 存的是**经纬度不是地名**，且写在自己的私有目录（没 root 写不了）。
官方路径是"手机扫码打开的控制页"，走 HTTP 接口：

```bash
./scripts/31-set-weather.sh 北京市                     # 自动：截图解二维码拿 token
./scripts/31-set-weather.sh --url http://192.168.1.100:8790/<token>/ 北京市
```

自动模式的步骤（脚本会提示你配合遥控器）：

1. 脚本先 `KEYCODE_DPAD_UP` 移焦点到状态栏（**焦点在图块上时按 MENU 只会弹图块菜单**），再按 MENU
2. 遥控器进：控制中心 → 个性化 → 右下角二维码
3. 回车 → 脚本 `screencap` + `tools/weather_token.py` 解码 → POST `/api/weather/city`

城市库在上游的 `assets/cities-cn.tsv`（北京 = `39.9075,116.3972`）。
其它接口：`/api/weather/auto`（回到按 IP 猜）、`/api/wallpaper`、`/api/screensaver`、`/api/focus`。

> 截图是 1920×1080，若在预览里看到的是缩放图，裁切坐标要按 1.765 倍换算 —— 所以脚本直接对整图解，最稳。

## 桌面图块的图标

**Aerial 的图块读 `android:banner`（320×180 横图），不是方形 `ic_launcher`。**
换图标必须改 `res/drawable-nodpi/banner.png`，只换 mipmap 在桌面上看不出变化。

## 手动命令备查

```bash
adb shell cmd package set-home-activity --user 0 com.ktcp.launcher.aerial/app.orchard.tv.MainActivity
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
adb shell pm enable com.skyworthdigital.sky2dlauncherv4        # 恢复官方桌面
```

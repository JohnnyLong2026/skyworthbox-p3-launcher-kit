创维小湃 P3 —— 已卸载系统应用的 APK 备份
==========================================
备份时间：2026-10-27 23:37
备份位置：盒子上 /sdcard/p3-backup/，PC 上本仓库 backup/system-apk/

为什么卸：这 4 个包被创维云端下发的「系统控制列表」反复恢复启用
（skycommonpropertymanager → unHiddenSingleApp → setApplicationEnabledSetting）。
包对 user 0 不存在后，云端找不到包，恢复动作直接失效（抛 Unknown package）。

注意：卸载只针对 user 0，APK 仍在 /system 或这里的备份里，随时可装回。
卸载用 pm uninstall -k --user 0，-k 表示保留数据目录。

四个包（含原始版本号）
----------------------
com.skyworthdigital.ottstatsv2       4.62.20   数据采集/埋点（原版在 /system/app/SkyOttstats-origin）
com.skyworthdigital.ott.advert.app   2.17.21   小湃通广告，就是它抢屏保
com.skyworthdigital.skyappupdate     4.60.04   应用更新（系统 OTA 由 com.skyworthdigital.upgrade 管，不受影响）
com.skyworthdigital.logcollector     1.04.01   日志收集

还原方法（任选其一）
--------------------
1) 首选，秒回且不需 APK：

   adb shell pm install-existing com.skyworthdigital.ottstatsv2
   adb shell pm install-existing com.skyworthdigital.ott.advert.app
   adb shell pm install-existing com.skyworthdigital.skyappupdate
   adb shell pm install-existing com.skyworthdigital.logcollector

   装回来的是 /system 分区里的出厂版本（比 data 更新版旧），够用。

2) 想回到卸载前的版本，用这里的 APK 手工装：

   adb install -r -d -k /sdcard/p3-backup/com.skyworthdigital.ottstatsv2.apk

   -r 覆盖安装、-d 允许降级、-k 保留数据。若报签名冲突，先做第 1 步
   再执行 2，或者直接重刷出厂。

3) 全部还原（含被停用的 26 个包）：跑仓库里的 ./scripts/40-restore.sh

恢复出厂设置也会把这 4 个装回来。

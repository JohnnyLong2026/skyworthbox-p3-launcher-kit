# 备份到 GitHub

仓库：<https://github.com/JohnnyLong2026/skyworthbox-p3-launcher-kit>

（注意本地目录名是 `skyworth-p3-launcher-kit`，GitHub 上的仓库名是 `skyworthbox-p3-...`，多了个 box。）

---

## 现在走哪条路

| 目标 | 结果 |
|---|---|
| SSH 22（`git push`） | ✅ **通，已实测**。公钥登记后就一直免密 |
| `git push` 到 github.com（HTTPS 443） | ❌ 沙箱代理 502，去掉代理直连超时 |
| `api.github.com` | ✅ 通，但已经用不上 |

所以现在只走 **SSH**：一次登记公钥，之后 `./50-backup-github.sh` 直接推完，不用 Token、不用输密码。

本机 `~/.ssh/config` 已经为 github.com 单独绑定了 `id_ed25519_p3` 并开了 `IdentitiesOnly`，
不会去试你别的密钥，也不影响其他 SSH 连接。

---

## 第一次：登记公钥（只做一次）

1. 打开 <https://github.com/settings/ssh/new>（Settings → SSH and GPG keys → New SSH key）
2. **Title** 填 `skyworth-p3-launcher-kit`，**Key type** 保持 Authentication Key
3. **Key** 粘贴这一行：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMhfefYq3RGhyoPd94BgESlneGEWbndiOvasTKuPWyDk skyworth-p3-launcher-kit
```

4. Add SSH key

验证：

```bash
ssh -T git@github.com          # 看到 Hi JohnnyLong2026! 就成了
```

---

## 之后每次备份

```bash
cd skyworth-p3-launcher-kit/scripts
./50-backup-github.sh
```

脚本会：确认 SSH 通 → 没有提交就先建一个 → 配好 origin → push 当前分支 → 打出网址。

想打包成 zip 给网页手动上传：

```bash
./50-backup-github.sh --zip    # 生成 ../skyworthbox-p3-launcher-kit.zip
```

> GitHub 网页不会自动解压 zip，直接拖 zip 会被当成单个文件，要先解压再把内容拖进去。

---

## 会备份哪些东西

```
README.md / CHANGELOG.md / LICENSE     总览与更新记录
docs/                                  7 篇 Markdown + 4 份 HTML 说明
scripts/                               10 个部署脚本（体检/优化/构建/部署/备份/还原）
apps/TVAutoStart/                      定时启动完整源码
patches/aerial-tv-p3.patch             Aerial 桌面的 3 处改动（不复制上游 96MB 源码）
apk/                                   2 个成品 APK（Aerial 1.65、定时启动 v4.2）
tools/                                 logo 生成、截图脱敏、天气 token 三个工具
config/                                停用清单、屏保原值备份
assets/screenshots/                    桌面与设置界面截图
```

`build/`、`.gradle/`、`local.properties` 都被 `.gitignore` 挡在外面，不会传。

只留当前版本：Aerial 1.47 和定时启动 v4.0 的 APK 已经删掉，
探索期的 logo 比稿脚本（`logo_d.py` / `logo_proposal.py` / `make_banner.py`）也已删除——
最终采用的方案是 `tools/make_logo_white.py`。

---

## 出问题先看这些

| 现象 | 原因 / 处理 |
|---|---|
| `Permission denied (publickey)` | 公钥没登记，或 `~/.ssh/config` 被改过。跑 `ssh -Tv git@github.com` 看它拿的是哪把钥匙 |
| `Hi xxx!` 里用户名不对 | 用的不是 `id_ed25519_p3` 那把钥匙，检查 `~/.ssh/config` 的 `IdentityFile` |
| `repository not found` | 仓库还没建，或名字不对（是 `skyworthbox-p3-launcher-kit`） |
| `src refspec main does not match any` | 本地还没有提交，脚本会自动建一个；手动跑就先 `git add -A && git commit -m "…"` |
| `Updates were rejected` | 远端有本地没有的提交（比如网页上改过 README），先 `git pull --rebase` |
| 推送很慢 | 两个 APK 加起来 3MB，正常几秒；卡住就 `Ctrl+C` 重来 |

> 以前这台机器只能拿 Token 调 REST API（`tools/github_backup.py`），那条路子连同脚本一起删了。
> 如果你是在别的机器上、确实走不了 SSH，用 `GIT_SSH_COMMAND` 或配 HTTPS + 凭据助手即可，
> 不用再找那个脚本。

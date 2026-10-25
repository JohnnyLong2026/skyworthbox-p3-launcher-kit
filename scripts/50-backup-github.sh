#!/bin/bash
# ============================================================
# 50 备份到 GitHub
#
#   ./50-backup-github.sh                 推送到 GitHub（走 SSH，免密）
#   GITHUB_USER=xxx ./50-backup-github.sh 指定用户名（也可以写进 box.conf）
#   ./50-backup-github.sh --zip           只打包成 zip，供网页手动上传
#
# 走 SSH：公钥登记到 GitHub 之后就一直免密，不用 Token，也不用每次输密码。
# 本机 ~/.ssh/config 已经为 github.com 绑定了 id_ed25519_p3，不影响其他 SSH 连接。
# 还没登记公钥的话，脚本会把公钥打出来，告诉你去哪儿加。
#
# 以前这台机器 git(443) 不通，只能拿 Token 调 REST API（tools/github_backup.py）。
# 现在 SSH 通了，那条路子已经删掉。
# ============================================================
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

REPO_NAME="${GITHUB_REPO:-skyworthbox-p3-launcher-kit}"
REPO_URL="https://github.com/JohnnyLong2026/$REPO_NAME"

case "$1" in
  --zip)
    info "打包 zip（给 GitHub 网页手动上传用）"
    OUT="$REPO_ROOT/../$REPO_NAME.zip"
    (cd "$REPO_ROOT" && git archive --format=zip --prefix="$REPO_NAME/" -o "$OUT" HEAD) \
      || die "打包失败（HEAD 不存在？先提交一次）"
    ls -lh "$OUT" | awk '{print "  " $5 "  " $9}'
    echo
    echo "  网页步骤：先建空仓库 → Add file → Upload files → 解压这个 zip 后把里面的内容拖进去"
    exit 0
    ;;
esac

command -v git >/dev/null 2>&1 || die "没有 git"

# 先认路：公钥登记了没有
if ! timeout 20 ssh -T git@github.com 2>&1 | grep -qi "successfully authenticated"; then
  warn "SSH 还没通：GitHub 上还没有这把公钥"
  echo
  echo "  1) 复制下面这一行："
  echo
  cat ~/.ssh/id_ed25519_p3.pub 2>/dev/null \
    || ssh-keygen -y -f ~/.ssh/id_ed25519_p3 2>/dev/null \
    || echo "  （没找到 id_ed25519_p3，先跑：ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_p3）"
  echo
  echo "  2) 打开 https://github.com/settings/ssh/new → New SSH key → 粘贴 → Add SSH key"
  echo "  3) 回来再跑一次这个脚本"
  exit 1
fi

info "推送到 GitHub（$REPO_NAME）"

cd "$REPO_ROOT" || die "进不去 $REPO_ROOT"

# 没有提交就先提交，免得 push 空仓库
if [ -z "$(git log --oneline -1 2>/dev/null)" ]; then
  info "还没有提交，先建第一个提交"
  git add -A || die "git add 失败"
  git commit -q -m "初始提交：P3 桌面与定时启动完整方案" || die "git commit 失败"
fi

git remote remove origin 2>/dev/null
git remote add origin "git@github.com:JohnnyLong2026/$REPO_NAME.git"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

git push -u origin "$BRANCH" || die "push 失败。仓库存在吗？$REPO_URL"

ok "已推送 → $REPO_URL/tree/$BRANCH"

#!/usr/bin/env bash

set -euo pipefail

# 用法:
#   ./git-auto.sh "你的提交信息"
#   ./git-auto.sh
#   ./git-auto.sh --watch
#   ./git-auto.sh --watch "你的提交信息"

DEFAULT_MSG="chore: auto commit"
WATCH_MODE="false"

if [[ "${1:-}" == "--watch" ]]; then
  WATCH_MODE="true"
  shift
fi

COMMIT_MSG="${1:-$DEFAULT_MSG}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "错误: 当前目录不是 git 仓库"
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "错误: 无法识别当前分支"
  exit 1
fi

commit_once() {
  if [[ -z "$(git status --porcelain)" ]]; then
    return 0
  fi

  echo "开始执行: git add ."
  git add .

  echo "开始执行: git commit"
  git commit -m "$COMMIT_MSG"

  echo "开始执行: git push origin $CURRENT_BRANCH"
  git push origin "$CURRENT_BRANCH"

  echo "完成: 已提交并推送到 origin/$CURRENT_BRANCH"
}

if [[ "$WATCH_MODE" == "false" ]]; then
  if [[ -z "$(git status --porcelain)" ]]; then
    echo "没有检测到变更，无需提交。"
    exit 0
  fi
  commit_once
  exit 0
fi

echo "已进入监听模式，每 60 秒检查一次变更。按 Ctrl+C 退出。"
while true; do
  if [[ -n "$(git status --porcelain)" ]]; then
    commit_once
  fi
  sleep 60
done

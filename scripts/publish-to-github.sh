#!/usr/bin/env bash
set -Eeuo pipefail

REPO_NAME="${REPO_NAME:-orbstack-ubuntu-tailscale-ssh}"
DESCRIPTION="${DESCRIPTION:-OrbStack Ubuntu VM Tailscale SSH setup for terminal and VS Code Remote - SSH}"

if ! command -v git >/dev/null 2>&1; then
  printf 'git is required.\n' >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  printf 'GitHub CLI (gh) is required: https://cli.github.com/\n' >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  printf 'Run gh auth login first.\n' >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init
fi

git branch -M main

if [[ -n "$(git status --short)" ]]; then
  git add .
  git commit -m "Update OrbStack Tailscale SSH setup"
fi

if git remote get-url origin >/dev/null 2>&1; then
  printf 'origin already exists: %s\n' "$(git remote get-url origin)"
  printf 'Pushing main to origin.\n'
  git push -u origin main
else
  gh repo create "$REPO_NAME" \
    --public \
    --description "$DESCRIPTION" \
    --source=. \
    --remote=origin \
    --push
fi

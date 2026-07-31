#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
USE_HASH_ROUTER="${USE_HASH_ROUTER:-true}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-Configure GitHub Pages deployment}"

print_usage() {
  cat <<EOF
Vue + Vite 프로젝트를 GitHub Pages에 배포하기 위한 초기 설정 스크립트

사용법:
  $SCRIPT_NAME <GitHub사용자명> <저장소명> [프로젝트경로]

예:
  $SCRIPT_NAME yangssem skala-vue ~/projects/skala-vue

환경 변수:
  USE_HASH_ROUTER=false
      Vue Router를 createWebHashHistory로 자동 변경하지 않습니다.

  COMMIT_MESSAGE="메시지"
      Git 커밋 메시지를 변경합니다.

사전 조건:
  1. GitHub에 저장소가 먼저 만들어져 있어야 합니다.
  2. 새 저장소는 README, .gitignore, License 없이 비어 있는 것이 좋습니다.
  3. git, node, npm이 설치되어 있어야 합니다.
EOF
}

info() {
  printf '\n[%s] %s\n' "INFO" "$*"
}

warn() {
  printf '\n[%s] %s\n' "WARN" "$*" >&2
}

die() {
  printf '\n[%s] %s\n' "ERROR" "$*" >&2
  exit 1
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' 명령을 찾을 수 없습니다."
}

ensure_gitignore_line() {
  local line="$1"
  if ! grep -qxF "$line" .gitignore 2>/dev/null; then
    printf '%s\n' "$line" >> .gitignore
  fi
}

configure_pages_manually() {
  warn "GitHub CLI로 Pages를 자동 활성화하지 못했습니다."
  printf '%s\n' "브라우저에서 다음 주소를 여세요:"
  printf '  https://github.com/%s/%s/settings/pages\n' "$GITHUB_OWNER" "$REPOSITORY"
  printf '%s\n' "Build and deployment → Source → GitHub Actions를 선택하세요."
  read -r -p "설정을 마쳤다면 Enter를 누르세요: "
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

[[ $# -ge 2 && $# -le 3 ]] || {
  print_usage
  exit 1
}

GITHUB_OWNER="$1"
REPOSITORY="$2"
PROJECT_DIRECTORY="${3:-.}"
REMOTE_URL="https://github.com/${GITHUB_OWNER}/${REPOSITORY}.git"
PAGES_URL="https://${GITHUB_OWNER}.github.io/${REPOSITORY}/"
BASE_PATH="/${REPOSITORY}/"

ensure_command git
ensure_command node
ensure_command npm

cd "$PROJECT_DIRECTORY"
PROJECT_DIRECTORY="$(pwd)"

[[ -f package.json ]] || die "package.json이 없습니다. Vue 프로젝트 루트에서 실행하세요."

if [[ -f vite.config.js ]]; then
  VITE_CONFIG="vite.config.js"
elif [[ -f vite.config.ts ]]; then
  VITE_CONFIG="vite.config.ts"
else
  die "vite.config.js 또는 vite.config.ts를 찾을 수 없습니다."
fi

info "프로젝트: $PROJECT_DIRECTORY"
info "원격 저장소: $REMOTE_URL"
info "예상 Pages 주소: $PAGES_URL"

if [[ ! -d .git ]]; then
  info "로컬 Git 저장소를 초기화합니다."
  git init
fi

if [[ -z "$(git config user.name || true)" ]]; then
  die "Git 사용자 이름이 없습니다. 먼저 'git config --global user.name \"이름\"'을 실행하세요."
fi

if [[ -z "$(git config user.email || true)" ]]; then
  die "Git 이메일이 없습니다. 먼저 'git config --global user.email \"이메일\"'을 실행하세요."
fi

if git remote get-url origin >/dev/null 2>&1; then
  CURRENT_REMOTE="$(git remote get-url origin)"
  if [[ "$CURRENT_REMOTE" != "$REMOTE_URL" ]]; then
    info "기존 origin 주소를 새 저장소 주소로 변경합니다."
    git remote set-url origin "$REMOTE_URL"
  else
    info "origin 주소가 이미 정확합니다."
  fi
else
  info "origin 원격 저장소를 등록합니다."
  git remote add origin "$REMOTE_URL"
fi

git branch -M main

info "환경 파일과 빌드 결과를 .gitignore에 등록합니다."
touch .gitignore
ensure_gitignore_line "node_modules"
ensure_gitignore_line "dist"
ensure_gitignore_line ".env"
ensure_gitignore_line ".env.*"
ensure_gitignore_line "!.env.example"

TRACKED_ENV_FILES="$(
  git ls-files '.env*' |
    while IFS= read -r file; do
      if [[ "$file" != ".env.example" ]]; then
        printf '%s\n' "$file"
      fi
    done
)"

if [[ -n "$TRACKED_ENV_FILES" ]]; then
  printf '%s\n' "$TRACKED_ENV_FILES" >&2
  die "위 환경 파일이 이미 Git에서 추적 중입니다. 비밀값을 확인하고 'git rm --cached <파일>'로 추적을 중단한 뒤 다시 실행하세요."
fi

info "$VITE_CONFIG의 base를 '$BASE_PATH'로 설정합니다."
node --input-type=commonjs - "$VITE_CONFIG" "$REPOSITORY" <<'NODE'
const fs = require('node:fs')

const configPath = process.argv[2]
const repository = process.argv[3]
const expectedBase = `/${repository}/`
let source = fs.readFileSync(configPath, 'utf8')

const baseLine = /^(\s*)base\s*:\s*[^,\n]+,?\s*$/m

if (baseLine.test(source)) {
  source = source.replace(baseLine, (_, indent) => {
    return `${indent}base: '${expectedBase}',`
  })
} else {
  const defineConfigObject = /defineConfig\s*\(\s*\{/

  if (!defineConfigObject.test(source)) {
    console.error(
      `자동 수정 실패: ${configPath}에서 defineConfig({ ... }) 형식을 찾지 못했습니다.`,
    )
    process.exit(1)
  }

  source = source.replace(
    defineConfigObject,
    (match) => `${match}\n  base: '${expectedBase}',`,
  )
}

fs.writeFileSync(configPath, source)
NODE

if [[ "$USE_HASH_ROUTER" == "true" && -f src/router/index.js ]]; then
  if grep -q "createWebHistory" src/router/index.js; then
    info "GitHub Pages 새로고침 404 방지를 위해 Vue Router를 Hash 모드로 변경합니다."
    node --input-type=commonjs <<'NODE'
const fs = require('node:fs')
const routerPath = 'src/router/index.js'
const source = fs.readFileSync(routerPath, 'utf8')
const updated = source.replaceAll('createWebHistory', 'createWebHashHistory')
fs.writeFileSync(routerPath, updated)
NODE
  fi
fi

info "정확한 경로에 GitHub Actions 워크플로를 생성합니다."
mkdir -p .github/workflows

cat > .github/workflows/deploy.yml <<'YAML'
name: Deploy Vue to GitHub Pages

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    runs-on: ubuntu-latest

    steps:
      - name: Checkout source
        uses: actions/checkout@v7

      - name: Setup Node.js
        uses: actions/setup-node@v6
        with:
          node-version: lts/*
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Build Vue application
        run: npm run build

      - name: Setup GitHub Pages
        uses: actions/configure-pages@v6

      - name: Upload build output
        uses: actions/upload-pages-artifact@v5
        with:
          path: ./dist

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v5
YAML

if [[ ! -f package-lock.json ]]; then
  info "package-lock.json이 없어 npm install을 실행합니다."
  npm install
fi

info "로컬 프로덕션 빌드를 검사합니다."
npm run build

PAGES_CONFIGURED="false"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  info "GitHub CLI를 이용해 Pages 배포 방식을 GitHub Actions로 설정합니다."

  if gh api "repos/${GITHUB_OWNER}/${REPOSITORY}/pages" >/dev/null 2>&1; then
    if gh api \
      --method PUT \
      "repos/${GITHUB_OWNER}/${REPOSITORY}/pages" \
      -f build_type=workflow >/dev/null 2>&1; then
      PAGES_CONFIGURED="true"
    fi
  else
    if gh api \
      --method POST \
      "repos/${GITHUB_OWNER}/${REPOSITORY}/pages" \
      -f build_type=workflow >/dev/null 2>&1; then
      PAGES_CONFIGURED="true"
    fi
  fi
fi

if [[ "$PAGES_CONFIGURED" != "true" ]]; then
  configure_pages_manually
fi

info "Git 커밋 대상 파일을 준비합니다."
git add -A
git diff --cached --name-only

printf '\n'
read -r -p "위 파일을 커밋하고 GitHub에 Push할까요? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  warn "커밋과 Push를 취소했습니다. 스테이징된 변경은 그대로 유지됩니다."
  exit 0
fi

if git diff --cached --quiet; then
  info "파일 변경이 없어 배포 재실행용 빈 커밋을 만듭니다."
  git commit --allow-empty -m "Trigger GitHub Pages deployment"
else
  git commit -m "$COMMIT_MESSAGE"
fi

info "main 브랜치를 GitHub에 Push합니다."
git push -u origin main

printf '\n%s\n' "설정과 Push가 완료되었습니다."
printf 'Actions: https://github.com/%s/%s/actions\n' "$GITHUB_OWNER" "$REPOSITORY"
printf 'Pages:   %s\n' "$PAGES_URL"
printf '%s\n' "Actions가 초록색으로 완료된 뒤 Pages 주소를 여세요."

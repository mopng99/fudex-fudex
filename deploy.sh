#!/usr/bin/env bash
# =============================================================================
# deploy.sh — ابنِ هذا المشروع من نواة + طبقة توافق.
#
#   ./deploy.sh --dry-run        اعرض ما سيحدث دون كتابة
#   ./deploy.sh                  اكتب في app_root
#
# الترتيب: نجلب النواة عند core_ref، ثم نستدعي أداتها، وهي تركّب النواة
# ثم تحطّ custom/ فوقها. كود هذا المشروع لا يُلمس أبداً.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_YML="$ROOT/project.yml"

die() { printf '\033[31mخطأ:\033[0m %s\n' "$1" >&2; exit 1; }
say() { printf '  %s\n' "$1"; }

# project.yml: read the key from the line's FIRST colon only.  An ssh url
# (git@host:org/repo) carries colons of its own, and splitting the line in
# two would cut the url off at 'git@github.com' - then git looks for a
# repository named exactly that, and the deploy fails before it starts.
cfg() {
  sed -n "s/^$1:[[:space:]]*//p" "$PROJECT_YML" | head -n1 | tr -d '"'\'' \r'
}

DRY=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY="--dry-run" ;;
    *) die "خيار غير معروف: $a" ;;
  esac
done

[ -f "$PROJECT_YML" ] || die "project.yml غير موجود بجوار deploy.sh"
[ -d "$ROOT/custom" ]  || die "مجلد custom/ غير موجود — أين كود المشروع؟"

NAME="$(cfg name)";        [ -n "$NAME" ]     || die "project.yml: name مفقود"
CORE_REF="$(cfg core_ref)"; [ -n "$CORE_REF" ] || die "project.yml: core_ref مفقود"
CORE_REPO="$(cfg core_repo)"
APP_ROOT="${FUERP_APP_ROOT:-$(cfg app_root)}"
[ -n "$APP_ROOT" ] || die "project.yml: app_root مفقود"

echo "=============================="
echo " مشروع : $NAME"
echo " نواة  : $CORE_REF"
echo " هدف   : $APP_ROOT"
echo "=============================="

# ---- 1. جلب النواة عند الوسم المحدد ----------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/$NAME-core-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

CORE_DIR="$WORK/fuerp-fudex"
if [ -n "${FUERP_CORE_REPO:-}" ] && [ -d "${FUERP_CORE_REPO}/.git" ]; then
  say "النواة من نسخة محلية: $FUERP_CORE_REPO"
  git clone --quiet --local "$FUERP_CORE_REPO" "$CORE_DIR"
  git -C "$CORE_DIR" checkout --quiet "$CORE_REF" \
    || die "الوسم غير موجود محلياً: $CORE_REF"
  CORE_REPO="$FUERP_CORE_REPO"
elif [ -d "${CORE_REPO:-}/.git" ]; then
  say "النواة من نسخة محلية: $CORE_REPO"
  git clone --quiet --local "$CORE_REPO" "$CORE_DIR"
  git -C "$CORE_DIR" checkout --quiet "$CORE_REF" || die "الوسم غير موجود: $CORE_REF"
else
  say "النواة من: $CORE_REPO @ $CORE_REF"
  git clone --quiet --branch "$CORE_REF" --depth 1 "$CORE_REPO" "$CORE_DIR" \
    || die "تعذّر جلب $CORE_REF من $CORE_REPO"
fi

[ -x "$CORE_DIR/tools/deploy_core.sh" ] || die "أداة النواة tools/deploy_core.sh غير موجودة"
say "نواة النواة: $(cat "$CORE_DIR/VERSION" 2>/dev/null || echo '?') @ $(git -C "$CORE_DIR" rev-parse --short HEAD)"

# ---- 2. النواة تركّب نفسها ثم تحطّ طبقتنا فوقها -------------------
FUERP_CORE_REPO="$CORE_DIR" \
  "$CORE_DIR/tools/deploy_core.sh" \
    --core-ref "$CORE_REF" \
    --custom   "$ROOT/custom" \
    --target   "$APP_ROOT" \
    $DRY

# ---- 3. ماذاsfnresh للمشروع نفسه --------------------------------------------
echo
say "منقول إلى $APP_ROOT:"
( cd "$ROOT/custom" && find . -type f | sed 's|^\./|    |' )

echo
printf '\033[32mتمّ\033[0m — %s على نواة %s\n' "$NAME" "$CORE_REF"
if [ -z "$DRY" ]; then
  echo "بقيت خطوة واحدة خارج هذا السكربت: أعد تشغيل الخدمة وتشغيل الترحيلات."
fi

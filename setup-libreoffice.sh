#!/usr/bin/env bash
# =============================================================================
# Setup LibreOffice cho macOS / Linux de convert Word -> PDF (.NET 9 API)
# -----------------------------------------------------------------------------
#  - Cai dat LibreOffice qua package manager (apt/dnf/yum/zypper/pacman/apk/brew)
#  - Tao thu muc profile + temp va cap quyen cho service user
#  - Test convert thu mot file
#  - In ra doan appsettings.json (ExecutablePath / ProfileBaseDir)
#
#  Tuong duong ban Windows: Setup-LibreOffice.ps1
#
#  Usage:
#     chmod +x setup-libreoffice.sh
#     sudo ./setup-libreoffice.sh
#     sudo ./setup-libreoffice.sh --service-user www-data
#     sudo ./setup-libreoffice.sh --profile-dir /var/lib/lo-profiles
#
#  Tren macOS thuong KHONG can sudo (neu dung Homebrew).
# =============================================================================
set -uo pipefail

# ─── Defaults (co the override bang flag) ────────────────────────────────────
SERVICE_USER=""                 # user ma .NET app chay duoi quyen (de chown)
PROFILE_DIR=""                  # de trong -> tu chon theo OS
SKIP_INSTALL=0                  # 1 = bo qua buoc cai, chi config + test
SKIP_TEST=0                     # 1 = bo qua test convert

# ─── Colors / helpers ────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_CYAN='\033[0;36m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'
  C_RED='\033[0;31m'; C_RESET='\033[0m'
else
  C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_RESET=''
fi
step() { printf "\n${C_CYAN}[STEP] %s${C_RESET}\n" "$1"; }
ok()   { printf "  ${C_GREEN}[OK] %s${C_RESET}\n" "$1"; }
warn() { printf "  ${C_YELLOW}[!!] %s${C_RESET}\n" "$1"; }
fail() { printf " ${C_RED}[ERR] %s${C_RESET}\n" "$1"; }
die()  { fail "$1"; exit 1; }

# ─── Parse args ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --service-user) SERVICE_USER="$2"; shift 2 ;;
    --profile-dir)  PROFILE_DIR="$2";  shift 2 ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --skip-test)    SKIP_TEST=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Tham so khong hop le: $1 (dung --help)" ;;
  esac
done

# ─── Detect OS ───────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *) die "He dieu hanh khong ho tro: $OS (script nay cho macOS/Linux)" ;;
esac

# Chon profile dir mac dinh theo OS neu chua truyen
if [ -z "$PROFILE_DIR" ]; then
  if [ "$PLATFORM" = "macos" ]; then
    PROFILE_DIR="/Users/Shared/LibreOfficeProfiles"
  else
    PROFILE_DIR="/var/lib/libreoffice-profiles"
  fi
fi

printf "${C_CYAN}"
cat <<'BANNER'

+======================================================+
|   LibreOffice Setup (macOS / Linux)                  |
|   Word -> PDF Converter for .NET 9 API               |
+======================================================+
BANNER
printf "${C_RESET}"
echo "  Platform     : $PLATFORM ($OS)"
echo "  Profile Dir  : $PROFILE_DIR"
echo "  Service User : ${SERVICE_USER:-<none / current user>}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1 - Tim soffice
# ═══════════════════════════════════════════════════════════════════════════
step "1/5 - Kiem tra LibreOffice da cai chua"

find_soffice() {
  # Tra ve duong dan soffice neu tim thay
  if command -v soffice >/dev/null 2>&1; then
    command -v soffice; return 0
  fi
  if command -v libreoffice >/dev/null 2>&1; then
    command -v libreoffice; return 0
  fi
  local candidates=(
    "/Applications/LibreOffice.app/Contents/MacOS/soffice"
    "/usr/bin/soffice"
    "/usr/local/bin/soffice"
    "/opt/libreoffice/program/soffice"
  )
  local c
  for c in "${candidates[@]}"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  # opt/libreofficeX.Y/program/soffice
  c="$(ls -d /opt/libreoffice*/program/soffice 2>/dev/null | head -n1)"
  [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  return 1
}

SOFFICE="$(find_soffice || true)"
if [ -n "$SOFFICE" ]; then
  ok "Da co LibreOffice: $SOFFICE"
else
  warn "Chua tim thay soffice."
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2 - Cai dat (neu can)
# ═══════════════════════════════════════════════════════════════════════════
step "2/5 - Cai dat LibreOffice"

run_priv() {
  # Chay lenh voi quyen root khi can
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "Can quyen root de cai dat. Hay chay lai voi sudo."
  fi
}

install_linux() {
  if   command -v apt-get >/dev/null 2>&1; then
    run_priv apt-get update -y
    run_priv apt-get install -y libreoffice-core libreoffice-writer \
                                fonts-dejavu fonts-liberation
  elif command -v dnf >/dev/null 2>&1; then
    run_priv dnf install -y libreoffice-core libreoffice-writer \
                            libreoffice-headless dejavu-sans-fonts || \
    run_priv dnf install -y libreoffice-core libreoffice-writer dejavu-sans-fonts
  elif command -v yum >/dev/null 2>&1; then
    run_priv yum install -y libreoffice-core libreoffice-writer dejavu-sans-fonts
  elif command -v zypper >/dev/null 2>&1; then
    run_priv zypper --non-interactive install libreoffice-writer dejavu-fonts
  elif command -v pacman >/dev/null 2>&1; then
    run_priv pacman -Sy --noconfirm libreoffice-still ttf-dejavu
  elif command -v apk >/dev/null 2>&1; then
    run_priv apk add --no-cache libreoffice ttf-dejavu font-liberation
  else
    die "Khong nhan dien duoc package manager (apt/dnf/yum/zypper/pacman/apk).
     Hay cai LibreOffice thu cong roi chay lai voi --skip-install."
  fi
}

install_macos() {
  if command -v brew >/dev/null 2>&1; then
    # Khong dung sudo voi brew
    brew install --cask libreoffice
  else
    die "Khong tim thay Homebrew.
     Cach 1: cai brew (https://brew.sh) roi chay lai script.
     Cach 2: tai .dmg tu https://www.libreoffice.org/download va keo vao /Applications,
             sau do chay lai voi --skip-install."
  fi
}

if [ -n "$SOFFICE" ]; then
  warn "Da cai roi -> bo qua buoc cai dat."
elif [ "$SKIP_INSTALL" -eq 1 ]; then
  die "Co --skip-install nhung khong tim thay soffice. Hay cai thu cong truoc."
else
  echo "  Dang cai dat (vui long cho)..."
  if [ "$PLATFORM" = "macos" ]; then install_macos; else install_linux; fi
  SOFFICE="$(find_soffice || true)"
  [ -n "$SOFFICE" ] || die "Cai xong nhung van khong tim thay soffice. Kiem tra lai."
  ok "Cai dat thanh cong: $SOFFICE"
fi

# Version
if VER="$("$SOFFICE" --version 2>/dev/null | head -n1)"; then
  ok "Version: $VER"
else
  warn "Khong lay duoc version (van co the chay duoc)."
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3 - Tao profile dir + temp dir va cap quyen
# ═══════════════════════════════════════════════════════════════════════════
step "3/5 - Tao thu muc profile + temp va cap quyen"

TEMP_LO="${TMPDIR:-/tmp}/lo_convert"

make_dir() {
  local d="$1"
  if [ -d "$d" ]; then ok "Da ton tai: $d"; return; fi
  if mkdir -p "$d" 2>/dev/null; then ok "Da tao: $d"
  else run_priv mkdir -p "$d" && ok "Da tao (sudo): $d"; fi
}

make_dir "$PROFILE_DIR"
make_dir "$TEMP_LO"

if [ -n "$SERVICE_USER" ]; then
  if id "$SERVICE_USER" >/dev/null 2>&1; then
    run_priv chown -R "$SERVICE_USER" "$PROFILE_DIR" "$TEMP_LO" 2>/dev/null \
      && ok "Da chown cho '$SERVICE_USER': $PROFILE_DIR, $TEMP_LO" \
      || warn "Khong chown duoc cho '$SERVICE_USER'."
    run_priv chmod -R u+rwX "$PROFILE_DIR" "$TEMP_LO" 2>/dev/null || true
  else
    warn "User '$SERVICE_USER' khong ton tai -> bo qua chown. Cap quyen 1777 thay the."
    run_priv chmod 1777 "$PROFILE_DIR" "$TEMP_LO" 2>/dev/null || true
  fi
else
  # Khong biet service user -> cho moi user ghi duoc (sticky)
  chmod 1777 "$PROFILE_DIR" "$TEMP_LO" 2>/dev/null \
    || run_priv chmod 1777 "$PROFILE_DIR" "$TEMP_LO" 2>/dev/null || true
  ok "Da cap quyen 1777 (chua chi dinh --service-user)."
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4 - Test convert thu
# ═══════════════════════════════════════════════════════════════════════════
step "4/5 - Test convert RTF -> PDF"

if [ "$SKIP_TEST" -eq 1 ]; then
  warn "Bo qua test (--skip-test)."
else
  TEST_DIR="$(mktemp -d)"
  TEST_IN="$TEST_DIR/lo_test.rtf"
  TEST_OUT="$TEST_DIR/out"
  TEST_PROFILE="$TEST_DIR/profile"
  mkdir -p "$TEST_OUT" "$TEST_PROFILE"
  printf '{\\rtf1 LibreOffice Test OK}' > "$TEST_IN"

  echo "  Dang convert file test..."
  if "$SOFFICE" \
        "-env:UserInstallation=file://$TEST_PROFILE" \
        --headless --norestore --nofirststartwizard \
        --convert-to pdf --outdir "$TEST_OUT" "$TEST_IN" >/dev/null 2>&1 \
     && [ -f "$TEST_OUT/lo_test.pdf" ]; then
    SIZE="$(wc -c < "$TEST_OUT/lo_test.pdf" | tr -d ' ')"
    ok "Convert thanh cong! PDF: ${SIZE} bytes"
  else
    fail "Test convert that bai. Kiem tra lai cai dat / quyen thu muc."
  fi
  rm -rf "$TEST_DIR" 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5 - Tong ket + appsettings.json
# ═══════════════════════════════════════════════════════════════════════════
step "5/5 - Hoan tat"

# Escape khong can thiet tren *nix (khong co backslash) -> dung nguyen ban
printf "${C_GREEN}"
cat <<'DONE'

+======================================================+
|   SETUP HOAN TAT                                     |
+======================================================+
DONE
printf "${C_RESET}"
echo "  soffice      : $SOFFICE"
echo "  Profile Dir  : $PROFILE_DIR"
echo ""
printf "${C_YELLOW}  Them vao appsettings.json cua .NET API:${C_RESET}\n"
cat <<JSON
  {
    "LibreOffice": {
      "ExecutablePath": "$SOFFICE",
      "ProfileBaseDir": "$PROFILE_DIR",
      "TimeoutSeconds": 60,
      "MaxConcurrent": 4,
      "IsOn": true
    }
  }
JSON
echo ""
if [ -n "$SERVICE_USER" ]; then
  echo "  Luu y: dam bao service .NET chay duoi user '$SERVICE_USER'."
else
  printf "  ${C_YELLOW}Luu y: nen chay lai voi --service-user <user> de chown dung profile dir.${C_RESET}\n"
fi

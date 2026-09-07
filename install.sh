#!/usr/bin/env bash
# install.sh — install Cardwall
# Full install: sudo ./install.sh
set -euo pipefail

# ── helpers ────────────────────────────────────────────────────────────────
info()  { echo "  [INFO]  $*"; }
warn()  { echo "  [WARN]  $*"; }
error() { echo "  [ERR]   $*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || error "The full installation must be run as root (sudo bash install.sh)"

# ── Detect the real desktop user ──────────────────────────────────────────
#
# When run with sudo:
#   $USER   may be "root"
#   $HOME   may be "/root"
#   $SUDO_USER is the user who invoked sudo
#
# We want the real user's home for the Anki add-on.

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$USER"
fi

REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

[[ -n "$REAL_HOME" && -d "$REAL_HOME" ]] || \
  error "Could not determine home directory for user '$REAL_USER'."

info "Real user: $REAL_USER"
info "Real home: $REAL_HOME"

# ── 0. Pre-flight: X11 requirement ────────────────────────────────────────
check_x11() {
  # Cardwall registers an xsessions entry and only works under X11.
  # Detect if the current session or GDM configuration is Wayland-only.

  # If we're already inside a running session, $XDG_SESSION_TYPE tells us.
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    warn "You are currently running a Wayland session (XDG_SESSION_TYPE=wayland)."
    warn "Cardwall requires X11. Before using Cardwall you must enable X11 in GDM:"
    warn ""
    warn "  1. Edit /etc/gdm3/custom.conf  (Ubuntu)  or"
    warn "          /etc/gdm/custom.conf   (Fedora/Arch)"
    warn "  2. Under [daemon] add or uncomment:  WaylandEnable=false"
    warn "  3. Reboot, then log in."
    warn ""
    warn "Continuing install, but Cardwall will NOT appear in GDM until X11 is enabled."
  fi

  # Also warn if GDM config explicitly has WaylandEnable=true (or is missing the disable flag).
  for gdm_conf in /etc/gdm3/custom.conf /etc/gdm/custom.conf; do
    if [[ -f "$gdm_conf" ]]; then
      if ! grep -qiE '^\s*WaylandEnable\s*=\s*false' "$gdm_conf"; then
        warn "GDM config ($gdm_conf) does not have 'WaylandEnable=false'."
        warn "GDM may default to Wayland and hide the Cardwall session entry."
        warn "Add the following under [daemon] to force X11:"
        warn "    WaylandEnable=false"
      fi
      break
    fi
  done
}

check_x11

command -v xdotool >/dev/null 2>&1 || error "xdotool is not installed. Cardwall requires it to pin the Anki window to half the screen. Install it via your package manager and re-run this script."
command -v nano >/dev/null 2>&1 || error "nano is not installed. Cardwall requires it for the editor pane. Install it via your package manager and re-run this script."
command -v xterm >/dev/null 2>&1 || error "xterm is not installed. Cardwall requires it to run nano before the desktop starts. Install it via your package manager and re-run this script."
python3 -c 'import Xlib' >/dev/null 2>&1 || error "python-xlib is not installed. Cardwall requires it for click-to-focus before the desktop starts. Install it via your package manager (e.g. python3-xlib) and re-run this script."

# ── 1. Anki add-on ─────────────────────────────────────────────────────────
install_addon() {
  local addon_dir

  # Use the REAL user's home directory, not root's $HOME when invoked via sudo.
  if [[ -d "${REAL_HOME}/.var/app/net.ankiweb.Anki/data/Anki2/addons21" ]]; then
    addon_dir="${REAL_HOME}/.var/app/net.ankiweb.Anki/data/Anki2/addons21/cardwall"
  elif [[ -d "${REAL_HOME}/.local/share/Anki2/addons21" ]]; then
    addon_dir="${REAL_HOME}/.local/share/Anki2/addons21/cardwall"
  else
    error "Could not find Anki add-ons directory for user '$REAL_USER'. Is Anki installed?"
  fi

  info "Installing add-on for user '$REAL_USER' to: $addon_dir"

  mkdir -p "$addon_dir"

  cp anki-addon/__init__.py "$addon_dir/__init__.py"
  cp anki-addon/manifest.json "$addon_dir/manifest.json"

  # If the installer was run with sudo, make sure the user's files
  # remain owned by the real user rather than root.
  if [[ "$EUID" -eq 0 ]]; then
    chown -R "$REAL_USER:$REAL_USER" "$addon_dir"
  fi

  info "Add-on installed. Restart Anki to activate it."
}

install_addon

# ── 2. Root-required steps ─────────────────────────────────────────────────
# 2a. Session binary
info "Installing session binary to /usr/local/bin/cardwall-session"
install -m 755 x11-session/cardwall-session /usr/local/bin/cardwall-session

# 2b. GDM session entry
SESSION_DIR="/usr/share/xsessions"
SESSION_STATE_DIR="/var/lib/cardwall"
DISABLED_SESSIONS_FILE="$SESSION_STATE_DIR/disabled-xsessions.list"

info "Disabling other X11 sessions in $SESSION_DIR"
mkdir -p "$SESSION_STATE_DIR"
touch "$DISABLED_SESSIONS_FILE"
while IFS= read -r -d '' session_file; do
  disabled_file="${session_file}.disabled"
  if [[ -e "$disabled_file" ]]; then
    warn "Skipping $session_file because $disabled_file already exists."
    continue
  fi
  mv "$session_file" "$disabled_file"
  printf '%s\n' "$session_file" >> "$DISABLED_SESSIONS_FILE"
  info "Disabled $session_file"
done < <(find "$SESSION_DIR" -maxdepth 1 -type f -name '*.desktop' \
  ! -name 'cardwall.desktop' -print0)
sort -u "$DISABLED_SESSIONS_FILE" -o "$DISABLED_SESSIONS_FILE"

info "Installing session entry to $SESSION_DIR/cardwall.desktop"
install -m 644 x11-session/cardwall.desktop "$SESSION_DIR/cardwall.desktop"

# 2c. GNOME session file (used by gnome-session for compositor lookup)
GNOME_SESSION_DIR="/usr/share/gnome-session/sessions"
if [[ -d "$GNOME_SESSION_DIR" ]]; then
  info "Installing GNOME session file to $GNOME_SESSION_DIR/cardwall.session"
  install -m 644 x11-session/cardwall.session "$GNOME_SESSION_DIR/cardwall.session"
fi

info "Installation complete."
info ""
info "Next steps:"
info "  1. Log out."
info "  2. Log in — Cardwall will launch Anki and wait for zero due cards."
info ""
info "To uninstall run:  sudo bash uninstall.sh"


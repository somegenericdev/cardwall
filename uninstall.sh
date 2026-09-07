#!/usr/bin/env bash
# uninstall.sh — remove Cardwall
set -euo pipefail

info()  { echo "  [INFO]  $*"; }
error() { echo "  [ERR]   $*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || error "The full uninstallation must be run as root (sudo bash uninstall.sh)"

# Resolve the desktop user's home instead of using root's $HOME when invoked via sudo.
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

# Add-on (user-level)
for dir in \
  "${REAL_HOME}/.local/share/Anki2/addons21/cardwall" \
  "${REAL_HOME}/.var/app/net.ankiweb.Anki/data/Anki2/addons21/cardwall"; do
  if [[ -d "$dir" ]]; then
    info "Removing add-on: $dir"
    rm -rf "$dir"
  fi
done

for f in \
  /usr/local/bin/cardwall-session \
  /usr/share/xsessions/cardwall.desktop \
  /usr/share/gnome-session/sessions/cardwall.session; do
  if [[ -f "$f" ]]; then
    info "Removing $f"
    rm -f "$f"
  fi
done

# Restore X11 sessions disabled by the installer.
DISABLED_SESSIONS_FILE="/var/lib/cardwall/disabled-xsessions.list"
if [[ -f "$DISABLED_SESSIONS_FILE" ]]; then
  while IFS= read -r session_file; do
    [[ -n "$session_file" ]] || continue
    disabled_file="${session_file}.disabled"
    if [[ -e "$disabled_file" && ! -e "$session_file" ]]; then
      info "Restoring $session_file"
      mv "$disabled_file" "$session_file"
    elif [[ -e "$disabled_file" ]]; then
      info "Leaving $disabled_file in place because $session_file already exists"
    fi
  done < "$DISABLED_SESSIONS_FILE"
  rm -f "$DISABLED_SESSIONS_FILE"
  rmdir /var/lib/cardwall 2>/dev/null || true
fi

info "Cardwall removed."

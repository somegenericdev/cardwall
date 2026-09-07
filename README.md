# Cardwall

A Linux session-level gate that prevents your GNOME desktop from starting
until you have finished all of today's Anki cards.

---

## How it works

```
GDM login screen
       │  (you authenticate normally)
       ▼
cardwall-session          ← this process IS the session
       │
       ├─ due cards? ──NO──► exec gnome-session   (instant passthrough)
       │
      YES
       │
       ▼
  Anki launched
       │
       │  Unix socket  (/run/user/<uid>/cardwall.sock)
       ▼
  Anki add-on (Cardwall)
       │  answers: {"due": N}
       ▼
  poll every 5 s
       │
       │  due == 0
       ▼
  exec gnome-session       ← replaces this process; GNOME starts
```

The key security property: **GNOME never starts until due == 0**.
There is no fullscreen window to kill, no Alt+F4 escape hatch.
The desktop environment simply does not exist yet.

---

## Repository layout

```
.
├── anki-addon/
│   ├── __init__.py      # Anki add-on — Unix socket server
│   └── manifest.json
├── x11-session/
│   ├── cardwall-session # Session binary (Python 3, shebang executable)
│   ├── cardwall.desktop # GDM / xsessions entry
│   └── cardwall.session # gnome-session session file
├── install.sh
├── uninstall.sh
└── README.md
```

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| OS | Linux with GDM and **X11** — Wayland is not supported |
| Anki | 2.1.x (packaged or Flatpak) |
| Python | 3.10+ |
| Desktop | GNOME (configurable via `CARDWALL_DOWNSTREAM`) |
| `xdotool` | Required to pin the Anki window to half the screen (see `CARDWALL_WINDOW_HALF`) |
| `nano` | Required for the pre-desktop editor pane |
| `xterm` | Required to run the editor pane before the desktop starts |
| `python-xlib` | Required for click-to-focus and for keeping Anki hidden while the due count is checked (`python3-xlib`) |

---

## Before you install — X11 vs Wayland

Cardwall registers itself as an **X11 session** (via `/usr/share/xsessions/`).
Modern GDM defaults to Wayland, which means the Cardwall entry will be
**invisible in the session picker** unless you explicitly enable X11 in GDM.

### How to enable X11 in GDM

Edit the GDM configuration file:

| Distro | File |
|--------|------|
| Ubuntu / Debian | `/etc/gdm3/custom.conf` |
| Fedora / Arch / RHEL | `/etc/gdm/custom.conf` |

Add or uncomment this line under the `[daemon]` section:

```ini
[daemon]
WaylandEnable=false
```

Then reboot. GDM will now offer X11 sessions and the **Cardwall** entry
will appear in the gear-icon session picker.

> **Note:** `install.sh` checks for this and prints a warning if your GDM
> config does not have `WaylandEnable=false`.

---

## Installation

Run the installer with `sudo` from the regular desktop user's account:

```bash
sudo bash install.sh
```

The installer requires root and always performs the complete installation;
there is no add-on-only mode. It uses the user who invoked `sudo` to locate
the Anki add-on directory, then copies:
- `x11-session/cardwall-session` → `/usr/local/bin/cardwall-session`
- `x11-session/cardwall.desktop` → `/usr/share/xsessions/cardwall.desktop`
- `x11-session/cardwall.session` → `/usr/share/gnome-session/sessions/cardwall.session`

It also disables the other X11 session entries in `/usr/share/xsessions` by
renaming them to `.desktop.disabled`, leaving Cardwall as the only selectable
X11 session. Uninstallation restores the entries disabled by the installer.

Restart Anki after installation so the add-on auto-starts and binds to
`/run/user/<uid>/cardwall.sock`.

### Log in

1. Log out.
2. Log in with your password — Cardwall is now the only available session.

---

## Configuration

All configuration is done via environment variables set in your session
environment (e.g. `~/.pam_environment`, `~/.config/environment.d/*.conf`).

| Variable | Default | Description |
|---|---|---|
| `CARDWALL_SOCKET_PATH` | `/run/user/<uid>/cardwall.sock` | Path to the Unix socket |
| `CARDWALL_DOWNSTREAM` | `gnome-session` | Command to exec into when done |
| `CARDWALL_ANKI_CMD` | `anki` | Command used to launch Anki |
| `CARDWALL_POLL_INTERVAL` | `5` | Seconds between due-count polls |
| `CARDWALL_CONNECT_RETRIES` | `60` | Max socket connect attempts (×interval = timeout) |
| `CARDWALL_WINDOW_HALF` | `1` | Pin the Anki window (and the editor, see below) to half the screen at full height (no WM is running yet); set to `0` to disable |
| `CARDWALL_FOCUS_MODE` | `click` | How the pre-desktop Anki/editor windows get keyboard focus (no WM is running yet): `click` (click-to-focus), `pointer` (focus follows mouse), or `off` |
| `CARDWALL_EDITOR_FONT_SIZE` | `18` | Point size used for the xterm that runs `nano` |
| `CARDWALL_EDITOR_FONT_FAMILY` | `Monospace` | Font family used for the xterm that runs `nano` |
| `CARDWALL_POINTER_FOCUS_INTERVAL` | `0.2` | Seconds between focus polls |
| `CARDWALL_DARK_MODE` | `1` | Force Anki into dark/night mode on profile load; set to `0` to leave the user's theme preference alone |

### Using KDE instead of GNOME

```ini
# ~/.config/environment.d/cardwall.conf
CARDWALL_DOWNSTREAM=startplasma-x11
```

### Using Flatpak Anki

```ini
CARDWALL_ANKI_CMD=flatpak run net.ankiweb.Anki
```

---

## IPC protocol

The add-on exposes a simple line-delimited JSON protocol over the Unix socket.

**Request**
```json
{"cmd": "due_count"}
```

**Response (success)**
```json
{"due": 37}
```

**Response (error)**
```json
{"error": "collection not loaded"}
```

One request per connection; the server closes the connection after each reply.

---

## Uninstallation

Run the uninstaller with `sudo` from the same desktop user's account. It
requires root and removes both the user's add-on and the system files:

```bash
sudo bash uninstall.sh
```

---

## Failsafe

If the add-on socket cannot be reached after `CARDWALL_CONNECT_RETRIES`
attempts, **Cardwall deliberately starts the desktop anyway** rather than
locking you out of your own machine permanently. A warning is logged to
the session journal (`journalctl --user`).

---

## Security considerations

- The socket is created with mode `0600` — only the owning user can connect.
- The session binary runs as the normal user, not root.
- `exec` is used (not `fork+exec`) so no Cardwall process remains alive
  after GNOME starts.

---

## License

MIT

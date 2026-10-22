#!/bin/bash
# Keep the staff web page (pixi run gui) running as a systemd user service, so
# it survives logout, closed terminals and reboots. Run from the control clone:
#   scripts/install_gui_service.sh              # install and start
#   scripts/install_gui_service.sh --uninstall  # stop and remove
#
# The service runs as you (your crontab, ~/.env, hpc3 key), the same as
# `pixi run gui`. Linger lets your user services run while you are logged out.
# Print the login link with `pixi run gui-link`.

set -euo pipefail

unit_dir="$HOME/.config/systemd/user"
unit="$unit_dir/bclgui.service"
control_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pixi="$(command -v pixi || echo "$HOME/.pixi/bin/pixi")"

if [[ "${1:-}" == "--uninstall" ]]; then
    systemctl --user disable --now bclgui 2>/dev/null || true
    rm -f "$unit"
    systemctl --user daemon-reload
    echo "Removed bclgui.service. (Linger left on; turn off with: loginctl disable-linger $USER)"
    exit 0
fi

[[ -x "$pixi" ]] || { echo "pixi not found; install it first (docs/GUI.md)" >&2; exit 1; }

mkdir -p "$unit_dir"
cat > "$unit" <<UNIT
[Unit]
Description=Sequencing run web page (bcl_conversion GUI)

[Service]
WorkingDirectory=$control_dir
ExecStart=$pixi run gui
Restart=on-failure
RestartSec=10
UMask=0007

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now bclgui
loginctl enable-linger "$USER"
sleep 2
systemctl --user --no-pager status bclgui | head -5
echo
echo "Installed. Login link:"
cd "$control_dir" && "$pixi" run gui-link

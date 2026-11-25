#!/bin/bash
# AI GENERATED - Tom Barone
# Usage: gnome-remote-desktop-sharing <port> <enable|disable>-view-only
#
# Shares the calling user's GNOME desktop over RDP. Clients sign in with
# the username and password on the two lines of
# ~/.config/gnome-remote-desktop-sharing.
#
# GNOME keeps those in the login keyring, which only the user's own
# session can open, so this runs each time the daemon starts.
set -euo pipefail

{
  IFS= read -r username
  IFS= read -r password
} <"${XDG_CONFIG_HOME:-${HOME}/.config}/gnome-remote-desktop-sharing"

# Where GNOME Settings keeps the certificate it generates, so one that
# is already there is kept
tls="${XDG_DATA_HOME:-${HOME}/.local/share}/gnome-remote-desktop/certificates/rdp-tls"
# openssl writes the certificate after the key
if [ ! -f "${tls}.crt" ]; then
  mkdir -p "${tls%/*}"
  openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/O=GNOME/CN=$(hostname)" \
    -out "${tls}.crt" -keyout "${tls}.key"
fi

grdctl rdp set-tls-cert "${tls}.crt"
grdctl rdp set-tls-key "${tls}.key"
grdctl rdp set-port "$1"
# Listen on that port or not at all, instead of on the next free one
grdctl rdp disable-port-negotiation
grdctl rdp "$2"
# On stdin, to keep the password out of the process list
grdctl rdp set-credentials "${username}" <<<"${password}"
# Last, so sharing is never on without credentials
grdctl rdp enable

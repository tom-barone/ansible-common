#!/bin/bash
# AI GENERATED - Tom Barone
# Usage: gnome-desktop-icons <name>...
#
# Copies /usr/share/applications/<name>.desktop onto the desktop and
# marks it trusted, so Desktop Icons NG starts it on double click.
set -euo pipefail

desktop="$(xdg-user-dir DESKTOP)"
# xdg-user-dirs points the desktop at the home directory once the
# Desktop folder has been deleted
[ "${desktop%/}" != "${HOME%/}" ] || exit 0
mkdir -p "${desktop}"

for name in "$@"; do
  launcher="${desktop}/${name}.desktop"
  cp "/usr/share/applications/${name}.desktop" "${launcher}" || continue
  gio set "${launcher}" metadata::trusted true
  # Last, so Desktop Icons NG gets a file event after the trust flag is set
  chmod +x "${launcher}"
done

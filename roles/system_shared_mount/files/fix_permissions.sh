#!/bin/bash
# AI GENERATED - Tom Barone
# Usage: fix_permissions.sh <path>
#
# Gives everything under path to the users group and makes it group
# writable, then prints how many paths it changed. -xdev keeps it on
# this filesystem, e.g. out of a drive mounted inside it.
set -euo pipefail

{
  find "$1" -xdev ! -group users -print \
    -exec chgrp --no-dereference users {} +
  # A directory without setgid predates the share or was copied in with
  # its mode kept, so it is missing the default ACL too
  find "$1" -xdev -type d ! -perm -2070 -print \
    -exec chmod g+rwxs {} + \
    -exec setfacl --default --modify g::rwx {} +
  find "$1" -xdev -type f ! -perm -0060 -print \
    -exec chmod g+rw {} +
} | wc -l

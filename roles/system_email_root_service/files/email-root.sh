#!/bin/bash
set -euo pipefail

# Email root a summary of a failed systemd unit. Intended to be run via
# the email-root@.service unit: OnFailure=email-root@%n.service
unit="$1"

/usr/sbin/sendmail -t <<EOF
To: root
Subject: [$(hostname)] ${unit} failed

$(systemctl status --full --no-pager --lines 100 "${unit}" || true)
EOF

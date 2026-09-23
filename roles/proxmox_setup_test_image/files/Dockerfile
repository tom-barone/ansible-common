# proxmox-auto-install-assistant is only packaged for Debian, so run it in
# a container. The Proxmox repository ships it for amd64 and arm64.
FROM debian:trixie-slim

ADD --chmod=644 \
    --checksum=sha256:136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45 \
    https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    /usr/share/keyrings/proxmox-archive-keyring.gpg

RUN echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
    > /etc/apt/sources.list.d/pve.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends proxmox-auto-install-assistant=9.2.8 xorriso=1.5.6-1.2+b1 \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["proxmox-auto-install-assistant"]

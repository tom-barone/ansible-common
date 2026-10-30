# ansible-common

Reusable ansible roles that can be used across projects via a git submodule.

Targeted at stock Debian on your own hardware or VPS providers like Hetzner / Linode.

A non-comprehensive list of the more interesting roles:

| Role | Description |
| --- | --- |
| `dokku_install` | Install [Dokku](https://dokku.com/) PaaS platform with admin SSH key and global domain configuration. |
| `github_actions_self_hosted_runner_install` | Deploy a GitHub Actions self-hosted runner with local cache server. |
| `gnome_power_management` | Configure GNOME automatic suspend for user sessions and the GDM login screen, masking the systemd sleep targets when it is disabled. |
| `immich_install` | Install the [Immich](https://immich.app/) photo and video manager via Docker. |
| `immich_restic_backup` | Automated Immich backups (database dump and original media) to an S3 compatible backend with [Restic](https://restic.net/), including scheduled `restic check` verification and bootstrap restore. |
| `llama_cpp_server` | Serve Hugging Face GGUF models with the [llama.cpp](https://github.com/ggml-org/llama.cpp) server in router mode, loading them on demand, as a systemd service on CUDA or CPU. |
| `monitoring_stack_install` | Install [Prometheus](https://prometheus.io/), [Loki](https://grafana.com/oss/loki/), [Grafana](https://grafana.com/), [Alloy](https://grafana.com/docs/alloy/latest/), [Node Exporter](https://github.com/prometheus/node_exporter), and [cAdvisor](https://github.com/google/cadvisor) via Docker with emailed alerts for disk and RAM usage. |
| `network_manager_switch` | Turn NetworkManager's WiFi and WWAN radio switches on or off. |
| `nvidia_drivers_install` | Install the NVIDIA compute driver (CUDA) with open kernel modules from NVIDIA's Debian repository, built by DKMS. |
| `openclaw_install` | Install the [OpenClaw](https://github.com/openclaw/openclaw) AI gateway as a hardened, non-root systemd service with scoped sudo. |
| `postfix_relay` | Configure Postfix as a mail relay with SASL authentication and SMTP settings. |
| `postgres_install_docker` | Deploy PostgreSQL via Docker. |
| `postgres_pgbackrest_install` | Deploy PostgreSQL via Docker with [pgBackRest](https://pgbackrest.org/) WAL archiving, scheduled full/differential backups and weekly repository verification against one or more configurable repositories (S3 compatible etc.), including bootstrap restore. |
| `postgres_pgbackrest_restore_verify` | Scheduled [pgBackRest](https://pgbackrest.org/) restore test into a throwaway PostgreSQL container with verification queries. |
| `postgres_restic_backup` | Automated PostgreSQL backups to any [Restic](https://restic.net/) supported backend, including scheduled `restic check` verification. |
| `qemu_vm_create` | Create and launch a QEMU virtual machine with cloud-init and COW disk overlay. |
| `samba_share` | Share a directory over SMB with read-write and read-only Samba credentials, advertised to macOS (mDNS) and Windows (WS-Discovery) clients. |
| `system_fail2ban` | Install and configure Fail2ban with jail rules for SSH brute-force protection. |
| `system_harden_ssh` | Harden SSH setting up authorized keys, and configuring sshd security parameters. |
| `system_logcheck` | Install [logcheck](https://packages.debian.org/logcheck) with ignore rules for common services. |
| `system_segmentation_offload` | Disable TSO/GSO segmentation offloads on selected NICs via a device-bound systemd unit, working around NIC bugs like the e1000e "Detected Hardware Unit Hang". |
| `system_shared_mount` | Let every login user and Samba user read and write a mounted disk through the `users` group, with setgid directories and a default ACL that overrides the umask. |
| `system_smartmontools` | Install and configure [smartmontools](https://www.smartmontools.org/) to monitor disk health with emailed SMART alerts via the local MTA. |
| `tailscale_install` | Connect to a [Tailscale](https://tailscale.com/) tailnet. |
| `tailscale_subnet_router` | Configure Tailscale subnet routing with auto-discovery of local subnets. |
| `traefik_install` | Install [Traefik](https://traefik.io/) reverse proxy with TLS passthrough and LetsEncrypt TLS terminated routes. |
| `xrdp_install` | Install [xrdp](https://www.xrdp.org/) for RDP access to the desktop, replacing GNOME's remote desktop on port 3389. |
| `zfs_pool` | Import a ZFS pool, or create it on blank disks, building the ZFS module with DKMS. |

## Development

See the `Justfile` for development tasks.

## Testing

Every role has a corresponding [molecule](https://docs.ansible.com/projects/molecule/) test and are required to pass idempotence checks.

Use this task in a playbook to pause execution and allow for manual verification of the container state during testing:

```yaml
- name: Infinite sleep to allow manual verification
  # When this runs, you can do `docker exec -it <container_name> bash`
  # to get a shell in the container at this point and verify the
  # state of the system manually.
  ansible.builtin.command: sleep infinity
  async: 0
  poll: 0
```

# ansible-common

Reusable ansible roles that can be used across projects via a git submodule.

Targeted at stock Debian on your own hardware or VPS providers like Hetzner / Linode.

A non-comprehensive list of the more interesting roles:

| Role | Description |
| --- | --- |
| `dokku_install` | Install [Dokku](https://dokku.com/) PaaS platform with admin SSH key and global domain configuration. |
| `github_actions_self_hosted_runner_install` | Deploy a GitHub Actions self-hosted runner with local cache server. |
| `monitoring_stack_install` | Install [Prometheus](https://prometheus.io/), [Loki](https://grafana.com/oss/loki/), [Grafana](https://grafana.com/), [Alloy](https://grafana.com/docs/alloy/latest/), [Node Exporter](https://github.com/prometheus/node_exporter), and [cAdvisor](https://github.com/google/cadvisor) via Docker with emailed alerts for disk and RAM usage. |
| `postfix_relay` | Configure Postfix as a mail relay with SASL authentication and SMTP settings. |
| `postgres_install_docker` | Deploy PostgreSQL via Docker. |
| `postgres_restic_backup` | Automated PostgreSQL backups to a S3 compatible backend with [Restic](https://restic.net/). |
| `qemu_vm_create` | Create and launch a QEMU virtual machine with cloud-init and COW disk overlay. |
| `system_fail2ban` | Install and configure Fail2ban with jail rules for SSH brute-force protection. |
| `system_harden_ssh` | Harden SSH setting up authorized keys, and configuring sshd security parameters. |
| `system_logcheck` | Install [logcheck](https://packages.debian.org/logcheck) with ignore rules for common services. |
| `tailscale_install` | Connect to a [Tailscale](https://tailscale.com/) tailnet. |
| `tailscale_subnet_router` | Configure Tailscale subnet routing with auto-discovery of local subnets. |
| `traefik_install` | Install [Traefik](https://traefik.io/) reverse proxy with docker tagging and LetsEncrypt support. |

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

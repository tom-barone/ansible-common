# Show help by default when running `just` with no arguments [private]
@default: help

# Install dependencies
@install:
    uv sync --quiet
    npm install --silent

# Show this help message
@help:
    just --list

# Run linters
@lint:
    uv run ansible-lint tests \
      ./roles/docker_install \
      ./roles/dokku_install \
      ./roles/system_fail2ban \
      ./roles/system_harden_ssh \
      ./roles/system_locale \
      ./roles/system_logcheck \
      ./roles/system_logrotate \
      ./roles/user_add_to_groups \
      ./roles/user_create_admin
    # https://github.com/ansible/ansible-lint/issues/4533
    rm -rf .ansible
    uv run yamllint --strict tests \
      ./roles/docker_install \
      ./roles/dokku_install \
      ./roles/system_fail2ban \
      ./roles/system_harden_ssh \
      ./roles/system_locale \
      ./roles/system_logcheck \
      ./roles/system_logrotate \
      ./roles/user_add_to_groups \
      ./roles/user_create_admin
    docker run --rm -v $(pwd):/repo --workdir /repo rhysd/actionlint:latest -color

# Run formatters
@format:
    npx prettier --write 'roles/**/*.yml' 'tests/**/*.yml' '.github/**/*.yaml' --list-different
    just --fmt --unstable

# Run tests
@test *ARGS:
    uv run tests/run.py {{ ARGS }}
    # Test logcheck matchers
    ./roles/system_logcheck/test.sh

# Run the Ansible docker container for testing (systemd enabled)
@run-docker:
    docker run --rm --detach \
      --privileged \
      --cgroupns=host \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      --name debian12-ansible \
      geerlingguy/docker-debian12-ansible:latest
    docker exec -it debian12-ansible bash

# Run all pre-commit checks
@precommit: install format lint test

PROXMOX_ISO := "proxmox-ve_9.1-1.iso"
PROXMOX_BASE_IMAGE := "proxmox-base.qcow2"
PROXMOX_WORKING_IMAGE := "proxmox-working.qcow2"

@proxmox-create-base:
    cd .cache && qemu-img create -f qcow2 {{ PROXMOX_BASE_IMAGE }} 64G
    cd .cache && qemu-system-x86_64 \
      -machine q35 \
      -cpu qemu64 \
      -accel tcg \
      -m 8192 \
      -smp 4 \
      -drive file={{ PROXMOX_BASE_IMAGE }},if=virtio,format=qcow2 \
      -cdrom {{ PROXMOX_ISO }} \
      -boot d \
      -k en-us \
      -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8006-:8006 \
      -device virtio-net-pci,netdev=net0 \
      -display cocoa \
      -vga virtio
    # Run through the installer and let it reboot once. 
    # Then shut down the VM -> the base image is ready for cloning and testing
    #
    # On MACOS use ctrl-option-G to release mouse from QEMU window
    # Choose graphical
    # Set country/timezone as normal
    # Set password as normal
    # Set email to email+alias@domain.com (gmail aliasing)
    # Set hostname to alias.domain.com

@proxmox-run:
    # Clone the base image for testing
    cd .cache && rm -rf {{ PROXMOX_WORKING_IMAGE }}
    cd .cache && qemu-img create -f qcow2 -F qcow2 -b {{ PROXMOX_BASE_IMAGE }} {{ PROXMOX_WORKING_IMAGE }}
    # Run the cloned image
    cd .cache && qemu-system-x86_64 \
      -machine q35 \
      -cpu qemu64 \
      -accel tcg \
      -m 8192 \
      -smp 4 \
      -drive file={{ PROXMOX_WORKING_IMAGE }},if=virtio,format=qcow2 \
      -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8006-:8006 \
      -device virtio-net-pci,netdev=net0 \
      -display cocoa \
      -vga virtio
    # SSH should be accessible on 127.0.0.1:2222
    # Proxmox web UI should be accessible on 127.0.0.1:8006

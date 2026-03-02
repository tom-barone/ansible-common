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
      ./roles/system_grub \
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
      ./roles/system_grub \
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
PROXMOX_HOST := "127.0.0.1"
PROXMOX_SSH_PORT := "2222"
PROXMOX_WEB_PORT := "8006"
PROXMOX_SSH_USER := "root"
PROXMOX_SSH_PASSWORD := "password"

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
      -netdev user,id=net0,hostfwd=tcp:{{ PROXMOX_HOST }}:{{ PROXMOX_SSH_PORT }}-:22,hostfwd=tcp:{{ PROXMOX_HOST }}:{{ PROXMOX_WEB_PORT }}-:8006 \
      -device virtio-net-pci,netdev=net0 \
      -display cocoa \
      -vga virtio
    # Run through the installer and let it reboot once. 
    # Then shut down the VM -> the base image is ready for cloning and testing
    #
    # On MACOS use ctrl-option-G to release mouse from QEMU window
    # Choose graphical
    # Set country/timezone as normal
    # Set password to {{ PROXMOX_SSH_PASSWORD }}
    # Set email to mail+proxmox-test@tombarone.net
    # Set hostname to proxmox-test.tombarone.net

@proxmox-run-from-base:
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
      -k en-us \
      -netdev user,id=net0,\
      hostfwd=tcp:{{ PROXMOX_HOST }}:{{ PROXMOX_SSH_PORT }}-:22,\
      hostfwd=tcp:{{ PROXMOX_HOST }}:{{ PROXMOX_WEB_PORT }}-:8006 \
      -device virtio-net-pci,netdev=net0 \
      -display cocoa \
      -vga virtio
    # SSH should be accessible on 127.0.0.1:2222
    # Proxmox web UI should be accessible on 127.0.0.1:8006

@proxmox-commit-to-base:
    # After making changes to the working image, commit them back to the base image
    cd .cache && qemu-img commit {{ PROXMOX_WORKING_IMAGE }}

@proxmox-configure-base:
    ANSIBLE_HOST_KEY_CHECKING=False \
      uv run ansible-playbook \
      -i "{{ PROXMOX_HOST }}:{{ PROXMOX_SSH_PORT }}," \
      -e "ansible_user={{ PROXMOX_SSH_USER }} \
      ansible_ssh_pass={{ PROXMOX_SSH_PASSWORD }} \
      ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' \
      ansible_python_interpreter=/usr/bin/python3" \
      ./tests/proxmox_configure_base.yml
    # Shutdown the VM and then commit changes to the base image

# Show help by default when running `just` with no arguments
[private]
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

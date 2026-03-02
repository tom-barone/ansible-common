# Show help by default when running `just` with no arguments
@default:
    just --list

[doc("Install dependencies")]
@install:
    uv sync --quiet
    uv run ansible-galaxy install -r requirements.yml
    npm install --silent

[doc("Run linters")]
@lint:
    uv run ansible-lint tests \
      ./roles/docker_install \
      ./roles/dokku_install \
      ./roles/postfix_config \
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
      ./roles/postfix_config \
      ./roles/system_fail2ban \
      ./roles/system_grub \
      ./roles/system_harden_ssh \
      ./roles/system_locale \
      ./roles/system_logcheck \
      ./roles/system_logrotate \
      ./roles/user_add_to_groups \
      ./roles/user_create_admin
    docker run --rm -v $(pwd):/repo --workdir /repo rhysd/actionlint:latest -color

[doc("Run formatters")]
@format:
    npx prettier --write 'roles/**/*.yml' 'tests/**/*.yml' '.github/**/*.yaml' --list-different
    just --fmt --unstable

[doc("Run tests")]
@test *ARGS:
    sops exec-env secrets.sops.env \
      'uv run tests/run.py {{ ARGS }}'
    # Test logcheck matchers
    ./roles/system_logcheck/test.sh

[doc("Edit secrets with sops")]
@secrets-edit:
    sops secrets.sops.env

[doc("Run a Debian 12 Ansible container for testing")]
@run-docker:
    docker run --rm --detach \
      --privileged \
      --cgroupns=host \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      --name debian12-ansible \
      geerlingguy/docker-debian12-ansible:latest
    docker exec -it debian12-ansible bash

[doc("Run all precommit checks")]
@precommit: install format lint test

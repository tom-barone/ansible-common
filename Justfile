[doc("Install dependencies")]
install:
    uv sync --quiet
    # Galaxy resets connections now and then, so retry a few times
    for i in 1 2 3; do uv run ansible-galaxy install -r requirements.yml && break; [ "$i" = 3 ] && exit 1; sleep 15; done
    npm install --silent

[doc("Run linters")]
lint:
    uv run ansible-lint tests roles
    # https://github.com/ansible/ansible-lint/issues/4533
    rm -rf .ansible
    uv run yamllint --strict tests roles
    actionlint -color
    git ls-files -z '*.sh' | xargs -0 shellcheck --severity=style
    # Test logcheck matchers
    ./roles/system_logcheck/test.sh

[doc("Run formatters")]
format:
    npx prettier --write 'roles/**/*.yml' 'tests/**/*.yml' '.github/**/*.yaml' --list-different
    just --fmt --unstable

[doc("Run tests")]
test *ARGS:
    #!/usr/bin/env bash
    {{ secrets }}
    uv run tests/run.py {{ ARGS }}

secrets := '''
set -euo pipefail
set -o allexport && eval "$(sops --decrypt secrets.sops.env)" && set +o allexport
'''

[doc("Edit secrets with sops")]
secrets-edit:
    sops secrets.sops.env

[doc("Run all precommit checks")]
precommit: install format lint

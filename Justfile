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
    uv run ansible-lint tests roles
    # https://github.com/ansible/ansible-lint/issues/4533
    rm -rf .ansible
    uv run yamllint --strict tests roles
    docker run --rm -v $(pwd):/repo --workdir /repo rhysd/actionlint:latest -color
    # Test logcheck matchers
    ./roles/system_logcheck/test.sh

[doc("Run formatters")]
@format:
    npx prettier --write 'roles/**/*.yml' 'tests/**/*.yml' '.github/**/*.yaml' --list-different
    just --fmt --unstable

[doc("Run tests")]
@test *ARGS:
    sops exec-env secrets.sops.env \
      'uv run tests/run.py {{ ARGS }}'

[doc("Edit secrets with sops")]
@secrets-edit:
    sops secrets.sops.env

[doc("Run all precommit checks")]
@precommit: install format lint

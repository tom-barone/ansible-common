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
      ./roles/user_add_to_groups \
      ./roles/user_create_admin
    # https://github.com/ansible/ansible-lint/issues/4533
    rm -rf .ansible
    uv run yamllint --strict tests \
      roles/user_add_to_groups \
      roles/user_create_admin

# Run formatters
@format:
    npx prettier --write 'roles/**/*.yaml' 'tests/**/*.yaml' --list-different
    just --fmt --unstable

# Run tests
@test *ARGS:
    uv run tests/run.py {{ ARGS }}

# Run all pre-commit checks
@precommit: install format lint test

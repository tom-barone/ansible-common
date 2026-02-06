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
    @echo "Skipping linters for now"
    #uv run ansible-lint
    ## https://github.com/ansible/ansible-lint/issues/4533
    #rm -rf .ansible
    #uv run yamllint .

# Run formatters
@format:
    npx prettier --write 'roles/**/*.yaml' --list-different
    just --fmt --unstable

# Run tests
@test:
    uv run tests/run.py

# Run all pre-commit checks
@precommit: install format lint test

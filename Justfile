# Show help by default when running `just` with no arguments
[private]
default: help

# Install dependencies
install:
    uv sync

# Show this help message
help:
    @just --list

# Run linters
lint:
    uv run ansible-lint
    @# https://github.com/ansible/ansible-lint/issues/4533
    rm -rf .ansible

# Run formatters
format:
    npx prettier --write '**/*.yaml'
    just --fmt --unstable

# Run all pre-commit checks
precommit: install format lint

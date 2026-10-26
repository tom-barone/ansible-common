ARG POSTGRES_VERSION
FROM postgres:${POSTGRES_VERSION}
# pgbackrest is updated often and we usually want the latest version, so it's not pinned here
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest \
    && rm -rf /var/lib/apt/lists/*

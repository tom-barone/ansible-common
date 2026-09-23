ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG PGBACKREST_VERSION
RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest=${PGBACKREST_VERSION} \
    && rm -rf /var/lib/apt/lists/*

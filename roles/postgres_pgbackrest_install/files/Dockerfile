ARG POSTGRES_VERSION
FROM postgres:${POSTGRES_VERSION}
RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest=2.59.0-1.pgdg13+1 \
    && rm -rf /var/lib/apt/lists/*

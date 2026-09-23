# Migrating a live Immich server to postgres_pgbackrest_install

This runbook moves one Immich host, in place and without losing data, from
the Postgres that `immich_install` used to run inside Immich's compose
stack to the `postgres` container managed by `postgres_pgbackrest_install`.
The database goes from Postgres 14 with VectorChord 0.4.3 to Postgres 18
with VectorChord 1.1.1, and its backups go from a nightly `pg_dumpall`
inside the restic snapshot to pgBackRest WAL archiving with scheduled
backups and a weekly test restore.

All commands run as root on the Immich host unless stated otherwise.
Ansible runs from the control machine. Do not upgrade Immich in the same
window: `immich_install_version` must be identical before and after.

## 1. What changes

| | Before | After |
| --- | --- | --- |
| Database container | `immich_postgres`, from `/opt/immich/docker-compose.yml`, image `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` | `postgres`, from `/opt/postgres/docker-compose.yml`, local image `postgres-pgbackrest:18.3` built on `ghcr.io/immich-app/postgres:18-vectorchord1.1.1-pgvector0.8.5` |
| Data directory | `/opt/immich/postgres` | `/opt/postgres/data` |
| Immich connection | `DB_HOSTNAME=database` | `DB_HOSTNAME=postgres`, `DB_PORT=5432`, same user, password and database name |
| Host port | none | `127.0.0.1:5432` (pgbouncer disabled) |
| Database backups | `pg_dumpall` into the restic snapshot, daily 03:00 UTC | pgBackRest: WAL archiving, full Sun 03:00 UTC, diff Mon..Sat 03:00 UTC, `pgbackrest verify` Sun 05:00 UTC, test restore Sun 06:00 UTC |
| Media backups | restic, `immich-restic-backup.timer` | unchanged, media directories only |
| Bootstrap restore | restic restore when the `"user"` table is empty | pgBackRest restore when the data directory is empty and the stanza has a backup; restic restore when the media directories hold nothing but `.immich` markers |
| Immich built-in DB backups | on by default | off |

Inventory for the host. The Postgres superuser password must stay the
same value as `immich_install_db_password`, because `pg_dump` carries no
roles and the new cluster gets its password from `POSTGRES_PASSWORD` at
initdb.

```yaml
immich_install_network: "immich_network"
postgres_pgbackrest_install_network: "{{ immich_install_network }}"
postgres_pgbackrest_install_password: "{{ immich_install_db_password }}"
postgres_pgbackrest_install_base_image: >-
  ghcr.io/immich-app/postgres:18-vectorchord1.1.1-pgvector0.8.5
# bookworm pin: Immich's image is built on pgvector's bookworm base
postgres_pgbackrest_install_pgbackrest_version: "2.59.0-1.pgdg12+1"
# Loads the image's tuned postgresql.conf, which preloads vchord.so
postgres_pgbackrest_install_settings:
  config_file: "/etc/postgresql/postgresql.conf"
postgres_pgbackrest_install_database: "immich"
postgres_pgbackrest_install_pgbouncer_enabled: false
postgres_pgbackrest_install_repos:
  - type: "s3"
    path: "/pgbackrest"
    s3-endpoint: "..."
    s3-bucket: "..."
    s3-region: "..."
    s3-key: "..."
    s3-key-secret: "..."
    cipher-type: "aes-256-cbc"
    cipher-pass: "..."
    retention-full: 4
postgres_pgbackrest_restore_verify_postgres_database: "immich"
postgres_pgbackrest_restore_verify_queries:
  - 'SELECT count(*) FROM "user"'
```

The playbook order from now on:

```yaml
roles:
  - docker_network_create
  - postgres_pgbackrest_install
  - immich_install
  - immich_restic_backup
  - postgres_pgbackrest_restore_verify
```

## 2. Pre-flight (days before)

Record every result. The same commands serve as checkpoints later.

Immich version and health. Expect `pong`, the version from the inventory
and four healthy containers.

```bash
curl -s http://localhost:2283/api/server/ping; echo
curl -s http://localhost:2283/api/server/version; echo
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
```

Extensions on the old database. Expect `cube`, `earthdistance`,
`plpgsql`, `vchord`, `vector` and possibly `uuid-ossp` and `unaccent`. The
second query must return no rows.

```bash
docker exec immich_postgres psql -U postgres -d immich -c \
  "SELECT extname, extversion FROM pg_extension ORDER BY 1;"
docker exec immich_postgres psql -U postgres -d immich -c \
  "SELECT table_name, column_name FROM information_schema.columns WHERE udt_schema = 'vectors';"
```

If `vectors` (pgvecto.rs) is listed and the second query is empty, the
instance was migrated from pgvecto.rs and the leftover extension is
unused. Leave it; the dump is filtered in step 4.5. If the second query
returns rows, stop: columns still use pgvecto.rs types and the new image
cannot host them.

Size and space. Free space on `/opt` should be at least three times the
database size: the new cluster, the compressed dump, and the weekly test
restore, which restores a full copy under
`/opt/pgbackrest-restore-verify/` while it runs. The old directory stays
until cleanup. The row counts of `smart_search` and `face_search` set how
long the vector index rebuild takes during the restore.

```bash
docker exec immich_postgres psql -U postgres -d immich -tAc \
  "SELECT pg_size_pretty(pg_database_size('immich'));"
docker exec immich_postgres psql -U postgres -d immich -c \
  "SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY 2 DESC LIMIT 10;"
du -sh /opt/immich/postgres
df -h /opt
stat -f -c %T /opt
```

The filesystem type must be a local one (ext4, xfs, btrfs, zfs). Immich's
postgres image refuses to start on network shares.

Port 5432 must be free on the host, because with pgbouncer disabled the
new container publishes `127.0.0.1:5432`.

```bash
ss -ltnp | grep -w 5432 || echo "5432 free"
```

The pgBackRest bucket exists, the credentials can list it, and the
`path` is empty. A backup already present there would make Stage 3
restore it instead of running initdb.

The restic repo is healthy. Expect recent snapshots that include
`/opt/immich-backup/db` and the three media directories, and exit 0.

```bash
cd /opt/immich-backup && source ./env
restic snapshots --latest 3
./verify.sh; echo "verify exit: $?"
```

The `.immich` markers exist. Immich writes them on startup and the new
restic bootstrap guard relies on them.

```bash
ls -la /opt/immich/data/library/.immich /opt/immich/data/upload/.immich /opt/immich/data/profile/.immich
```

Save the current compose file. This is the fastest rollback after the
switch.

```bash
mkdir -p -m 700 /opt/immich-migration
cp -a /opt/immich/docker-compose.yml /opt/immich-migration/docker-compose.yml.pre-migration
```

Pick a window outside 03:00 to 06:30 UTC, when the timers fire. Budget
one to two hours for a database of a few GB. The restore (COPY plus the
vector index rebuild) and the first full backup upload dominate.

## 3. Stage A: new Postgres next to the old stack (no downtime)

Run only `docker_network_create` and `postgres_pgbackrest_install`, with
the inventory above. Do not run the full playbook yet (see section 8).
Use a temporary playbook with just those two roles if the real one is
not tagged.

What the role does on this host:

1. Builds `postgres-pgbackrest:18.3` from Immich's image plus the pinned
   pgbackrest package.
2. Writes `/opt/postgres/pgbackrest.conf` and creates `/opt/postgres/data`.
3. Finds no `PG_VERSION` and no backup in the stanza, so it does not
   restore anything.
4. Starts the container; initdb creates an empty `immich` database.
5. Runs `stanza-create` and `pgbackrest check`, which confirms WAL can
   be pushed to the repo.
6. Installs the backup scripts and the three timers.

The old stack is untouched. `postgres` is now resolvable on
`immich_network`, but Immich still talks to `database`.

Checkpoints. Expect `18`, `vchord.so`, `on`, `0`, matching encoding and
collation on both clusters, `accepting connections`, and Immich still
answering `pong`.

```bash
cat /opt/postgres/data/18/docker/PG_VERSION
docker exec postgres psql -U postgres -tAc "SHOW shared_preload_libraries;"
docker exec postgres psql -U postgres -tAc "SHOW archive_mode;"
docker exec postgres psql -U postgres -d immich -tAc \
  "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"
for c in postgres immich_postgres; do
  docker exec "$c" psql -U postgres -tAc \
    "SELECT pg_encoding_to_char(encoding) || ' ' || datcollate FROM pg_database WHERE datname = 'immich';"
done
docker exec -u postgres postgres pgbackrest --stanza=main check
docker run --rm --network immich_network postgres-pgbackrest:18.3 \
  pg_isready -h postgres -p 5432 -U postgres
curl -s http://localhost:2283/api/server/ping; echo
```

Park the pgBackRest timers until Stage C. A scheduled diff with no prior
full backup takes a full backup of the empty database, which would then
be what the test restore checks. The role's "Enable and start backup
timers" task re-enables them on the next playbook run.

```bash
systemctl disable --now postgres-pgbackrest-backup-full.timer \
  postgres-pgbackrest-backup-diff.timer postgres-pgbackrest-verify.timer
```

## 4. Stage B: move the database (maintenance window)

Keep one root shell for the whole window.

```bash
set -o pipefail
MIG=/opt/immich-migration
DUMP="$MIG/immich-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
```

### 4.1 Stop Immich

Downtime starts here. Stopping before the final backup makes the last
restic snapshot and the dump the same quiescent state.

```bash
docker stop immich_server immich_machine_learning
```

### 4.2 Final old-style backup

Expect exit 0 and a new snapshot whose paths include
`/opt/immich-backup/db`. Record its ID as the rollback point.

```bash
/opt/immich-backup/backup.sh; echo "backup exit: $?"
source /opt/immich-backup/env && restic snapshots --latest 1
```

### 4.3 Dump the old database

`docker exec -t` is left out on purpose: a pseudo-TTY rewrites line
endings in the stream. Expect exit 0, a file that ends with `dump
complete`, and a `set_config` count of 1.

```bash
docker exec immich_postgres pg_dump --clean --if-exists --dbname=immich --username=postgres \
  | gzip > "$DUMP"; echo "dump exit: $?"
zcat "$DUMP" | tail -n 3
zcat "$DUMP" | grep -c "SELECT pg_catalog.set_config('search_path', '', false);"
zcat "$DUMP" | grep -nE '(^|[^a-z_])vectors([^a-z_]|$)'
```

The last command decides step 4.5. No output: plain restore. Only lines
that create, drop, alter or comment on the `vectors` extension or schema:
filtered restore. Anything else (a column type, an operator class, a
function): stop and roll back (section 7); the dump cannot be loaded
into the new image.

### 4.4 Confirm the target database is pristine

Expect `0`. Anything else means Immich has already run against this
database (section 8); recreate it before restoring.

```bash
docker exec postgres psql -U postgres -d immich -tAc \
  "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"
# only if the count was not 0:
docker exec postgres psql -U postgres -d postgres \
  -c 'DROP DATABASE immich WITH (FORCE);' -c 'CREATE DATABASE immich;'
```

### 4.5 Restore into the new container

This is Immich's documented restore. The `sed` rewrites the dump's
`search_path` setting; the parentheses are unescaped here because the
escaped form in the Immich docs is a grouping operator in GNU sed and
does not match. `--single-transaction` is required because the rewritten
setting is transaction local, and it also means a failure rolls back
everything, leaving the database empty for a retry.

```bash
gunzip --stdout "$DUMP" \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | docker exec -i postgres psql --dbname=immich --username=postgres \
      --single-transaction --set ON_ERROR_STOP=on 2>&1 \
  | tee "$MIG/restore.log"; echo "restore exit: $?"
```

Filtered variant, when 4.3 showed `vectors` extension lines: insert this
between the `sed` and the `docker exec`.

```bash
  | grep -vE '^(CREATE|DROP|ALTER|COMMENT ON) (EXTENSION|SCHEMA) (IF (NOT )?EXISTS )?vectors( |;)' \
```

For a large `smart_search` or `face_search` table, add
`-e PGOPTIONS='-c maintenance_work_mem=1GB'` to the `docker exec -i` to
speed up the index build. Progress can be watched from a second shell
with `pg_stat_progress_create_index`.

Expect `restore exit: 0` and no `ERROR` lines in `$MIG/restore.log`.
`NOTICE ... does not exist, skipping` lines are normal. Failures to
expect:

- `extension "vectors" is not available`: use the filtered variant.
- `relation ... already exists`: the target was not pristine, do 4.4.
- `extension "vchord" must be loaded via shared_preload_libraries`: the
  Stage A checkpoint was skipped; fix the postgres command line first.
- Killed during `CREATE INDEX`: raise `maintenance_work_mem` or the
  memory available to the container, then rerun.

### 4.6 Compare old and new

Expect `0` mismatches, the extension list from section 2 minus `vectors`
with `vchord 1.1.1` and `vector 0.8.5`, both vector indexes present as
`vchordrq`, and `0` invalid indexes.

```bash
docker exec immich_postgres psql -U postgres -d immich -tAc \
  "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1" \
| while read -r t; do
    o=$(docker exec immich_postgres psql -U postgres -d immich -tAc "SELECT count(*) FROM \"$t\"")
    n=$(docker exec postgres psql -U postgres -d immich -tAc "SELECT count(*) FROM \"$t\"")
    [ "$o" = "$n" ] && s=ok || s=MISMATCH
    printf '%-40s %12s %12s %s\n' "$t" "$o" "$n" "$s"
  done | tee "$MIG/counts.log"
grep -c MISMATCH "$MIG/counts.log"
docker exec postgres psql -U postgres -d immich -c \
  "SELECT extname, extversion FROM pg_extension ORDER BY 1;"
docker exec postgres psql -U postgres -d immich -c \
  "SELECT indexname, left(indexdef, 80) FROM pg_indexes WHERE indexname IN ('clip_index', 'face_index');"
docker exec postgres psql -U postgres -d immich -tAc \
  "SELECT count(*) FROM pg_index WHERE NOT indisvalid;"
```

### 4.7 Switch Immich to the new database

Run the full playbook. Everything in it is safe now:

- `postgres_pgbackrest_install` finds `PG_VERSION`, so no bootstrap
  decision; it re-enables the timers parked in Stage A.
- `immich_install` re-templates the compose file without the `database`
  service, warns about the orphan `immich_postgres` container and leaves
  it running, recreates `immich_server` with the new environment, starts
  machine learning and waits for the ping.
- `immich_restic_backup` sees a snapshot in the repo and real media on
  disk, so it does not restore.
- `postgres_pgbackrest_restore_verify` installs its script and timer.

Checkpoints. Expect `pong`, `DB_HOSTNAME=postgres`, no `ERROR` lines,
connections from the Immich container, and `immich_postgres` still up.

```bash
curl -s http://localhost:2283/api/server/ping; echo
docker inspect immich_server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^DB_'
docker logs --since 15m immich_server 2>&1 | grep -iE 'migrat|error' | tail
docker exec postgres psql -U postgres -c \
  "SELECT client_addr, count(*) FROM pg_stat_activity WHERE datname = 'immich' GROUP BY 1;"
docker ps -a --format '{{.Names}}\t{{.Status}}' | grep -E 'immich|postgres'
```

In the browser: log in as an existing user, scroll the timeline, open an
album, open People, run a smart search (exercises the vector index) and
compare Administration > Server Status with the counts from 4.6.

### 4.8 Stop the old database container

Downtime ends here. Keep the container and `/opt/immich/postgres` until
cleanup; `restart: unless-stopped` keeps it stopped, and the new compose
file no longer knows about it.

```bash
docker stop immich_postgres
curl -s http://localhost:2283/api/server/ping; echo
```

## 5. Stage C: first backups and verification (same window)

First full backup. Expect exit 0 and `status: ok` with one full backup.

```bash
/opt/postgres/backup.sh full; echo "backup exit: $?"
docker exec -u postgres postgres pgbackrest --stanza=main info
```

Test restore. Expect four active pgbackrest timers, `PASS` with the user
count from 4.6, and no leftover `restore.*` directory afterwards.

```bash
systemctl list-timers 'postgres-pgbackrest-*'
/opt/pgbackrest-restore-verify/verify.sh; echo "verify exit: $?"
ls /opt/pgbackrest-restore-verify
```

Media-only restic backup. Expect no `pg_dumpall` in the script, exit 0,
and a newest snapshot listing only the three media directories.

```bash
grep -c pg_dumpall /opt/immich-backup/backup.sh
/opt/immich-backup/backup.sh; echo "backup exit: $?"
source /opt/immich-backup/env && restic snapshots --latest 2
```

Disable Immich's built-in database backups: Administration > Settings >
Backup Settings. pgBackRest replaces them, and the client tools in the
Immich server image are not guaranteed to match Postgres 18.

Run the playbook once more and confirm it reports no failures.

## 6. Soak and cleanup (about one week later)

Wait for one full timer cycle: weekday diffs, the Sunday full backup,
`pgbackrest verify`, the restic check and the test restore. Failures
email root.

```bash
systemctl --failed
journalctl -u postgres-pgbackrest-backup-full.service -u postgres-pgbackrest-backup-diff.service --since '8 days ago' | grep -E 'completed successfully|ERROR' | tail
journalctl -u postgres-pgbackrest-restore-verify.service --since '8 days ago' | grep -E 'PASS|FAIL|ERROR'
docker exec -u postgres postgres pgbackrest --stanza=main info
```

Then clean up, in this order.

```bash
cd /opt/immich && docker compose up -d --remove-orphans   # removes immich_postgres
docker image rm ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
mv /opt/immich/postgres /opt/immich/postgres.pre-migration  # delete a week later
rm -rf /opt/immich-backup/db
```

Keep `/opt/immich-migration` (dump, logs, old compose file) until the
first monthly restic snapshot after the migration exists. Remove
`immich_install_db_data_location` and the other dropped variables from
the inventory.

Old restic snapshots that contain `pg_dumpall.sql` age out under the
forget policy (7 daily, 4 weekly). Monthly snapshots are kept forever, so
one old-style snapshot per month stays as a permanent fallback unless you
forget it by hand.

## 7. Rollback

After Stage A, before Stage B. Immich is untouched. To remove the new
stack: park the timers as in Stage A, `docker compose down` in
`/opt/postgres`, `rm -rf /opt/postgres`, and empty the S3 path so a
retry starts from a clean stanza.

During Stage B, before 4.7. The old database is intact.

```bash
docker start immich_server immich_machine_learning
```

If 4.5 completed, recreate the new database (the command in 4.4) before
any retry.

After 4.7. `/opt/immich/postgres` was only stopped, never modified, so
Immich resumes at the state of the 4.3 dump. Anything written through
Immich after the switch is lost from the database.

```bash
docker stop immich_server immich_machine_learning
docker start immich_postgres
cp -a /opt/immich-migration/docker-compose.yml.pre-migration /opt/immich/docker-compose.yml
cd /opt/immich && docker compose up -d
```

Then check out the pre-refactor roles and inventory on the control
machine before the next playbook run, or Ansible re-applies the new
compose file.

Worst case, old data directory damaged. Restore the 4.2 snapshot with
`immich_server` stopped and `immich_postgres` running:

```bash
source /opt/immich-backup/env
restic restore <snapshot id> --target / --include /opt/immich/data
restic dump <snapshot id> /opt/immich-backup/db/pg_dumpall.sql \
  | docker exec -i immich_postgres psql -U postgres -d postgres
docker start immich_server immich_machine_learning
```

## 8. Pitfalls

- Running the full playbook before 4.5. `immich_install` would point
  Immich at the empty database; Immich runs its migrations and creates an
  empty schema, and the restore then fails with `relation ... already
  exists`. Fix: stop `immich_server`, recreate the database (4.4),
  restore, continue. Do not create an admin user in that state.
- Bootstrap restore after Stage C. `postgres_pgbackrest_install` restores
  from the repo whenever `PG_VERSION` is absent and the stanza has a
  backup, so wiping `/opt/postgres/data` and re-running the role is a
  disaster recovery path, not a way to get a fresh initdb.
  `immich_restic_backup` restores only when the media directories hold
  nothing but `.immich` markers.
- `.immich` markers. Immich refuses to start if one disappears. Never
  delete them; they are backed up with the media, which is harmless.
- `retention-full` must be set on every pgBackRest repo or nothing
  expires.
- The vector index rebuild runs inside the single restore transaction.
  Time and memory scale with the `smart_search` and `face_search` row
  counts; `maintenance_work_mem` and the container memory are the knobs.
- Same Immich version on both sides. A newer image would run migrations
  on the freshly restored database during 4.7 and remove the ability to
  compare against the old one. Upgrade after the soak.
- Postgres is now reachable on `127.0.0.1:5432` with the Immich
  password. Immich itself connects over `immich_network`. Do not expose
  the port beyond localhost.
- `docker compose down` in `/opt/immich` before cleanup leaves
  `immich_postgres` alone; with `--remove-orphans` it deletes the
  container (not the data directory).

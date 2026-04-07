#!/bin/bash
set -e

PRIMARY_HOST="postgres-db-0.postgres-db.banking.svc.cluster.local"
REPLICA_USER="replicator"
DATA_DIR="/var/lib/postgresql/data"

# ──────────────────────────────────────────────────────
# PRIMARY SETUP
# ──────────────────────────────────────────────────────
if echo $HOSTNAME | grep -q "db-0"; then
  echo ">>> Starting as PRIMARY"

  if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
    echo ">>> Initializing primary data directory"
    initdb -D $DATA_DIR

    # Allow replication connections
    echo "host replication $REPLICA_USER all md5"  >> $DATA_DIR/pg_hba.conf
    # Allow app connections
    echo "host $DB_NAME $DB_USER all md5"          >> $DATA_DIR/pg_hba.conf

    # Enable WAL streaming
    cat >> $DATA_DIR/postgresql.conf <<EOF
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64
listen_addresses = '*'
EOF

    # Start postgres temporarily to create users and DB
    pg_ctl -D $DATA_DIR -o "-c listen_addresses=''" -w start

    psql -U postgres -c "CREATE USER $REPLICA_USER WITH REPLICATION ENCRYPTED PASSWORD '$DB_PASSWORD';"
    psql -U postgres -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';"
    psql -U postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

    pg_ctl -D $DATA_DIR -m fast -w stop
    echo ">>> Primary initialization complete"
  else
    echo ">>> Data directory exists, skipping initialization"
  fi

# ──────────────────────────────────────────────────────
# REPLICA SETUP
# ──────────────────────────────────────────────────────
else
  echo ">>> Starting as REPLICA"

  echo ">>> Waiting for primary at $PRIMARY_HOST..."
  until pg_isready -h $PRIMARY_HOST -U postgres; do
    echo ">>> Primary not ready yet, retrying in 2s..."
    sleep 2
  done
  echo ">>> Primary is ready"

  if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
    echo ">>> Cloning primary via pg_basebackup"
    PGPASSWORD=$DB_PASSWORD pg_basebackup \
      -h $PRIMARY_HOST \
      -U $REPLICA_USER \
      -D $DATA_DIR \
      -Fp -Xs -P -R

    cat >> $DATA_DIR/postgresql.auto.conf <<EOF
primary_conninfo = 'host=$PRIMARY_HOST port=5432 user=$REPLICA_USER password=$DB_PASSWORD'
EOF

    echo ">>> Replica initialization complete"
  else
    echo ">>> Data directory exists, skipping basebackup"
  fi
fi

echo ">>> Handing off to postgres"
exec postgres -D $DATA_DIR
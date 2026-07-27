#!/usr/bin/env python
"""Run a command while holding a PostgreSQL advisory lock.

Serializes the startup bootstrap across the Django-bearing containers, which
replaces the tactical-init one-shot container. Whichever container starts first
does the work; the others block here and then find it already done.

The lock is session scoped, not transaction scoped, so it is held for exactly as
long as this process holds its connection. A container killed mid-bootstrap drops
its connection, PostgreSQL releases the lock, and the next container proceeds:
there is no stale lock to clean up and no timeout to tune.

Indentation is 4 spaces, not the repo default of tabs: this is a Python file.
"""

import os
import subprocess
import sys
import time

import psycopg

# One Tactical RMM database per stack, so a fixed key needs no namespacing.
# Advisory lock keys share a single 64-bit space per database; nothing else in
# this stack takes one.
LOCK_KEY = 7215009346101


def connect(retries=60, delay=2):
    """Connect to the tacticalrmm database, waiting for it to accept auth.

    A TCP check only proves the port is open. PostgreSQL refuses connections for
    a while after that during its own first-run initialization, so retry rather
    than crash the container into a restart loop.
    """
    conninfo = {
        "host": os.environ.get("POSTGRES_HOST", "tactical-postgres"),
        "port": os.environ.get("POSTGRES_PORT", "5432"),
        "user": os.environ.get("POSTGRES_USER", "tactical"),
        "password": os.environ.get("POSTGRES_PASS", "tactical"),
        "dbname": os.environ.get("POSTGRES_DB", "tacticalrmm"),
    }

    last = None
    for _ in range(retries):
        try:
            return psycopg.connect(autocommit=True, **conninfo)
        except psycopg.OperationalError as exc:
            last = exc
            print(f"pg_lock: waiting for postgresql: {exc}", file=sys.stderr)
            time.sleep(delay)
    raise SystemExit(f"pg_lock: could not reach postgresql: {last}")


def main():
    if len(sys.argv) < 2:
        print("usage: pg_lock.py <command> [args...]", file=sys.stderr)
        return 2

    with connect() as conn:
        print(f"pg_lock: acquiring bootstrap lock {LOCK_KEY}", file=sys.stderr)
        # Blocks until granted. autocommit keeps this out of a transaction, so no
        # snapshot is pinned for the lifetime of the child process.
        conn.execute("SELECT pg_advisory_lock(%s)", (LOCK_KEY,))
        print("pg_lock: lock held", file=sys.stderr)
        try:
            return subprocess.run(sys.argv[1:]).returncode
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", (LOCK_KEY,))
            print("pg_lock: lock released", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())

"""Import all CSV / Parquet files from ./data into PostgreSQL bronze schema.

Usage (from project root): python scripts/01_import_bronze.py
One source file -> one table. Existing tables are NOT replaced.
All source fields load as TEXT in Bronze; typed conversions happen in Silver.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import pandas as pd
import pyarrow.parquet as pq
from dotenv import load_dotenv
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import URL
from sqlalchemy.types import Text

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
load_dotenv(ROOT / ".env", override=True)

import os

DB = os.getenv("PGDATABASE", "defi_pools")
if DB != "defi_pools":
    raise SystemExit(f"STOP: PGDATABASE={DB!r}, expected 'defi_pools'.")

URL_CONN = URL.create(
    "postgresql+psycopg",
    username=os.getenv("PGUSER", "postgres"),
    password=os.getenv("PGPASSWORD") or None,
    host=os.getenv("PGHOST", "127.0.0.1"),
    port=int(os.getenv("PGPORT", "2018")),
    database=DB,
)


def sql_name(value: str) -> str:
    val = re.sub(r"[^a-z0-9_]+", "_", str(value).lower()).strip("_") or "unnamed"
    if val[0].isdigit():
        val = "t_" + val
    return val[:63]


def batches(filepath: Path):
    if filepath.suffix.lower() == ".csv":
        yield from pd.read_csv(filepath, chunksize=5000, dtype=str, keep_default_na=False,
                               encoding="utf-8-sig")
    else:
        reader = pq.ParquetFile(filepath)
        for batch in reader.iter_batches(batch_size=5000):
            yield batch.to_pandas()


def to_text(value):
    """Keep source values textual, preserving nested Parquet objects as JSON."""
    if value is None:
        return None
    if isinstance(value, (list, tuple, dict)):
        return json.dumps(value, ensure_ascii=False, default=str)
    if hasattr(value, "tolist") and not isinstance(value, (str, bytes)):
        arr = value.tolist()
        if isinstance(arr, (list, dict)):
            return json.dumps(arr, ensure_ascii=False, default=str)
    try:
        if bool(pd.isna(value)):
            return None
    except (TypeError, ValueError):
        pass
    return str(value)


def prepare(frame: pd.DataFrame, filename: str) -> pd.DataFrame:
    names = [sql_name(c) for c in frame.columns]
    if len(set(names)) != len(names) or "_source_file" in names:
        raise ValueError(f"Duplicate/reserved column names in {filename}: {names}")
    frame = frame.copy()
    frame.columns = names
    for col in names:
        frame[col] = frame[col].map(to_text)
    frame["_source_file"] = filename
    return frame


def main():
    source_files = sorted(f for f in DATA.iterdir()
                          if f.is_file() and f.suffix.lower() in (".csv", ".parquet"))
    if not source_files:
        raise SystemExit("No CSV or Parquet found in data/. Copy your 12 files there first.")
    names = [sql_name(f.stem) for f in source_files]
    if len(set(names)) != len(names):
        raise SystemExit("Two files have the same stem (e.g. x.csv and x.parquet). Rename one first.")

    engine = create_engine(URL_CONN, pool_pre_ping=True)
    with engine.begin() as conn:
        current = conn.execute(text("SELECT current_database()" )).scalar_one()
        if current != "defi_pools":
            raise SystemExit(f"STOP: connected to {current!r}, not 'defi_pools'.")
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS bronze"))
        print(f"Connected to PostgreSQL database: {current}")

    failed = []
    for file in source_files:
        table = sql_name(file.stem)
        try:
            # One transaction per input file: either the whole file loads, or none of it does.
            with engine.begin() as conn:
                if inspect(conn).has_table(table, schema="bronze"):
                    print(f"SKIP bronze.{table} (already exists)")
                    continue
                rows, first = 0, True
                for chunk in batches(file):
                    df = prepare(chunk, file.name)
                    if df.empty:
                        continue
                    df.to_sql(table, conn, schema="bronze",
                              if_exists="fail" if first else "append",
                              index=False, chunksize=1000,
                              dtype={c: Text() for c in df.columns})
                    first, rows = False, rows + len(df)
                if first:
                    print(f"SKIP {file.name} (no rows)")
                else:
                    print(f"OK   bronze.{table:<32} {rows:>9,} rows")
        except Exception as exc:
            failed.append((file.name, str(exc)))
            print(f"ERROR {file.name}: {exc}")

    engine.dispose()
    if failed:
        raise SystemExit(f"{len(failed)} file(s) failed. See ERROR lines above; other files imported.")
    print("Finished. Refresh Database Client > defi_pools > bronze > Tables.")


if __name__ == "__main__":
    main()

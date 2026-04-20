from __future__ import annotations

import datetime as dt
from typing import Iterable


def parse_timeout_hours(raw_value: str | None, default: float = 2.0) -> float:
    if raw_value is None:
        return default
    value = raw_value.strip()
    if not value:
        return default
    try:
        parsed = float(value)
    except ValueError:
        return default
    # A non-positive timeout would mark every in-flight run as stale on the
    # next sensor tick, so fall back to the default instead of returning 0.
    if parsed <= 0:
        return default
    return parsed


def run_status_name(run) -> str:
    status = getattr(run, "status", None)
    if hasattr(status, "name"):
        return str(status.name).upper()
    if isinstance(status, str):
        return status.split(".")[-1].upper()
    return str(status).split(".")[-1].upper()


def run_start_timestamp(run) -> float | None:
    for attr in ("start_time", "create_timestamp", "creation_time"):
        value = getattr(run, attr, None)
        if value is None:
            continue
        if hasattr(value, "timestamp"):
            return float(value.timestamp())
        try:
            return float(value)
        except (TypeError, ValueError):
            continue
    return None


def find_stale_runs(
    runs: Iterable[object],
    *,
    job_name: str,
    timeout_hours: float,
    now: dt.datetime | None = None,
) -> list[tuple[str, dt.datetime]]:
    reference_time = now or dt.datetime.now(dt.timezone.utc)
    cutoff = reference_time - dt.timedelta(hours=timeout_hours)
    stale_runs: list[tuple[str, dt.datetime]] = []

    for run in runs:
        if getattr(run, "job_name", None) != job_name:
            continue
        if run_status_name(run) not in {"STARTED", "STARTING"}:
            continue
        start_timestamp = run_start_timestamp(run)
        if start_timestamp is None:
            continue
        started_at = dt.datetime.fromtimestamp(start_timestamp, tz=dt.timezone.utc)
        if started_at <= cutoff:
            stale_runs.append((run.run_id, started_at))

    return stale_runs

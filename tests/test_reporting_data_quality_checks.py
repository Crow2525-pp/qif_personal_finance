from __future__ import annotations

import datetime as dt
import sys
import types
from pathlib import Path
import importlib.util


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))
sys.path.insert(0, str(REPO_ROOT))


def _ensure_psycopg2_stub() -> None:
    if "psycopg2" in sys.modules:
        return

    psycopg2 = types.ModuleType("psycopg2")
    extras = types.ModuleType("psycopg2.extras")

    class _RealDictCursor:  # pragma: no cover - simple compatibility stub
        pass

    extras.RealDictCursor = _RealDictCursor
    psycopg2.extras = extras
    psycopg2.connect = lambda **kwargs: None
    sys.modules["psycopg2"] = psycopg2
    sys.modules["psycopg2.extras"] = extras


_ensure_psycopg2_stub()

import check_reporting_data_quality as dq  # noqa: E402

_RUN_TIMEOUT_SPEC = importlib.util.spec_from_file_location(
    "run_timeout",
    REPO_ROOT
    / "data_projects"
    / "qif_personal_finance"
    / "pipeline_personal_finance"
    / "run_timeout.py",
)
run_timeout = importlib.util.module_from_spec(_RUN_TIMEOUT_SPEC)
assert _RUN_TIMEOUT_SPEC.loader is not None
_RUN_TIMEOUT_SPEC.loader.exec_module(run_timeout)


class FakeCursor:
    def __init__(self, responses):
        self.responses = responses
        self._rows = []

    def execute(self, query, params=None):
        for matcher, rows in self.responses:
            if matcher(query, params):
                self._rows = list(rows)
                return
        raise AssertionError(f"unexpected query: {query}")

    def fetchone(self):
        return self._rows[0] if self._rows else None

    def fetchall(self):
        return list(self._rows)


def _row(**values):
    return values


def test_new_checks_are_registered():
    registered_ids = {check["id"] for check in dq._CHECKS}
    assert {
        "DQ010",
        "DQ011",
        "DQ012",
        "DQ013",
        "DQ014",
        "DQ015",
        "DQ016",
        "DQ017",
    } <= registered_ids


def test_dq010_requires_property_assets():
    cursor = FakeCursor([
        (
            lambda query, params: "rpt_household_net_worth" in query,
            [_row(
                budget_year_month="2026-02",
                total_assets=13600,
                liquid_assets=13600,
                property_assets=0,
                net_worth=13600,
            )],
        )
    ])

    result = dq._check_property_assets(cursor)

    assert result.check_id == "DQ010"
    assert result.passed is False
    assert "property_assets=0.0" in result.detail


def test_dq011_requires_three_populated_cash_flow_months():
    cursor = FakeCursor([
        (
            lambda query, params: "rpt_cash_flow_analysis" in query,
            [
                _row(budget_year_month="2026-02", total_inflows=1000, total_outflows=900, net_cash_flow=100),
                _row(budget_year_month="2026-01", total_inflows=2000, total_outflows=1500, net_cash_flow=500),
                _row(budget_year_month="2025-12", total_inflows=1500, total_outflows=1200, net_cash_flow=300),
            ],
        )
    ])

    result = dq._check_cash_flow_analysis(cursor)

    assert result.check_id == "DQ011"
    assert result.passed is True
    assert "2026-02" in result.detail
    assert "2025-12" in result.detail


def test_dq013_accepts_recent_dashboard_refresh():
    import datetime as _dt

    cursor = FakeCursor([
        (
            lambda query, params: "rpt_executive_dashboard" in query,
            [_row(
                dashboard_month="2026-02",
                dashboard_generated_at=_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(days=10),
            )],
        )
    ])

    result = dq._check_executive_dashboard_refresh(cursor)

    assert result.check_id == "DQ013"
    assert result.passed is True


def test_dq014_requires_complete_monthly_snapshot():
    cursor = FakeCursor([
        (
            lambda query, params: "rpt_monthly_budget_summary" in query,
            [_row(
                budget_year_month="2026-02",
                total_income=5000,
                total_expenses=4200,
                net_cash_flow=800,
                savings_rate_percent=0.16,
                expense_ratio_percent=0.84,
            )],
        ),
        (
            lambda query, params: "rpt_executive_dashboard" in query,
            [_row(
                dashboard_month="2026-02",
                current_net_worth=120000,
                liquid_assets=35000,
                total_assets=160000,
                total_liabilities=40000,
            )],
        ),
        (
            lambda query, params: "rpt_household_net_worth" in query,
            [_row(
                budget_year_month="2026-02",
                total_assets=160000,
                total_liabilities=40000,
                net_worth=120000,
                liquid_assets=35000,
            )],
        ),
    ])

    result = dq._check_monthly_snapshot_complete(cursor)

    assert result.check_id == "DQ014"
    assert result.passed is True
    assert "summary_missing=[]" in result.detail


def test_dq015_requires_at_least_six_months_of_cash_flow_history():
    cursor = FakeCursor([
        (
            lambda query, params: "rpt_cash_flow_analysis" in query,
            [
                _row(budget_year_month="2026-02"),
                _row(budget_year_month="2026-01"),
                _row(budget_year_month="2025-12"),
                _row(budget_year_month="2025-11"),
                _row(budget_year_month="2025-10"),
                _row(budget_year_month="2025-09"),
            ],
        )
    ])

    result = dq._check_cash_flow_trend_history(cursor)

    assert result.check_id == "DQ015"
    assert result.passed is True
    assert "distinct_closed_months=6" in result.detail


def test_dq016_requires_non_zero_savings_rows():
    cursor = FakeCursor([
        (
            lambda query, params: "rpt_savings_analysis" in query,
            [
                _row(
                    budget_year_month="2026-02",
                    total_savings=800,
                    total_savings_rate_percent=0.16,
                    traditional_savings_rate_percent=0.12,
                    liquid_savings_rate_percent=0.07,
                    investment_rate_percent=0.03,
                ),
                _row(
                    budget_year_month="2026-01",
                    total_savings=700,
                    total_savings_rate_percent=0.14,
                    traditional_savings_rate_percent=0.11,
                    liquid_savings_rate_percent=0.06,
                    investment_rate_percent=0.02,
                ),
                _row(
                    budget_year_month="2025-12",
                    total_savings=650,
                    total_savings_rate_percent=0.13,
                    traditional_savings_rate_percent=0.10,
                    liquid_savings_rate_percent=0.05,
                    investment_rate_percent=0.01,
                ),
            ],
        )
    ])

    result = dq._check_savings_analysis(cursor)

    assert result.check_id == "DQ016"
    assert result.passed is True


def test_dq017_requires_multiple_positive_net_worth_months():
    cursor = FakeCursor([
        (
            lambda query, params: "rpt_household_net_worth" in query,
            [
                _row(budget_year_month="2026-02", net_worth=120000),
                _row(budget_year_month="2026-01", net_worth=118000),
                _row(budget_year_month="2025-12", net_worth=115000),
                _row(budget_year_month="2025-11", net_worth=0),
            ],
        )
    ])

    result = dq._check_net_worth_trend(cursor)

    assert result.check_id == "DQ017"
    assert result.passed is True
    assert "positive_months=3" in result.detail


def test_timeout_helpers_identify_stale_runs():
    class Run:
        def __init__(self, run_id, job_name, status, start_time):
            self.run_id = run_id
            self.job_name = job_name
            self.status = status
            self.start_time = start_time

    now = dt.datetime(2026, 3, 18, 12, 0, tzinfo=dt.timezone.utc)
    runs = [
        Run("fresh", "qif_pipeline_job", "STARTED", now.timestamp() - 1800),
        Run("stale", "qif_pipeline_job", "STARTED", now.timestamp() - 8 * 3600),
        Run("other-job", "different", "STARTED", now.timestamp() - 8 * 3600),
    ]

    stale = run_timeout.find_stale_runs(
        runs,
        job_name="qif_pipeline_job",
        timeout_hours=2,
        now=now,
    )

    assert len(stale) == 1
    assert stale[0][0] == "stale"
    assert run_timeout.parse_timeout_hours("  ") == 2.0
    assert run_timeout.parse_timeout_hours("4.5") == 4.5
    # Non-positive timeouts must fall back to the default to avoid
    # terminating every in-flight run on the next sensor tick.
    assert run_timeout.parse_timeout_hours("0") == 2.0
    assert run_timeout.parse_timeout_hours("-3") == 2.0
    assert run_timeout.parse_timeout_hours("0", default=1.5) == 1.5

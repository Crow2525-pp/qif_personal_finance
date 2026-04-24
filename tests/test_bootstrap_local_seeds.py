from __future__ import annotations

from pathlib import Path

from scripts.bootstrap_local_seeds import bootstrap_qif_files


QIF_DIR = Path("data_projects/qif_personal_finance/pipeline_personal_finance/qif_files")


def test_bootstrap_qif_files_materializes_mixed_case_extensions(tmp_path: Path):
    repo_root = tmp_path / "repo"
    shared_dir = tmp_path / "shared"
    shared_dir.mkdir(parents=True)

    (shared_dir / "ING_Countdown_Transactions_20260422.QIF").write_text(
        "countdown",
        encoding="utf-8",
    )
    (shared_dir / "Adelaide_Homeloan_Transactions_20260419.qIf").write_text(
        "homeloan",
        encoding="utf-8",
    )
    (shared_dir / "ignore.txt").write_text("nope", encoding="utf-8")

    messages = bootstrap_qif_files(repo_root, shared_dir, mode="copy")

    target_dir = repo_root / QIF_DIR
    assert (target_dir / "ING_Countdown_Transactions_20260422.QIF").read_text(encoding="utf-8") == "countdown"
    assert (target_dir / "Adelaide_Homeloan_Transactions_20260419.qIf").read_text(encoding="utf-8") == "homeloan"
    assert not (target_dir / "ignore.txt").exists()
    assert any("ING_Countdown_Transactions_20260422.QIF" in message for message in messages)
    assert any("Adelaide_Homeloan_Transactions_20260419.qIf" in message for message in messages)

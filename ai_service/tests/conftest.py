"""Keep simulated provider tests out of the live shared quota ledger."""
import sys
import pytest


@pytest.fixture(autouse=True)
def isolated_quota_ledger(tmp_path, monkeypatch):
    from app.core.config import settings
    monkeypatch.setenv("AI_QUOTA_LEDGER_PATH", str(tmp_path / "quota.json"))
    monkeypatch.setattr(settings, "AI_QUOTA_LEDGER_PATH", tmp_path / "quota.json")
    module = sys.modules.get("app.core.container")
    if module is not None:
        governor = module.container.llm_service.governor
        if hasattr(governor, "path"):
            monkeypatch.setattr(governor, "path", tmp_path / "container-quota.json")

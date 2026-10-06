"""Approval boundaries and failure behavior; no databases or LLM calls."""

import asyncio
import json
import os
import subprocess
import sys
from dataclasses import FrozenInstanceError
from pathlib import Path

import pytest

from app.core.config import Settings
from app.core.exceptions import KnowledgeDocumentException
from app.infrastructure.knowledge.document_schema import ArticleDocument
from app.infrastructure.knowledge.file_knowledge_repository import FileKnowledgeRepository
from app.infrastructure.knowledge.inspect_document import inspect


def article(identifier="fixture.fact", status="draft"):
    data = {
        "id": identifier, "title": "ข้อมูลทดสอบ", "content": "ข้อเท็จจริงทดสอบที่เจ้าของตรวจได้",
        "sources": [{"title": "เอกสารทดสอบ", "reference": "fixture-owner-document", "revision": "fixture-revision"}],
        "reviewed_at": "2026-10-03", "status": "draft", "approval": None,
    }
    if status == "approved":
        data["approval"] = {
            "approved_by": "fixture-owner", "approved_at": "2026-10-03T14:00:00+07:00",
            "content_sha256": ArticleDocument.model_validate(data).approval_digest(),
        }
    data["status"] = status
    return data


def write_document(path, articles):
    path.write_text(json.dumps({
        "schema_version": "1", "document_id": "fixture-document", "version": "fixture-version",
        "articles": articles,
    }, ensure_ascii=False), encoding="utf-8")


@pytest.mark.asyncio
async def test_only_explicitly_approved_facts_are_returned_with_provenance(tmp_path):
    path = tmp_path / "ความรู้.json"
    write_document(path, [article("allowed", "approved"), article("draft"),
                          article("unverified", "unverified"), article("rejected", "rejected")])
    snapshot = await FileKnowledgeRepository(path).get_approved_knowledge()
    assert [entry.id for entry in snapshot.articles] == ["allowed"]
    allowed = snapshot.articles[0]
    assert allowed.approved_by == "fixture-owner"
    assert allowed.approved_at.utcoffset() is not None
    assert allowed.sources[0].reference == "fixture-owner-document"
    assert allowed.sources[0].revision == "fixture-revision"
    assert snapshot.document_id == "fixture-document"
    with pytest.raises(FrozenInstanceError):
        allowed.content = "mutated"


@pytest.mark.asyncio
@pytest.mark.parametrize("change", ["content", "evidence", "review_date", "identity"])
async def test_edits_cannot_reuse_a_previous_approval(tmp_path, change):
    path = tmp_path / "facts.json"
    data = article(status="approved")
    write_document(path, [data])
    repository = FileKnowledgeRepository(path)
    assert len((await repository.get_approved_knowledge()).articles) == 1
    if change == "content":
        data["content"] = "ข้อความที่ยังไม่ได้อนุมัติ"
    elif change == "evidence":
        data["sources"][0]["reference"] = "different-evidence"
    elif change == "review_date":
        data["reviewed_at"] = "2026-10-02"
    else:
        data["id"] = "different-fact"
    write_document(path, [data])
    with pytest.raises(KnowledgeDocumentException) as failed:
        await repository.get_approved_knowledge()
    assert failed.value.code == "invalid_document"


@pytest.mark.asyncio
async def test_revoked_approval_is_not_cached(tmp_path):
    path = tmp_path / "facts.json"
    data = article(status="approved")
    write_document(path, [data])
    repository = FileKnowledgeRepository(path)
    before = await repository.get_approved_knowledge()
    data.update(status="rejected", approval=None)
    write_document(path, [data])
    after = await repository.get_approved_knowledge()
    assert before.articles and not after.articles
    assert before.document_sha256 != after.document_sha256


@pytest.mark.asyncio
async def test_invalid_update_does_not_serve_last_known_approved_text(tmp_path):
    path = tmp_path / "facts.json"
    write_document(path, [article(status="approved")])
    repository = FileKnowledgeRepository(path)
    assert (await repository.get_approved_knowledge()).articles
    path.write_text('{"incomplete":', encoding="utf-8")
    with pytest.raises(KnowledgeDocumentException) as failed:
        await repository.get_approved_knowledge()
    assert failed.value.code == "invalid_document"


@pytest.mark.asyncio
@pytest.mark.parametrize("invalid", ["missing_metadata", "missing_evidence", "naive_timestamp", "approval_before_review", "unapproved_with_metadata"])
async def test_invalid_approval_fails_closed_even_next_to_valid_fact(tmp_path, invalid):
    path = tmp_path / "facts.json"
    invalid_article = article("invalid", "approved")
    if invalid == "missing_metadata":
        invalid_article["approval"] = None
    elif invalid == "missing_evidence":
        invalid_article["sources"] = []
    elif invalid == "naive_timestamp":
        invalid_article["approval"]["approved_at"] = "2026-10-03T14:00:00"
    elif invalid == "approval_before_review":
        invalid_article["approval"]["approved_at"] = "2026-10-02T14:00:00+07:00"
    else:
        invalid_article["status"] = "draft"
    write_document(path, [article("valid", "approved"), invalid_article])
    with pytest.raises(KnowledgeDocumentException):
        await FileKnowledgeRepository(path).get_approved_knowledge()


@pytest.mark.asyncio
async def test_unverified_topic_is_not_an_approved_policy(tmp_path):
    path = tmp_path / "facts.json"
    unknown = article("unknown-policy", "unverified")
    unknown["sources"] = []
    write_document(path, [unknown])
    assert not (await FileKnowledgeRepository(path).get_approved_knowledge()).articles
    unknown["status"] = "approved"
    write_document(path, [unknown])
    with pytest.raises(KnowledgeDocumentException):
        await FileKnowledgeRepository(path).get_approved_knowledge()


@pytest.mark.asyncio
async def test_duplicate_article_ids_and_unknown_fields_are_rejected(tmp_path):
    path = tmp_path / "facts.json"
    write_document(path, [article("same", "approved"), article("same")])
    with pytest.raises(KnowledgeDocumentException):
        await FileKnowledgeRepository(path).get_approved_knowledge()
    data = article()
    data["approved"] = True
    write_document(path, [data])
    with pytest.raises(KnowledgeDocumentException):
        await FileKnowledgeRepository(path).get_approved_knowledge()


@pytest.mark.asyncio
async def test_configuration_and_io_errors_are_explicit_without_path_leaks(tmp_path, monkeypatch):
    for path, expected in [(None, "not_configured"), (tmp_path / "private-fixture-path.json", "not_found")]:
        with pytest.raises(KnowledgeDocumentException) as failed:
            await FileKnowledgeRepository(path).get_approved_knowledge()
        assert failed.value.code == expected
        assert "private-fixture-path" not in str(failed.value)

    def forbidden_read(path):
        raise PermissionError("private-fixture-path")

    monkeypatch.setattr(Path, "read_bytes", forbidden_read)
    with pytest.raises(KnowledgeDocumentException) as failed:
        await FileKnowledgeRepository(tmp_path / "facts.json").get_approved_knowledge()
    assert failed.value.code == "unreadable"
    assert "private-fixture-path" not in str(failed.value)


@pytest.mark.asyncio
@pytest.mark.parametrize("raw", [b"\xff\xfe", b'{"private-fixture":"sensitive text",', b'{"schema_version":"1","schema_version":"1"}'])
async def test_invalid_encoding_json_and_duplicate_keys_are_safely_rejected(tmp_path, raw):
    path = tmp_path / "facts.json"
    path.write_bytes(raw)
    with pytest.raises(KnowledgeDocumentException) as failed:
        await FileKnowledgeRepository(path).get_approved_knowledge()
    assert failed.value.code == "invalid_document"
    assert "sensitive" not in str(failed.value)


@pytest.mark.asyncio
async def test_unicode_and_bom_and_independent_documents(tmp_path):
    first = tmp_path / "หนึ่ง.json"
    second = tmp_path / "สอง.json"
    write_document(first, [article("first", "approved")])
    write_document(second, [article("second", "approved")])
    first.write_bytes(b"\xef\xbb\xbf" + first.read_bytes())
    snapshots = await asyncio.gather(FileKnowledgeRepository(first).get_approved_knowledge(),
                                     FileKnowledgeRepository(second).get_approved_knowledge())
    assert [[entry.id for entry in snapshot.articles] for snapshot in snapshots] == [["first"], ["second"]]


def test_knowledge_path_is_injected_and_blank_values_are_not_current_directory():
    assert Settings(_env_file=None, APP_KNOWLEDGE_PATH="  ").APP_KNOWLEDGE_PATH is None
    assert Settings(_env_file=None, APP_KNOWLEDGE_PATH=" facts.json ").APP_KNOWLEDGE_PATH == Path("facts.json")


@pytest.mark.asyncio
async def test_owner_review_document_is_valid_and_all_repository_references_exist():
    service_root = Path(__file__).resolve().parents[1]
    document_path = service_root / "knowledge/app_knowledge.json"
    inspection = await inspect(document_path)
    payload = json.loads(document_path.read_text(encoding="utf-8"))
    assert sum(inspection["counts"].values()) == len(payload["articles"])
    for entry in payload["articles"]:
        for evidence in entry["sources"]:
            reference = (service_root.parent / evidence["reference"]).resolve()
            assert reference.is_relative_to(service_root.parent)
            assert reference.is_file(), evidence["reference"]


def test_operator_command_outputs_utf8_on_windows_legacy_encoding():
    service_root = Path(__file__).resolve().parents[1]
    task_env = dict(os.environ, PYTHONIOENCODING="cp1252")
    result = subprocess.run(
        [sys.executable, "-m", "app.infrastructure.knowledge.inspect_document", "--path", "knowledge/app_knowledge.json"],
        cwd=service_root, env=task_env, capture_output=True, check=False,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    report = json.loads(result.stdout.decode("utf-8"))
    assert any("แอป" in entry["title"] for entry in report["articles"])

from copy import deepcopy
import json

from evaluation.conversation_20261004.runner import ROOT, digest, next_request, planned_rows, read, scores, validate


def configuration():
    return read(ROOT / "config.json")


def test_six_groups_have_twenty_distinct_stimuli_and_three_rounds():
    config = configuration()
    validate(config, read(ROOT / "suite.json"))
    assert len(planned_rows(config)) == 360


def test_partial_review_cannot_meet_threshold_or_certify():
    config = configuration()
    report = {"rows": planned_rows(config)}
    row = report["rows"][0]
    row.update(status="completed", contract_checks={"catalog": True})
    review = {"key": row["key"], "turns_sha256": digest(row["turns"]),
              "semantic_pass": True, "reviewer_kind": "independent_human", "reviewed_by": "tester"}
    scores(report, config, {"entries": [review]})
    assert report["scores"][0]["observed_accuracy"] == 1
    assert report["scores"][0]["full_group_accuracy"] is None
    assert not report["all_groups_threshold_met"]
    assert not report["certificate_95_percent"]


def test_ai_review_is_never_relabelled_as_independent_human():
    config = configuration()
    report = {"rows": planned_rows(config)}
    entries = []
    for row in report["rows"]:
        row.update(status="completed", contract_checks={"catalog": True})
        entries.append({"key": row["key"], "turns_sha256": digest(row["turns"]),
                        "semantic_pass": True, "reviewer_kind": "codex_ai", "reviewed_by": "Codex"})
    scores(report, config, {"entries": entries})
    assert report["all_groups_threshold_met"]
    assert not report["certificate_95_percent"]


def test_changed_output_invalidates_review():
    config = configuration()
    row = planned_rows(config)[0]
    row.update(status="completed", contract_checks={"catalog": True})
    entry = {"key": row["key"], "turns_sha256": digest(row["turns"]), "semantic_pass": True}
    row["turns"].append({"changed": True})
    report = {"rows": planned_rows(config)}
    report["rows"][0] = row
    scores(report, config, {"entries": [entry]})
    assert report["scores"][0]["reviewed"] == 0


def test_choice_continuation_uses_real_question_ids_and_actual_history_only():
    config = configuration()
    context = {"session_id": "test-session", "user_goal": "บันทึกเสียง", "questions": [
        {"id": "generated:people", "title": "จำนวนผู้พูด", "dimension": "people", "choices": [
            {"id": "generated:one", "label": "คนเดียว", "action_value": "ผู้พูดหนึ่งคน"},
            {"id": "generated:two", "label": "สองคน", "action_value": "ผู้พูดสองคน"}]}]}
    row = {"group": "selected_choices", "case_index": 1, "session_id": "test-session",
           "steps": ["ช่วยเลือกอุปกรณ์บันทึกเสียง"], "turns": [
               {"request": {"message": "ช่วยเลือกอุปกรณ์บันทึกเสียง"},
                "result": {"response": "ต้องบันทึกกี่คน", "context": context, "questions": context["questions"]}}]}
    snapshot = deepcopy(row)
    request = next_request(row, config)
    assert request.questionnaire_answers[0].question_id == "generated:people"
    assert request.questionnaire_answers[0].option_id == "generated:two"
    assert request.message == "สองคน"
    assert [m.content for m in request.history] == ["ช่วยเลือกอุปกรณ์บันทึกเสียง", "ต้องบันทึกกี่คน"]
    assert "rubric" not in request.model_dump()
    assert "expected" not in request.model_dump()
    assert row == snapshot


def test_ui_review_cannot_copy_a_pass_to_an_unread_new_output(tmp_path, monkeypatch):
    from evaluation.conversation_20261004 import review_ui
    monkeypatch.setattr(review_ui, "ROOT", tmp_path)
    attempts = [{"flow": "choices", "started_at": "2026-10-04T01:00:00+00:00",
                 "output_sha256": hash_value, "outcome": "completed"}
                for hash_value in ("manually-read-output", "new-unread-output")]
    (tmp_path / "ui_attempts.json").write_text(json.dumps({"attempts": attempts}), encoding="utf-8")
    (tmp_path / "ui_review_notes.json").write_text(json.dumps({
        "notes": {"choices": "Reviewed the recorded turns"},
        "reviewed_output_hashes": ["manually-read-output"]}), encoding="utf-8")
    review_ui.main()
    reviews = json.loads((tmp_path / "ui_reviews.json").read_text(encoding="utf-8"))["entries"]
    assert len(reviews) == 1
    assert reviews[0]["output_sha256"] == "manually-read-output"

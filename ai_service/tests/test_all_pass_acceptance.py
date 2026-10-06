"""กันการรับรองทั้งหมดจากผลไม่ครบ hash ผิด หรือบุคลิกที่แค่โมเดลประกาศ."""
from copy import deepcopy
from evaluation.conversation_afterfix_20261004_v7.acceptance import case_passes
from evaluation.conversation_afterfix_20261004_v7.runner import digest


def fixture():
    turns = [{"result": {"response": "fixture", "speaker_register": "informal_ungendered"}}]
    fingerprint = digest(turns)
    row = {"status": "completed", "group": "small_talk", "turns": turns, "turns_sha256": fingerprint,
           "contract_checks": {k: True for k in ("real_catalog_cards", "question_bounds",
               "questions_cards_exclusive", "session_preserved", "nonempty_answer")}}
    review = {"turns_sha256": fingerprint, "semantic_pass": True, "neutral_voice_pass": True}
    return row, review


def test_complete_bound_semantic_and_voice_review_passes():
    assert case_passes(*fixture())


def test_incomplete_or_changed_turns_cannot_pass():
    row, review = fixture()
    incomplete = deepcopy(row); incomplete["status"] = "paused"
    assert not case_passes(incomplete, review)
    row["turns"][0]["result"]["response"] = "changed"
    assert not case_passes(row, review)


def test_declared_register_does_not_replace_actual_voice_review():
    row, review = fixture()
    for verdict in (None, False):
        review["neutral_voice_pass"] = verdict
        assert not case_passes(row, review)


def test_missing_or_failed_contract_cannot_pass():
    row, review = fixture()
    row["contract_checks"]["session_preserved"] = False
    assert not case_passes(row, review)
    row["contract_checks"] = {}
    assert not case_passes(row, review)

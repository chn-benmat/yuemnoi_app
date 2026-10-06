"""Evaluation evidence must survive a failed native capture and bind actual images."""
import hashlib
import json
import xml.etree.ElementTree as ET
import pytest
from evaluation.emulator_natural_20261006_v20 import driver, flow_review


def test_sent_request_is_retained_when_after_xml_dump_fails(tmp_path, monkeypatch):
    monkeypatch.setattr(driver, 'ROOT', tmp_path)
    (tmp_path / 'case_attempts.json').write_text('[]', encoding='utf-8')
    button = ET.Element('node', {'content-desc': 'ส่งข้อความ', 'bounds': '[0,0][2,2]'})

    def snapshot(name):
        (tmp_path / (name + '.png')).write_bytes(b'actual-evaluation-test-picture')
        if name.endswith('_after'):
            raise RuntimeError('uiautomator returned no XML')
        (tmp_path / (name + '.xml')).write_text('<hierarchy/>', encoding='utf-8')
        return [button]

    def tap(node):
        (tmp_path / 'turn_actual.json').write_text(json.dumps({'started_at': '2026-10-06T00:00:00+00:00'}), encoding='utf-8')

    monkeypatch.setattr(driver, 'snapshot', snapshot)
    monkeypatch.setattr(driver, 'tap', tap)
    driver.send('r1_B1')
    attempts = json.loads((tmp_path / 'case_attempts.json').read_text(encoding='utf-8'))
    assert len(attempts) == 1
    assert attempts[0]['capture_error_type'] == 'RuntimeError'
    assert attempts[0]['turn_artifacts'][0]['path'] == 'turn_actual.json'
    assert len(attempts[0]['screens']) == 2


def test_flow_review_detects_image_changed_without_raw_turn_change(tmp_path, monkeypatch):
    monkeypatch.setattr(flow_review, 'ROOT', tmp_path)
    image = tmp_path / 'r1_B1_after.png'
    image.write_bytes(b'captured-picture')
    record = {'image': image.name, 'xml': 'r1_B1_after.xml',
        'image_sha256': hashlib.sha256(image.read_bytes()).hexdigest()}
    (tmp_path / 'captures.jsonl').write_text(json.dumps(record) + '\n', encoding='utf-8')
    flow_review.flow_evidence([], ['r1_B1'])
    image.write_bytes(b'changed-picture')
    with pytest.raises(AssertionError):
        flow_review.flow_evidence([], ['r1_B1'])

"""Real rejected output must expose an actionable machine constraint to failover."""
import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.domain.entities.turn_plan import NativeTurnPlan


def test_recorded_all_unrestricted_choices_report_the_exact_constraint():
    output = json.loads((Path(__file__).parent / 'fixtures' /
                         'native_all_unrestricted_choices.json').read_text(encoding='utf-8'))
    with pytest.raises(ValidationError) as error:
        NativeTurnPlan.model_validate(output)
    codes = [entry['type'] for entry in error.value.errors()]
    assert codes.count('native_choices_require_specified_and_at_most_one_unrestricted') == 3
    assert 'value_error' not in codes

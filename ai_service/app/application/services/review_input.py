"""Lossless JSON-pointer references for repeated internal review subtrees."""
import copy
import json


def _child_path(path, key):
    return path + '/' + str(key).replace('~', '~0').replace('/', '~1')


def compact_review_draft(draft):
    seen, references = {}, {}
    def visit(value, path):
        if isinstance(value, (dict, list, str)) and value:
            encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
            previous = seen.get(encoded)
            if previous is not None:
                link_cost = len(json.dumps({path: previous}, ensure_ascii=False, separators=(',', ':')))
                if len(encoded) > len('null') + link_cost:
                    references[path] = previous
                    return None
            else:
                seen[encoded] = path
        if isinstance(value, dict):
            return {key: visit(child, _child_path(path, key)) for key, child in value.items()}
        if isinstance(value, list):
            return [visit(child, _child_path(path, i)) for i, child in enumerate(value)]
        return value
    return visit(draft, ''), references


def restore_review_draft(draft, references):
    """Restore all exact strings and paths; reject malformed or cyclic links."""
    if not references:
        return copy.deepcopy(draft)
    def at(path):
        if not isinstance(path, str) or path and not path.startswith('/'):
            raise ValueError('Invalid draft pointer')
        value = draft
        for token in path.split('/')[1:]:
            key = token.replace('~1', '/').replace('~0', '~')
            try:
                value = value[int(key)] if isinstance(value, list) else value[key]
            except (KeyError, TypeError, ValueError, IndexError):
                raise ValueError('Unknown draft pointer') from None
        return value
    for target, source in references.items():
        if at(target) is not None:
            raise ValueError('Draft link must replace only its null placeholder')
        at(source)
    def expand(path, ancestors):
        if path in ancestors:
            raise ValueError('Cyclic draft reference')
        ancestors = ancestors | {path}
        if path in references:
            return expand(references[path], ancestors)
        value = at(path)
        if isinstance(value, dict):
            return {key: expand(_child_path(path, key), ancestors) for key in value}
        if isinstance(value, list):
            return [expand(_child_path(path, i), ancestors) for i in range(len(value))]
        return value
    return expand('', frozenset())


def compact_planning_input(payload):
    """ลดเฉพาะข้อมูลซ้ำโดยคงข้อความและ provenance ต้นฉบับทุกฟิลด์."""
    projected, references = compact_review_draft(payload)
    result = {**projected, 'input_references': references}
    if restore_planning_input(result) != payload:
        raise ValueError('Planning projection is not lossless')
    return result


def restore_planning_input(payload):
    return restore_review_draft({k: v for k, v in payload.items() if k != 'input_references'}, payload.get('input_references', {}))

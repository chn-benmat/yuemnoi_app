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
    tables = {}
    def tabulate(value, path):
        if isinstance(value, dict):
            return {key: tabulate(child, _child_path(path, key)) for key, child in value.items()}
        if not isinstance(value, list):
            return value
        rows = [tabulate(child, _child_path(path, index)) for index, child in enumerate(value)]
        if len(rows) >= 2 and all(isinstance(row, dict) for row in rows):
            columns = list(rows[0])
            if columns and all(set(row) == set(columns) for row in rows):
                table = {'columns': columns, 'rows': [[row[key] for key in columns] for row in rows]}
                encode = lambda data: json.dumps(data, ensure_ascii=False, separators=(',', ':'))
                if len(encode({path: table})) + len('null') < len(encode(rows)):
                    tables[path] = table
                    return None
        return rows
    projected = tabulate(projected, '')
    # ตารางคลังมี category/unit/status ซ้ำมาก ใช้พจนานุกรมข้อความแบบคืนต้นฉบับได้
    counts = {}
    marker_collision = False
    def count(value):
        nonlocal marker_collision
        if isinstance(value, str):
            counts[value] = counts.get(value, 0) + 1
        elif isinstance(value, dict):
            marker_collision |= set(value) == {'$text'}
            for child in value.values(): count(child)
        elif isinstance(value, list):
            for child in value: count(child)
    count(projected)
    count(tables)
    encode = lambda data: json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    dictionary, indices = [], {}
    for value, amount in (counts.items() if not marker_collision else []):
        marker = {'$text': len(dictionary)}
        if amount * len(encode(value)) > amount * len(encode(marker)) + len(encode(value)) + 1:
            indices[value] = len(dictionary)
            dictionary.append(value)
    def intern(value):
        if isinstance(value, str) and value in indices:
            return {'$text': indices[value]}
        if isinstance(value, dict):
            return {key: intern(child) for key, child in value.items()}
        if isinstance(value, list):
            return [intern(child) for child in value]
        return value
    projected, tables = intern(projected), intern(tables)
    result = {**projected, 'input_references': references}
    if tables:
        result['input_tables'] = tables
    if dictionary:
        result['input_dictionary'] = dictionary
    if restore_planning_input(result) != payload:
        raise ValueError('Planning projection is not lossless')
    return result


def restore_planning_input(payload):
    dictionary = payload.get('input_dictionary', [])
    def unintern(value):
        if isinstance(value, dict):
            if set(value) == {'$text'}:
                index = value['$text']
                if type(index) is not int or not 0 <= index < len(dictionary) or not isinstance(dictionary[index],str):
                    raise ValueError('Invalid input dictionary reference')
                return dictionary[index]
            return {key: unintern(child) for key, child in value.items()}
        if isinstance(value, list):
            return [unintern(child) for child in value]
        return value
    if 'input_dictionary' in payload:
        payload = unintern({k: v for k,v in payload.items() if k != 'input_dictionary'})
    tables = payload.get('input_tables', {})
    def expand(value, path):
        if path in tables:
            table = tables[path]
            columns, rows = table['columns'], table['rows']
            if (value is not None or not columns or len(columns) != len(set(columns))
                    or any(len(row) != len(columns) for row in rows)):
                raise ValueError('Invalid input table')
            value = [dict(zip(columns, row)) for row in rows]
        if isinstance(value, dict):
            return {key: expand(child, _child_path(path, key)) for key, child in value.items()}
        if isinstance(value, list):
            return [expand(child, _child_path(path, index)) for index, child in enumerate(value)]
        return value
    data = {k: v for k, v in payload.items() if k not in ('input_references', 'input_tables')}
    return restore_review_draft(expand(data, ''), payload.get('input_references', {}))

"""Simulated assessment metadata for unit tests; never used by production or live probes."""
def assessed(result,paths=None):
    value=dict(result)
    names=('relevance','completeness','neutral_voice','choice_equivalence','grounding','context','followups')
    checks=value.get('checks')
    if checks is None:
        checks={key:True for key in names}
        for issue in value['issues']:
            key={'neutral_voice':'neutral_voice','semantic':'relevance','grounding':'grounding','context':'context','choice':'choice_equivalence','contract':'completeness'}[issue['kind']]
            checks[key]=False
        value['checks']=checks
    value['assessments']={name:{'reason':'Simulated independent unit-test assessment; not live quality evidence.',
        'field_paths':paths or ['/response'],'passed':checks[name]} for name in names}
    # Simulated legacy fixtures declare the expected verdict; the native model
    # contract now emits each assessment only once and derives that verdict.
    for key in ('checks','semantic_pass','neutral_voice_pass'):value.pop(key,None)
    value.setdefault('reviewed_surface_groups',[])
    return value

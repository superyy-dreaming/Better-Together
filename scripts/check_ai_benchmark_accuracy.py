#!/usr/bin/env python3
"""Check fixed synthetic benchmark facts; this is not a semantic-summary grader."""
import argparse
import json
import re
from pathlib import Path


def check(raw, manifest):
    result = {'stage': raw['stage'], 'state': raw['state'], 'scenarios': {}}
    for run in raw['runs']:
        inputs = next(x for x in manifest['runs'] if x['scenario'] == run['scenario'] and x['repeat'] == run['repeat'])
        # The BYOK manifest stores plan metadata objects. Older manifests used
        # bare UUID strings, so accept both shapes while comparing the photo's
        # persisted plan_id.
        expected_plan = inputs['plans'][1 if run['scenario'] == 'screenshot1' else 0]
        if isinstance(expected_plan, dict):
            expected_plan = expected_plan.get('id')
        scene = result['scenarios'].setdefault(run['scenario'], {'total': 0, 'ready': 0, 'plan_exact': 0, 'summary_nonempty': 0, 'screenshot_facts': []})
        for photo in run.get('photos', []):
            scene['total'] += 1
            scene['ready'] += photo['state'] == 'ready'
            scene['plan_exact'] += photo.get('plan_id') == expected_plan
            scene['summary_nonempty'] += bool((photo.get('summary') or '').strip())
            if run['scenario'] != 'screenshot1':
                continue
            fields = [f for f in photo.get('fields') or [] if f.get('source') == 'screenshot']
            def matches(number, units):
                return any(re.search(r'(?<![\d.])'+number+r'\s*(?:'+units+r')\b',str(f.get('value','')), re.I) for f in fields)
            scene['screenshot_facts'].append({'repeat':run['repeat'],
                'date_exact': photo.get('screenshot_date') == manifest['fixture_date'],
                'distance_and_unit': matches(r'5\.2(?:0)?', r'km|公里|千米'),
                'duration_and_unit': matches('32',r'min|minutes|分钟'),
                'energy_and_unit': matches('315',r'kcal|千卡|大卡'),
                'only_ai_or_screenshot_sources': all(f.get('source') in ['ai','screenshot'] for f in photo.get('fields') or [])})
    result['summary_fact_review'] = 'Manual review required; nonempty is not a factual accuracy claim.'
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('raw',type=Path)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    # The private manifest contains only test-account credentials. Never copy
    # account identifiers/passwords to the public accuracy result.
    result=check(json.loads(args.raw.read_text()), json.loads(args.manifest.read_text()))
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__': main()

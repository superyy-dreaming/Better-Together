#!/usr/bin/env python3
"""Live batch business contract; synthetic account, pixels and recognition results.
No provider call, AI key, private URL or authentication token is logged.
"""
import json
from pathlib import Path
import sys
import uuid
from smoke_support import Client, SmokeError, env_file, private_text, required, require, synthetic_photo

root = Path(__file__).resolve().parents[1]
report = {'scope': 'Synthetic business results, not a model accuracy test'}
try:
    public = json.loads(private_text(root / '.local/client.json'))
    cloud = env_file(root / '.local/cloud.env')
    server = env_file(root / '.local/server.env')
    client = Client(required(public, 'SUPABASE_URL'), required(public, 'SUPABASE_ANON_KEY'),
                    required(cloud, 'SUPABASE_SERVICE_ROLE_KEY'), required(server, 'JOB_SECRET'))
    account = json.loads(private_text(root / '.local/ai-benchmark/byok-smoke-account.json'))
    client.login(account)
    plans = client.action('read_page', collection='plans', limit=100)['items']
    selected = {}
    for category, title in [('study','分组验收学习'),('exercise','分组验收运动')]:
        found = next((p for p in plans if p['title'] == title and p['status'] == 'active'), None)
        if not found:
            client.action('save_plan', title=title, category=category, weekdays=[1,2,3,4,5,6,7],
                          start_time='00:00', deadline='23:50', visibility='private', status='active')
            plans = client.action('read_page', collection='plans', limit=100)['items']
            found = next(p for p in plans if p['title'] == title)
        selected[category] = found['id']
    batch = str(uuid.uuid4())
    photos = []
    for index, category in enumerate(['study', 'exercise', 'study']):
        original, analysis, _, _ = synthetic_photo(client.timezone())
        mid = str(uuid.uuid4())
        recognition = {'photo_id':mid,'status':'ready','origin':'byok','plan_id':selected[category],
                       'confidence':0.95,'summary':f'第 {index+1} 张合成验收照片。','fields':[], 'screenshot_date':None}
        media = client.multipart('media', {'source':'album','photo_id':mid,'batch_id':batch,
                 'recognition_result':json.dumps(recognition)}, {'file':original,'analysis':analysis})
        photos.append((media['id'], category, recognition['summary']))
    before = client.rows('checkins','id',{'batch_id':'eq.'+batch,'user_id':'eq.'+client.owner})
    require(before == [], 'STAMP_BEFORE_CONFIRMATION')
    groups = [{'plan_id':selected[cat],'plan_selection':'ai','media_ids':[p[0] for p in photos if p[1] == cat],
               'summary':'占位句不应覆盖逐图摘要','fields':[],'user_edited':False} for cat in ['study','exercise']]
    args = {'groups':groups,'idempotency_key':batch,'response_version':2}
    result = client.action('submit_checkin_batch', **args)
    require(len(result['checkin_ids']) == 2, 'SPLIT_FAILED')
    require(len(result.get('updated_checkins',[])) == 2, 'UPDATED_RECORDS_MISSING')
    for cid in result['checkin_ids']:
        record = client.action('get_checkin', id=cid)
        relevant = [p for p in photos if selected[p[1]] == record['plan_id']]
        require({p['id'] for p in record['photos']} == {p[0] for p in relevant}, 'PHOTO_GROUP_MISMATCH')
        require(record['summary'] == '\n'.join(p[2] for p in relevant), 'SUMMARY_MISMATCH')
        require(all(p.get('recognition',{}).get('summary') for p in record['photos']), 'PER_PHOTO_SUMMARY_LOST')
        require(all(p['url'].startswith('media:') for p in record['photos']), 'PUBLIC_MEDIA_URL')
    repeated = client.action('submit_checkin_batch', **args)
    require(repeated['checkin_ids'] == result['checkin_ids'], 'DUPLICATE_BATCH')
    report.update(mixed_groups=2, archived_photos=3, before_confirmation='no records',
                  repeat='same IDs', summaries='per-photo and record preserved', private_media='permission-gated references')
    original, analysis, _, _ = synthetic_photo(client.timezone())
    mid, pending_batch = str(uuid.uuid4()), str(uuid.uuid4())
    pending={'photo_id':mid,'origin':'byok','status':'pending','plan_id':None,'confidence':0,
             'summary':'','fields':[],'screenshot_date':None}
    client.multipart('media', {'source':'album','photo_id':mid,'batch_id':pending_batch,
        'recognition_result':json.dumps(pending)}, {'file':original,'analysis':analysis})
    result=client.action('submit_checkin_batch', groups=[{'media_ids':[mid],'plan_id':None,
        'plan_selection':'all','summary':'','fields':[]}], idempotency_key=pending_batch)
    record=client.action('get_checkin', id=result['checkin_ids'][0])
    require(record['status']=='stamped' and record['plan_id'] is None and record['memo_status']=='pending', 'PENDING_BLOCKED')
    report['pending']='ALL stamped, memo pending'
    report['status']='passed'
except SmokeError as error:
    report.update(status='failed', code=error.code)
except Exception as error:
    report.update(status='failed', code=type(error).__name__)
(root / 'output/qa/batch-cloud-smoke.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False))
if report['status'] != 'passed': sys.exit(1)

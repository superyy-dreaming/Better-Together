#!/usr/bin/env python3
"""Current cloud BYOK boundary smoke, synthetic account/evidence only; no AI key."""
import json,uuid,secrets,sys
from pathlib import Path
from smoke_support import Client,SmokeError,env_file,private_text,required,require,synthetic_photo
root=Path(__file__).resolve().parents[1]
report={'stage':'step2','scope':'live cloud business boundary; AI failures separately injected in client tests'}
try:
 public=json.loads(private_text(root/'.local/client.json'));cloud=env_file(root/'.local/cloud.env');server=env_file(root/'.local/server.env')
 c=Client(required(public,'SUPABASE_URL'),required(public,'SUPABASE_ANON_KEY'),required(cloud,'SUPABASE_SERVICE_ROLE_KEY'),required(server,'JOB_SECRET'))
 account=root/'.local/ai-benchmark/byok-smoke-account.json'
 if not account.exists():
  email='byok-smoke-'+secrets.token_hex(6)+'@example.invalid';password=secrets.token_urlsafe(32)
  user=c.call('/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True,'user_metadata':{'nickname':'BYOK 合成边界验收'}},admin=True)
  account.write_text(json.dumps({'TEST_EMAIL':email,'TEST_PASSWORD':password}));account.chmod(0o600)
 c.login(json.loads(private_text(account)))
 try:
  c.rows('ai_settings','user_id',{})
  raise SmokeError('AI_TABLE_STILL_PRESENT')
 except SmokeError as e:
  require(e.code=='HTTP_404','AI_TABLE_CHECK_UNCONFIRMED')
 report['current_ciphertext_table']='absent (404)'
 for action in ['get_ai_settings','save_ai_settings','test_ai_settings','delete_ai_settings']:
  try:c.action(action);raise SmokeError('OLD_ACTION_ACCEPTED')
  except SmokeError as e:require(e.code=='HTTP_409','OLD_ACTION_NOT_RETIRED')
 report['old_settings']='all four rejected (409)'
 try:c.multipart('recognize',{},{});raise SmokeError('OLD_PROXY_ACCEPTED')
 except SmokeError as e:require(e.code=='HTTP_503','OLD_PROXY_NOT_RETIRED')
 report['old_proxy']='pending-compatible upgrade response (503)'
 for kind in ['ai','report']:
  value=c.call('/functions/v1/worker',{'kind':kind},worker=True)
  require(value['data']['reason']=='CLIENT_BYOK_REQUIRED','AI_WORKER_ACTIVE')
 report['server_ai_workers']='both explicitly skipped'
 stamps=[]
 for case in ['no_configuration','pending_provider_failure','pending_timeout']:
  original,analysis,_,_=synthetic_photo(c.timezone());media_id,batch=str(uuid.uuid4()),str(uuid.uuid4())
  pending={'photo_id':media_id,'status':'pending','summary':'','fields':[],'plan_id':None,'confidence':0,'screenshot_date':None,'origin':'byok'}
  photo=c.multipart('media',{'source':'album','batch_id':batch,'photo_id':media_id,'recognition_result':json.dumps(pending)},{'file':original,'analysis':analysis})
  result=c.action('submit_checkin',media_ids=[photo['id']],idempotency_key='byok-smoke-'+batch,response_version=2)
  id=result['checkin_ids'][0];record=c.action('get_checkin',id=id)
  require(record['status']=='stamped' and record['memo_status']=='pending' and record['plan_id'] is None,'PENDING_BLOCKED_STAMP')
  require(record['photos'][0]['recognition']['status']=='pending','PHOTO_RESULT_MISSING')
  repeat=c.action('submit_checkin',media_ids=[photo['id']],idempotency_key='byok-smoke-'+batch,response_version=2)
  require(repeat['checkin_ids']==result['checkin_ids'],'DUPLICATE_STAMP')
  stamps.append({'case':case,'checkin_id':id,'stamp':'saved','memo':'pending','per_photo':'pending','repeat':'idempotent'})
 report['records']=stamps;report['status']='passed'
except SmokeError as e:report.update(status='failed',code=e.code)
except Exception as e:report.update(status='failed',code=type(e).__name__)
(root/'output/ai-byok/step2-business-smoke.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))
if report['status']!='passed':sys.exit(1)

"""Read-only timing and private-media smoke, credentials never logged."""
import json,time,statistics,urllib.request
from pathlib import Path
from smoke_support import Client,private_text,env_file,required,SmokeError,require
root=Path(__file__).resolve().parents[1]
report={}
try:
 config=json.loads(private_text(root/'.local/simulator.json'))
 cloud=env_file(root/'.local/cloud.env');server=env_file(root/'.local/server.env')
 c=Client(required(config,'SUPABASE_URL'),required(config,'SUPABASE_ANON_KEY'),required(cloud,'SUPABASE_SERVICE_ROLE_KEY'),required(server,'JOB_SECRET'));c.login(config)
 for action in ['bootstrap','bootstrap_v2']:
  rows=[]
  for _ in range(3):
   t=time.perf_counter();data=c.action(action);rows.append({'elapsed_ms':round((time.perf_counter()-t)*1000),'json_bytes':len(json.dumps(data,ensure_ascii=False).encode()),'checkins':len(data['checkins']),'photos':sum(len(v['photos']) for v in data['checkins'])})
  report[action]=rows
 page=c.action('read_page',collection='checkins',limit=2)
 require(len(page['items'])<=2,'PAGE_LIMIT')
 if page['next_cursor']:
  page2=c.action('read_page',collection='checkins',limit=2,cursor=page['next_cursor'])
  require(not set(v['id'] for v in page['items']).intersection(v['id'] for v in page2['items']),'CURSOR_DUPLICATE')
 report['pagination']='passed'
 all_page=c.action('read_page',collection='checkins',limit=50)
 photo=next((p for r in all_page['items'] for p in r['photos'] if p['url'].startswith('media:')),None)
 if photo:
  refs=c.action('media_urls',refs=[{'ref':photo['url'],'variant':'original'},{'ref':photo['url'],'variant':'thumbnail'}])['items']
  require(all(v['allowed'] for v in refs),'MEDIA_DENIED')
  # Only the returned private signed URL is fetched, never written to output.
  result=[]
  for item in refs:
   t=time.perf_counter()
   with c.opener.open(item['url'],timeout=30) as response:content=response.read()
   result.append({'variant':item['variant'],'bytes':len(content),'elapsed_ms':round((time.perf_counter()-t)*1000)})
  report['private_media']=result
 plans=c.action('read_page',collection='plans',limit=1)
 if plans['items']: require(c.action('get_plan',id=plans['items'][0]['id'])['id']==plans['items'][0]['id'],'PLAN_DETAIL')
 report['status']='passed'
except SmokeError as e:report['status']='failed';report['code']=e.code
except Exception as e:report['status']='failed';report['code']=type(e).__name__
(root/'output/scoped-cloud-smoke.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False))

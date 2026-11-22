"""Synthetic account only: immutable avatar/evidence, multi-record weekly stamp."""
import json,time,io,uuid,hashlib
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
from smoke_support import Client,private_text,env_file,required,SmokeError,require,synthetic_photo
root=Path(__file__).resolve().parents[1];report={}
try:
 from PIL import Image
 config=json.loads(private_text(root/'.local/simulator.json'));cloud=env_file(root/'.local/cloud.env');server=env_file(root/'.local/server.env')
 c=Client(required(config,'SUPABASE_URL'),required(config,'SUPABASE_ANON_KEY'),required(cloud,'SUPABASE_SERVICE_ROLE_KEY'),required(server,'JOB_SECRET'));c.login(config)
 profile=c.rows('profiles','avatar_url',{'id':'eq.'+c.owner})[0]
 avatar=io.BytesIO();Image.new('RGB',(512,512),'#b9cdae').save(avatar,'JPEG')
 uploaded=c.multipart('media',{'source':'avatar','batch_id':str(uuid.uuid4())},{'file':avatar.getvalue()})
 c.action('save_profile',avatar_url=uploaded['path'])
 require(c.action('bootstrap_v2')['profile']['avatar_url'].startswith('avatar:'),'AVATAR_REF')
 c.action('save_profile',avatar_url=profile['avatar_url'])
 report['avatar_upload_and_reference']='passed; original profile restored'
 zone=c.timezone();day=datetime.now(ZoneInfo(zone)).strftime('%Y-%m-%d')
 existing=c.rows('plans','id',{'user_id':'eq.'+c.owner,'title':'eq.合成验收：每周目标'})
 plan=existing[0]['id'] if existing else c.action('save_plan',schema_version=2,title='合成验收：每周目标',category='study',schedule_kind='weekly_target',weekly_target_days=3,anchor_date=day,weekdays=[1,2,3,4,5,6,7],start_time='00:00',deadline='23:59',visibility='private')['id']
 report['plan_id']=plan
 photos=[];stamps=[]
 for index in range(2):
  original,analysis,_,_=synthetic_photo(zone)
  # Synthetic content has unique pixels; preserve the EXIF supplied by the fixture.
  image=Image.open(io.BytesIO(original));image.thumbnail((1000,800));from PIL import ImageDraw
  draw=ImageDraw.Draw(image)
  if index==0: draw.rectangle((20,20,380,430),fill='#355cac')
  else: draw.ellipse((470,240,940,650),fill='#ed773b')
  stream=io.BytesIO();image.save(stream,'JPEG',exif=image.getexif());original=stream.getvalue()
  image.thumbnail((1600,1600));stream=io.BytesIO();image.save(stream,'JPEG',quality=82);analysis=stream.getvalue()
  photo,batch=str(uuid.uuid4()),str(uuid.uuid4())
  report['pending_identity']={'photo':photo,'batch':batch,'index':index}
  (root/'output/flexible-write-progress.json').write_text(json.dumps(report))
  media=c.multipart('media',{'source':'album','photo_id':photo,'batch_id':batch},{'file':original,'analysis':analysis})
  result=c.action('submit_checkin',media_ids=[media['id']],plan_id=plan,idempotency_key='flexible-smoke-'+batch,response_version=2)
  require(bool(result.get('updated_checkins')),'COMMITTED_RECORD_NOT_RETURNED')
  photos.append(photo);stamps+=result['checkin_ids']
 require(len(set(stamps))==2,'INDEPENDENT_RECORDS')
 progress=c.action('get_plan',id=plan)
 require(progress['weekly_completed']==1,'DAILY_DEDUPLICATION')
 report['same_day_two_records_one_completed_day']='passed'
 c.call('/functions/v1/worker',{'kind':'thumbnail'},worker=True)
 rows=c.rows('media','id,thumbnail_path',{'id':'in.('+','.join(photos)+')'})
 require(all(v['thumbnail_path'] for v in rows),'THUMBNAIL_PENDING')
 report['private_thumbnail_job']='passed'
 refs=c.action('media_urls',refs=[{'ref':'media:'+photos[0],'variant':'thumbnail'},{'ref':'media:'+photos[0],'variant':'original'}])['items']
 sizes={}
 for item in refs:
  with c.opener.open(item['url'],timeout=30) as response:sizes[item['variant']]=len(response.read())
 require(sizes['thumbnail']<sizes['original'],'THUMBNAIL_NOT_SMALLER');report['download_bytes']=sizes
 report.pop('pending_identity',None);report['status']='passed'
except SmokeError as e:report['status']='failed';report['code']=e.code
except Exception as e:report['status']='failed';report['code']=type(e).__name__
(root/'output/flexible-write-smoke.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))

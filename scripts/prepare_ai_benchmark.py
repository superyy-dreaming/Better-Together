#!/usr/bin/env python3
"""Prepare isolated synthetic runs. Never exports an AI credential.

Input manifests are private (0600), outside source, and contain only dedicated
test-account login credentials and public Supabase configuration. Accounts are
kept for audit; this script does not delete or reset any account or record.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import random
import secrets
import sys
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont
from smoke_support import Client, SmokeError, env_file, private_text, required

ROOT = Path(__file__).resolve().parents[1]


def save_private(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    path.chmod(0o600)


def fixtures(folder, day):
    font_path = '/System/Library/Fonts/Supplemental/Arial.ttf'
    def font(size):
        return ImageFont.truetype(font_path, size)
    manifest = []
    # Genuinely different synthetic learning cards, not byte edits of one image.
    titles = ['GEOMETRY', 'BOTANY', 'SOLAR SYSTEM', 'FRACTIONS', 'MUSIC THEORY',
              'MAP READING', 'CHEMISTRY', 'LANGUAGE NOTES', 'PHYSICS']
    for i, title in enumerate(titles):
        rng = random.Random(8031 + i)
        im = Image.new('RGB', (1800, 2400), (235-i*9, 221-i*7, 202+i*4))
        d = ImageDraw.Draw(im)
        x, y = 100 + (i % 3)*180, 130 + (i % 4)*160
        d.rectangle((x,y,x+1060,y+1380), fill=(255,253,245))
        d.text((x+50,y+60), title, font=font(64), fill='#193E33')
        d.text((x+50,y+155), 'Learning notes / synthetic fixture',font=font(36),fill='#34463C')
        for j in range(5):
            cx, cy = x+70+rng.randrange(700), y+270+rng.randrange(800)
            radius = rng.randrange(60,170)
            color = tuple(rng.randrange(30,180) for _ in range(3))
            if (i+j)%2:
                d.ellipse((cx,cy,cx+radius,cy+radius), fill=color)
            else:
                d.rectangle((cx,cy,cx+radius*2,cy+radius), fill=color)
        d.text((x+50,y+1240), f'Visible topic: {title}',font=font(40),fill='#193E33')
        exif=Image.Exif()
        exif[34665]={36867: day.strftime('%Y:%m:%d 08:00:00'), 36881:'+08:00'}
        name=f'photo-{i+1:02}.jpg'
        im.save(folder/name,quality=93,exif=exif)
        manifest.append({'file':name,'source':'album','expected_category':'study','visible_topic':title})
    im=Image.new('RGB',(1200,2000),'#F5F7FA')
    d=ImageDraw.Draw(im)
    d.rectangle((0,0,1200,350),fill='#213C2C')
    d.text((70,70),'RUN SUMMARY',font=font(72),fill='white')
    d.text((70,205),day.strftime('%Y-%m-%d'),font=font(68),fill='white')
    for y,label,value in [(490,'Distance','5.20 km'),(780,'Duration','32 min'),(1070,'Energy','315 kcal')]:
        d.text((80,y),label,font=font(46),fill='#3E5747')
        d.text((80,y+80),value,font=font(102),fill='#172D20')
    d.text((80,1600),'SYNTHETIC TEST DATA',font=font(44),fill='#3E5747')
    im.save(folder/'screenshot.jpg',quality=93)
    manifest.append({'file':'screenshot.jpg','source':'screenshot','expected_category':'exercise',
                     'date':day.strftime('%Y-%m-%d'),'distance_km':5.2,'duration_minutes':32,'calories_burned':315})
    for item in manifest:
        raw=(folder/item['file']).read_bytes()
        item.update(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
    (folder/'fixtures.json').write_text(json.dumps(manifest,indent=2))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--stage',required=True)
    parser.add_argument('--runs',type=int,default=5)
    parser.add_argument('--byok',action='store_true')
    args=parser.parse_args()
    if not args.stage.isalnum() or not 1<=args.runs<=5:
        raise SmokeError('ARGUMENT_INVALID')
    folder=ROOT/'.local'/'ai-benchmark'/args.stage
    if (folder/'input.json').exists():
        raise SmokeError('MANIFEST_EXISTS_DO_NOT_OVERWRITE')
    folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    now=datetime.now(ZoneInfo('Asia/Shanghai'))
    fixtures(folder,now)
    public=json.loads(private_text(ROOT/'.local'/'client.json'))
    cloud=env_file(ROOT/'.local'/'cloud.env')
    c=Client(required(public,'SUPABASE_URL'),required(public,'SUPABASE_ANON_KEY'),
             required(cloud,'SUPABASE_SERVICE_ROLE_KEY'),'')
    cases=[('photo1',['photo-01.jpg'],'album'),('screenshot1',['screenshot.jpg'],'screenshot'),
           ('photo3',[f'photo-{i:02}.jpg' for i in range(1,4)],'album'),
           ('photo9',[f'photo-{i:02}.jpg' for i in range(1,10)],'album')]
    rows=[]
    run_id=secrets.token_hex(6)
    account_path=ROOT/'.local'/'ai-benchmark'/'byok-account.json'
    shared=json.loads(private_text(account_path)) if args.byok and account_path.exists() else None
    for scenario,files,source in cases:
        for repeat in range(1,args.runs+1):
            if shared is None:
                email=f'ai-bench-{run_id}-{scenario}-{repeat}@example.invalid'
                password=secrets.token_urlsafe(30)
                user=c.call('/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True,
                    'user_metadata':{'nickname':'AI 合成基准','benchmark_stage':args.stage}},admin=True)
                account={'email':email,'password':password,'owner':required(user,'id'),'plans':[]}
                c.login({'TEST_EMAIL':email,'TEST_PASSWORD':password})
                for category,title in [('study','学习笔记'),('exercise','跑步记录')]:
                    p=c.action('save_plan',schema_version=2,title=title,category=category,goal='',
                               weekdays=[1,2,3,4,5,6,7],start_time='00:00',deadline='23:59',
                               visibility='private',schedule_kind='weekdays',anchor_date=now.strftime('%Y-%m-%d'))
                    account['plans'].append({'id':p['id'],'category':category})
                if args.byok:
                    shared=account
                    save_private(account_path,shared)
            else:
                account=shared
            row={**account,'scenario':scenario,'repeat':repeat,'files':files,'source':source}
            rows.append(row)
            save_private(folder/'provisioning.json',rows)
            print(f'Prepared {scenario} run {repeat}',flush=True)
    save_private(folder/'input.json',{'stage':args.stage,'byok':args.byok,'auto_start':args.byok,'fixture_date':now.strftime('%Y-%m-%d'),
                  'url':c.base_url,'anon':c.anon,'runs':rows})
    print(f'Ready: {len(rows)} isolated synthetic runs; no AI credentials exported')


if __name__=='__main__':
    try:
        main()
    except SmokeError as error:
        print('Stopped: '+error.code,file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('Stopped: UNEXPECTED_PREPARATION_FAILURE',file=sys.stderr)
        sys.exit(1)

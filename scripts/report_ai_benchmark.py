#!/usr/bin/env python3
"""Summarize timing evidence without summing parallel waits as wall time."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
from statistics import median


def first(events, event, state=None):
    return next((e['elapsed_ms'] for e in events if e['event']==event and
                 (state is None or e.get('state')==state)),None)


def delta(events, start, end):
    a,b=first(events,start),first(events,end)
    return b-a if a is not None and b is not None else None


def intervals(events,start,end):
    pending=defaultdict(list)
    pairs=[]
    for e in events:
        key=e.get('photo',e.get('batch',''))
        if e['event']==start:
            pending[key].append(e['elapsed_ms'])
        if e['event']==end and pending[key]:
            pairs.append((pending[key].pop(0),e['elapsed_ms']))
    return pairs


def union_duration(pairs):
    end=-1
    total=0
    for a,b in sorted(pairs):
        total+=max(0,b-max(a,end))
        end=max(b,end)
    return total if pairs else None


def provider_durations(events):
    """Pair only the same image and request kind (OCR and memo are distinct)."""
    started={}
    completed=defaultdict(list)
    for e in events:
        key=(e.get('photo'),e.get('state'))
        if e['event']=='recognition_sent':
            started[key]=e['elapsed_ms']
        elif e['event']=='recognition_received' and key in started:
            completed[e.get('state','unknown')].append(e['elapsed_ms']-started.pop(key))
    return dict(completed)


def summary(run):
    events=run['events']
    batch=next((e.get('batch') for e in events if e['event']=='picker_returned'),None)
    own_photos={p['id'] for p in run.get('photos',[])}
    events=[e for e in events if e.get('batch')==batch or
            (e.get('batch') is None and e.get('photo') in own_photos)]
    start=first(events,'picker_returned')
    visible=first(events,'photo_visible','ready')
    batch=first(events,'batch_terminal')
    state=Counter(p['state'] for p in run.get('photos',[]))
    sent=[e['elapsed_ms'] for e in events if e['event']=='recognition_sent']
    terminal=[e['elapsed_ms'] for e in events if e['event']=='photo_terminal']
    stamp=run['stamp']
    if stamp=='not_attempted' and first(events,'stamp_start') is not None:
        stamp='unconfirmed'
    request_overhead=[]
    for photo in run.get('photos',[]):
        pe=[e for e in events if e.get('photo')==photo['id']]
        roundtrip=delta(pe,'recognition_sent','recognition_received')
        server=next((e['duration_ms'] for e in pe if e['event']=='server_total'),None)
        if roundtrip is not None and server is not None:
            request_overhead.append(max(0,roundtrip-server))
    return {
        'repeat':run['repeat'],'stamp':stamp,'photo_states':dict(state),
        'archive_count':run.get('archived',0),
        'original_read_ms':union_duration(intervals(events,'original_read_start','original_read_end')),
        'compression_wall_ms':union_duration(intervals(events,'compression_start','compression_end')),
        'first_ready_visible_ms':visible-start if start is not None and visible is not None else None,
        'batch_terminal_ms':batch-start if start is not None and batch is not None else None,
        'request_wall_ms':max(terminal)-min(sent) if sent and terminal else None,
        'archive_wall_ms':union_duration(intervals(events,'archive_start','archive_end')),
        'stamp_request_ms':delta(events,'stamp_start','stamp_end'),
        'pick_to_stamp_ms':delta(events,'picker_returned','stamp_end'),
        'analysis_upload_bytes':sum(e.get('bytes',0) for e in events if e['event']=='recognition_sent'),
        'analysis_requests':len(sent),
        'http_statuses':dict(Counter(str(e['status']) for e in events if e['event']=='recognition_headers')),
        'transport_and_gateway_ms':request_overhead,
        # The memo result is validated after the last response; do not count a
        # screenshot's second network call as parsing of its first OCR response.
        'parse_validation_ms':[
            validated-max(received)
            for photo in own_photos
            if (received:=[e['elapsed_ms'] for e in events if e.get('photo')==photo and e['event']=='recognition_received'])
            and (validated:=first([e for e in events if e.get('photo')==photo], 'recognition_validated')) is not None
        ],
        'provider_durations_ms':provider_durations(events),
        'timeouts':sum(e['event']=='recognition_failed' and e.get('state')=='timeout' for e in events),
        'server_stages_ms':{stage:[e['duration_ms'] for e in events if e['event']==f'server_{stage}']
                            for stage in ['auth','body','image','context','candidates','provider_config','ocr','memo','total']},
    }


def fmt(value,scale=1000):
    return '未取得' if value is None else f'{value/scale:.3f}'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('input',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    raw=json.loads(args.input.read_text())
    groups=defaultdict(list)
    for run in raw['runs']:
        groups[run['scenario']].append(summary(run))
    output={'stage':raw['stage'],'state':raw['state'],'scenarios':{}}
    lines=[f"# 第 {raw['stage']} 阶段 AI 基准实测",'',
           '同一 iPhone Release，固定合成素材。计时起点是选图回调后，不含人工选择与思考时间。',
           '供应商耗时包含供应商网络、排队、模型与响应读取，不能解释为纯模型计算时间。',
           '失败和待补样本保留；成功首图为空表示没有有效结果，不是零耗时。', '',
           '| 场景 | 次数 | 有效图/总图 | 收到盖章确认 | 首张有效结果中位秒 | 整批终态中位秒 | 归档中位秒 | 盖章请求中位秒 | 选图至盖章中位秒 |',
           '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for scenario,runs in groups.items():
        numeric=['original_read_ms','compression_wall_ms','first_ready_visible_ms','batch_terminal_ms',
                 'request_wall_ms','archive_wall_ms','stamp_request_ms','pick_to_stamp_ms','analysis_upload_bytes']
        medians={key:median(values) if (values:=[r[key] for r in runs if r[key] is not None]) else None for key in numeric}
        counts=Counter()
        for r in runs: counts.update(r['photo_states'])
        server={key:median(values) if (values:=[v for r in runs for v in r['server_stages_ms'][key]]) else None
                for key in runs[0]['server_stages_ms']}
        samples={key:sum(r[key] is not None for r in runs) for key in numeric}
        provider_names={key for r in runs for key in r['provider_durations_ms']}
        provider={key:median([v for r in runs for v in r['provider_durations_ms'].get(key,[])]) for key in provider_names}
        output['scenarios'][scenario]={'medians':medians,'measured_samples':samples,'photo_states':dict(counts),'server_request_medians_ms':server,'provider_request_medians_ms':provider,'runs':runs}
        lines.append(f"| {scenario} | {len(runs)} | {counts['ready']}/{sum(counts.values())} | {sum(r['stamp']=='saved' for r in runs)}/{len(runs)} | "+
                     ' | '.join(fmt(medians[k]) for k in ['first_ready_visible_ms','batch_terminal_ms','archive_wall_ms','stamp_request_ms','pick_to_stamp_ms'])+' |')
    lines+=['','分段中位耗时（秒）：','',
            '| 场景 | 原图读取 | 压缩墙钟 | 识别请求墙钟 | 每请求服务端校验 | 每请求上下文读取 | 截图 OCR 调用 | 纪要调用 |',
            '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for scenario,data in output['scenarios'].items():
        m=data['medians'];s=data['server_request_medians_ms']
        lines.append('| '+scenario+' | '+' | '.join(fmt(v) for v in [m['original_read_ms'],m['compression_wall_ms'],m['request_wall_ms'],s['image'],s['context'],s['ocr'],s['memo']])+' |')
    lines+=['','压缩与归档使用实际区间的并集；整批耗时使用墙钟时间。请求中位数与批次中位数分开保存，不能相加。',
            '盖章响应未确认不等于数据库保存失败。缺失时长不填零、不纳入该项中位数；JSON measured_samples 列出每个中位数的有效测量数。',
            '完整逐次数据和服务端分段见同名 JSON。真实 Keep 截图准确率未验证。','']
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.with_suffix('.json').write_text(json.dumps(output,ensure_ascii=False,indent=2))
    args.output.with_suffix('.md').write_text('\n'.join(lines))
    print('\n'.join(lines))


if __name__=='__main__': main()

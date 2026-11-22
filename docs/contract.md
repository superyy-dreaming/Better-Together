# 客户端 / 后端共享契约 v1

All names below are wire names. ISO UTC timestamps; local dates YYYY-MM-DD, weekdays ISO 1–7. Team timezone immutable IANA name. Single active team per user MVP; solo timezone stored profile. Server derives identity from verified JWT.

## Transport
Supabase functions `api` accepts JSON `{action: string, ...args}`. Success `{data: ...}`, error `{error:{code,message}}` with appropriate non-2xx. Functions `media` accepts multipart `{file,source,captured_at?,batch_id}` (source camera/album/screenshot), returns `{data:{id,path,captured_at,source}}`. Server validates stored bytes and computes pHash. Client calls submit only with returned media IDs.

## Snapshot (`action: bootstrap`)
```
{profile:{id,nickname,avatar_url?,timezone,notification_preferences,makeup_remaining},
 team:null|{id,name,timezone,owner_id,streak,members:[{id,nickname,avatar_url?,status}]},
 plans:[{id,title,category,goal,weekdays:[1,2,3,4,5,6,7],start_time,deadline,visibility,status}],
 checkins:[{id,user_id,plan_id?,batch_id,local_date,status,is_makeup,is_late,created_at,summary,memo_status,fields:[],photos:[],nickname,category,likes,comments:[],challenge_count,challenge_threshold}],
 reports:[{id,week_start,kind,summary,title,metrics,highlights,suggestion,shared,refreshed}],
 overdue:[{id,user_id,plan_id,title,nickname,deadline_at,status,poke_count,poked}],
 notifications:[{id,kind,title,body,read,created_at,target_id?}]}
```
Photo `{id,url,source,captured_at,plan_id?,confidence?}`; memo field `{key,label,value,source,confidence?}`. Comments `{id,user_id,nickname,content,is_challenge,created_at}`. Checkin statuses stamped/redo_required/makeup/incomplete; memo_status pending/ready/unavailable. Category study/exercise/food/custom/all. Plan status active/paused/ended. Visibility team/private.

Profile `paused_week` is a boolean for the current fixed-timezone week, `paused_week_start` is nullable ISO date. Checkins include `classification_pending`. Deleted photos awaiting storage cleanup remain in the owner's photos with `url:''` and `cleanup_status:'pending'`; render “原图清理中”, no image. After completion they disappear. Other members never receive deleted photo placeholders. `delete_photo` responds `{deleted:true,cleanup_status:'pending'|'done'}`.

## Actions and arguments
- save_profile: nickname?, avatar_url?, notification_preferences? (all,poke,overdue,report,interaction,challenge), timezone? (solo only)
- create_team: name,timezone; join_team: token; create_invite: no args -> {token,url}; leave_team: no args; manage_team: operation rename/remove/dissolve, name?/member_id?
- save_plan: id?, title,category,goal,weekdays,start_time,deadline,visibility,status; pause_week: paused boolean
- submit_checkin: media_ids[],plan_id? (null=ALL), note?, timer_seconds?, target_date? (makeup/redo only), makeup_reason?, redo_of?, idempotency_key -> checkin IDs; must not wait on OpenAI. Uploaded media batch used once only except idempotent replay.
- edit_memo: checkin_id,summary,fields; reclassify: checkin_id,plan_id -> preserve user edits, 24h server guard.
- assign_batch_fields: checkin_id,target_checkin_id -> owner assigns private `unassigned_fields` and `unassigned_summary` once to a checkin in the same batch; unassigned fields do not contribute to reports. Either can be nonempty independently. Selecting a team-visible card publishes the draft there; show this clearly before the action.
- interact: checkin_id,kind like/comment/challenge,content?; poke: overdue_id
- interact_report: report_id,kind like/comment,content?; reports include likes/liked/comments
- mark_notifications: ids[]; register_device: platform ios/android,token,provider apns/jpush
- unregister_device: token; removes only the calling user's registration, idempotent
- share_report: report_id,method feed/image; refresh_report: report_id; accept_suggestion: report_id
- delete_photo: photo_id; delete_account: confirmation 'DELETE'

## Server jobs (not exposed to end users)
`worker` authorized with JOB_SECRET, kind ai/schedule/push. Claims queued jobs with lease; retry only dependency errors. AI emits JSON schema with photo assignments, summary, sourced fields. AI completion does not downgrade stamped checkins. Does not overwrite user-edited values. Scheduler idempotent per subject+local_date+kind. Push outbox independent of in-app notifications. Bootstrap uses signed short-lived photo URLs.

## Source precedence
User approved plan + session decisions > product rules in README > PDF > HTML demo. HTML fake states and legacy freeze-card copy must not be copied. Date verification is eligibility, not an AI judgment. Screenshot OCR validation occurs before a returned media_id; if date unavailable ask for another image, never call it cheating. Photo capture metadata alone is not cryptographic proof; no facial/geolocation identity claims.

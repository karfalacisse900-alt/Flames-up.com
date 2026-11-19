// Read-only public-content capture for the paired simulator review. The snapshot
// and image bytes stay on the runner; no real user data is committed to Git.
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {discussionSentences} from '../../backend-cf/src/tea-conversations.ts';

const query = `select jsonb_build_object('capturedAt',now(),'notes',jsonb_agg(
 jsonb_build_object('id',c.id,'title',c.title,'body',c.body,'links',c.links,'version',c.version,
 'createdAt',c.created_at,'borough',c.borough,'following',false,'isAuthor',false,'canManageApplications',false,
 'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),u.username),
 'username',u.username,'photoURL',u.avatar_url,'isVerified',u.is_verified)) order by c.created_at desc),
 'replies',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'conversationID',r.conversation_id,
 'body',r.body,'target',r.target,'createdAt',r.created_at,'author',jsonb_build_object('id',a.id,
 'name',coalesce(nullif(a.full_name,''),a.username),'username',a.username,'photoURL',a.avatar_url,
 'isVerified',a.is_verified)) order by r.created_at),'[]') from public.app_tea_replies r
 join public.app_users a on a.id=r.author_id join public.app_tea_conversations p on p.id=r.conversation_id
 join public.app_users pa on pa.id=p.author_id
 where r.status='active' and p.status='active' and coalesce(a.metadata->>'status','active')='active'
 and coalesce(pa.metadata->>'status','active')='active' and pa.is_private=false and a.is_private=false)) snapshot
 from (select * from public.app_tea_conversations where status='active' order by created_at desc limit 4) c
 join public.app_users u on u.id=c.author_id where not coalesce(u.is_private,false)
 and u.is_private=false and coalesce(u.metadata->>'status','active')='active' and c.primary_action is null`;
let snapshot;
async function read(query) {
 const {SUPABASE_PROJECT_REF:ref,SUPABASE_ACCESS_TOKEN:token}=process.env;
 if(!/^[a-z]{20}$/.test(ref??'')||!token) throw Error('Review read credentials missing');
 if(ref!=='cclgvxukwccvtgrbcwie') throw Error('Review project does not match Captro');
 const r=await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`,{
  method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
  body:JSON.stringify({query,read_only:true}),redirect:'error',signal:AbortSignal.timeout(25000)});
 if(!r.ok) {
   const failure=await r.json().catch(()=>({}));
   const message=String(failure.message??failure.error??'').replace(/https?:\S+|Bearer\s+\S+|sbp_\S+/g,'[redacted]').slice(0,250);
   throw Error(`Public review read failed: HTTP ${r.status}: ${message}`);
 }
 return r.json();
}
if(process.argv[2]) snapshot=JSON.parse(readFileSync(process.argv[2],'utf8'));
else {
 snapshot=(await read(query))[0].snapshot;
 snapshot.home=await read(`select p.id,p.app_user_id "userId",u.username "userUsername",u.full_name "userFullName",
 u.avatar_url "userProfileImage",u.is_verified "userIsVerified",p.title,p.content,p.content caption,
 p.post_type "postType",p.created_at "createdAt",p.likes_count "likesCount",p.comments_count "commentsCount",
 (select jsonb_agg(m->>'url') from jsonb_array_elements(p.media) m) images,p.media_dimensions "mediaDimensions",
 p.editor_data->'overlays' "editorOverlays",p.visibility from public.app_posts p
 join public.app_users u on u.id=p.app_user_id where p.visibility='public' and not coalesce(u.is_private,false)
 and p.post_type='general' and p.status='active' and p.editor_data->'moderation'->>'status'='approved'
 and jsonb_array_length(p.media)>0 and p.media->0->>'type'='image'
 and u.is_private=false and coalesce(u.metadata->>'status','active')='active'
 order by (length(coalesce(p.content,''))>0) desc,p.created_at desc limit 3`);
 const owner=snapshot.home[0]?.userId;
 if(!owner||!/^[a-zA-Z0-9_-]+$/.test(owner)) throw Error('Public profile unavailable');
 snapshot.profile=(await read(`select id,username,full_name "fullName",avatar_url "profileImage",bio,city,
 is_verified "isVerified",counts->'followers' "followersCount",counts->'following' "followingCount"
 from public.app_users where id='${owner}' and not coalesce(is_private,false)`))[0];
}
if(!snapshot.notes?.length) throw Error('No public Notes available for comparison');
snapshot.replies=snapshot.replies.filter(r=>snapshot.notes.some(n=>n.id===r.conversationID));
for(const note of snapshot.notes) {
 note.sentences=discussionSentences(note.body,note.version);
 const replies=snapshot.replies.filter(r=>r.conversationID===note.id);
 note.replyCount=replies.length;
 const targets=new Map();
 for(const reply of replies) if(reply.target){
   const key=JSON.stringify(reply.target);
   const group=targets.get(key)??{target:reply.target,count:0}; group.count++;targets.set(key,group);
 }
 note.replyTargets=[...targets.values()];
}
snapshot.images={};
const urls=[...new Set([...snapshot.notes,...snapshot.replies].map(p=>p.author.photoURL)
 .concat((snapshot.home??[]).flatMap(p=>[p.userProfileImage,...(p.images??[])]),snapshot.profile?.profileImage).filter(Boolean))];
for(const url of urls){
 const parsed=new URL(url);
 if(parsed.protocol!=='https:'||!['imagedelivery.net','lh3.googleusercontent.com'].includes(parsed.hostname)) throw Error('Unsupported review image host');
 const r=await fetch(url,{signal:AbortSignal.timeout(25000)});
 if(!r.ok) throw Error(`Review image failed: HTTP ${r.status}`);
 snapshot.images[url]=Buffer.from(await r.arrayBuffer()).toString('base64');
}
const json=JSON.stringify(snapshot);
writeFileSync('ios_native/MIRA/Sources/MIRANative/Screens/CaptroPolishSnapshotPayload.swift',
 '#if DEBUG\nimport Foundation\nenum CaptroPolishSnapshotPayload {\n static let data = Data(base64Encoded: "'+Buffer.from(json).toString('base64')+'")!\n}\n#endif\n');
writeFileSync(process.env.RUNNER_TEMP?`${process.env.RUNNER_TEMP}/polish-snapshot-proof.json`:'polish-snapshot-proof.json',
 JSON.stringify({capturedAt:snapshot.capturedAt,notes:snapshot.notes.length,replies:snapshot.replies.length,sha256:createHash('sha256').update(json).digest('hex'),source:'read-only public Captro records'},null,2));
console.log(`Captured ${snapshot.notes.length} public Notes once for both renders; personal data omitted from logs.`);

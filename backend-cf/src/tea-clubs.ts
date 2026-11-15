import { discussionLinks, DiscussionInputError } from './tea-conversations.ts';
import { readFeedCursor, writeFeedCursor, FeedCursorError } from './feed-pagination.ts';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const reads = new Set(['overview','messages','message','links','members','invites','inviteRequests']);
const fields: Record<string,string[]> = {
 send:['id','body','room','quote'], read:['message','room'], saveLink:['id','title','url','message'],
 editLink:['id','title','url','version'], removeLink:['id','version'], createRoom:['id','name','announcements'],
 pin:['message','version'], settings:['rules','links','version'], createInvite:['id','expires','approval'],
 revokeInvite:['id'], decideInvite:['id','user','approve'], removeMember:['user'], memberRole:['user','role'],
};
export function clubInput(action:string, raw:any) {
 if (!fields[action] || !raw || typeof raw!=='object' || Array.isArray(raw) || Object.keys(raw).some(k=>!fields[action].includes(k))) throw new DiscussionInputError('Invalid club action.');
 const data={...raw};
 for(const key of fields[action]) {
   if (['room','quote','message'].includes(key) && data[key]==null) continue;
   if (['id','room'].includes(key) && !uuid.test(data[key]??'')) throw new DiscussionInputError('Invalid identity.');
   if (['id','room'].includes(key)) data[key]=data[key].toLowerCase();
   if (['quote','message','user'].includes(key) && (typeof data[key]!=='string'||! /^[a-zA-Z0-9_-]{1,120}$/.test(data[key]))) throw new DiscussionInputError('Invalid target.');
   if (['announcements','approval','approve'].includes(key) && typeof data[key]!=='boolean') throw new DiscussionInputError('Choose an option.');
   if (key==='version' && (!Number.isSafeInteger(data[key])||data[key]<1)) throw new DiscussionInputError('Refresh before changing this item.');
   if (['body','title','name','rules'].includes(key)) {
     const max=key==='body'?2000:key==='rules'?8000:key==='name'?60:100;
     if(typeof data[key]!=='string'||[...data[key]].length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(data[key])||(key!=='rules'&&!data[key].trim())) throw new DiscussionInputError('Check the '+key+'.');
     data[key]=data[key].trim();
   }
 }
 if(fields[action].includes('url')) data.url=discussionLinks([data.url])[0];
 if(fields[action].includes('links')) data.links=discussionLinks(data.links);
 if(fields[action].includes('role')&&!['admin','member'].includes(data.role)) throw new DiscussionInputError('Invalid role.');
 if(fields[action].includes('expires')&&(typeof data.expires!=='string'||!Number.isFinite(Date.parse(data.expires)))) throw new DiscussionInputError('Choose a valid expiry.');
 return data;
}
async function digest(raw:string) {return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
async function inviteToken(secret:string,creator:string,club:string,id:string) {
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(JSON.stringify(['tea-invite',creator,club,id]))))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
type Deps={auth:any;viewer:(c:any)=>Promise<string>;rpc:(c:any,name:string,body:any)=>Promise<any>;limit:(c:any,write:boolean)=>Promise<any>;restriction:(c:any)=>Promise<any>;site:(path:string)=>string};
export function mountTeaClubs(api:any,deps:Deps) {
 async function handle(c:any,action:string) {
  c.header('Cache-Control','private, no-store');
  try {
   const write=!reads.has(action);const limited=await deps.limit(c,write);if(limited)return limited;
   const viewer=await deps.viewer(c);if(!viewer)return c.json({detail:'Sign in to open this club.'},401);
   if(write){const denied=await deps.restriction(c);if(denied)return denied;}
   const id=(c.req.param('id')??'').toLowerCase();if(!uuid.test(id))throw new DiscussionInputError('Invalid club.');
   let data:any=write?clubInput(action,await c.req.json()):{};
   const room=c.req.query('room')?.toLowerCase();if(room&&!uuid.test(room))throw new DiscussionInputError('Invalid room.');
   if(reads.has(action)&&room)data.room=room;
   if(action==='message')data.message=c.req.param('message');
   if(action==='members')data.after=c.req.query('after')??'';
   if(action==='messages')data.through=c.req.query('through');
   if ([data.message,data.after,data.through].some(v=>v && !/^[a-zA-Z0-9_-]{1,120}$/.test(v))) throw new DiscussionInputError('Invalid target.');
   if(data.through&&c.req.query('cursor'))throw new DiscussionInputError('Choose a message or a page.');
   let cursor:any;
   if(['messages','links','invites','inviteRequests'].includes(action)) {
    cursor=await readFeedCursor(c.env.JWT_SECRET,c.req.query('cursor'),{viewer,scope:'tea-club-'+action,city:id+':'+(room??'general')});
    if(cursor.boundary){data.before=cursor.boundary.createdAt;data.boundary=cursor.boundary.id;}
   }
   let token:string|undefined;
   if(action==='saveLink' && data.message) {
    const source=await deps.rpc(c,'captro_tea_club',{p_actor:viewer,p_club:id,p_action:'message',p_data:{message:data.message}});
    const candidates=typeof source?.[0]?.body==='string'?source[0].body.match(/https:\/\/[^\s<>"']+/g)??[]:[];
    if(!candidates.some((raw:string)=>{
      try { return discussionLinks([raw])[0]===data.url || discussionLinks([raw.replace(/[.,;!?)\]}]+$/,'')])[0]===data.url; } catch { return false; }
    })) throw new DiscussionInputError('This link does not belong to that message.');
   }
   if(action==='createInvite'){token=await inviteToken(c.env.JWT_SECRET,viewer,id,data.id);data.hash=await digest(token);}
   let value=await deps.rpc(c,'captro_tea_club',{p_actor:viewer,p_club:id,p_action:action,p_data:data});
   if(action==='invites') value=await Promise.all(value.map(async(i:any)=>{
    const token=await inviteToken(c.env.JWT_SECRET,i.created_by,id,i.id);
    const {token_hash,...safe}=i;
    // A signing-key rotation must never produce a plausible but invalid invite.
    return {...safe,url:await digest(token)===token_hash?deps.site('tea-invite/'+token):null};
   }));
   if(cursor){
    const items=value.slice(0,50),last=items.at(-1);
    const nextCursor=value.length>50&&last?await writeFeedCursor(c.env.JWT_SECRET,{...cursor,boundary:{id:last.id,createdAt:last.createdAt??last.created_at,legacyCreatedAt:null}}):null;
    return c.json({items:action==='messages'?items.reverse():items,nextCursor});
   }
   if(action==='members')return c.json({items:value.slice(0,50),nextCursor:value.length>50?value[49].id:null});
   if(action==='createInvite')return c.json({...value,url:deps.site('tea-invite/'+token)});
   if(action==='send'||action==='message')return value[0]?c.json(value[0]):c.json({detail:'Message unavailable.'},404);
   return c.json(value);
  } catch(e){return failure(c,e);}
 }
 for(const action of reads) {
  const path=action==='overview'?'/tea/clubs/:id':action==='message'?'/tea/clubs/:id/messages/:message':'/tea/clubs/:id/'+action;
  api.get(path,deps.auth,(c:any)=>handle(c,action));
 }
 for(const action of Object.keys(fields))api.post('/tea/clubs/:id/'+action,deps.auth,(c:any)=>handle(c,action));
 for(const method of ['get','post'])api[method]('/tea/club-invites/:token',deps.auth,async(c:any)=>{
  c.header('Cache-Control','private, no-store');
  try{
   const limited=await deps.limit(c,method==='post');if(limited)return limited;
   const token=c.req.param('token');if(!/^[a-f0-9]{64}$/.test(token))throw new Error('TEA_INVITE_INVALID');
   const viewer=await deps.viewer(c);if(!viewer)return c.json({detail:'Sign in to open this invitation.'},401);
   if(method==='post'){const denied=await deps.restriction(c);if(denied)return denied;}
   return c.json(await deps.rpc(c,'captro_tea_invite',{p_actor:viewer,p_hash:await digest(token),p_accept:method==='post'}));
  }catch(e){return failure(c,e);}
 });
}
function failure(c:any,error:unknown) {
 if(error instanceof DiscussionInputError||error instanceof FeedCursorError)return c.json({detail:error.message},400);
 const message=error instanceof Error?error.message:'';
 for(const [key,status,detail] of [
 ['TEA_CLUB_FORBIDDEN',403,'You do not have access to this club action.'],['TEA_CLUB_UNAVAILABLE',404,'This club or item is unavailable.'],
 ['TEA_CLUB_CONFLICT',409,'This item changed. Refresh before trying again.'],['TEA_CLUB_INVALID',400,'Check the details and try again.'],
 ['TEA_INVITE_INVALID',404,'This invitation is invalid.'],['TEA_INVITE_REVOKED',410,'This invitation was revoked.'],['TEA_INVITE_EXPIRED',410,'This invitation expired.'],
 ] as const)if(message.includes(key))return c.json({code:key,detail},status);
 return c.json({detail:'Could not load or save this club. Try again.'},503);
}

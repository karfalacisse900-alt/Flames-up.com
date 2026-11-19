import { discussionLinks, DiscussionInputError } from './tea-conversations.ts';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function badgeInput(action: string, value: any) {
  const submit = action === 'submit';
  const allowed = submit ? ['id','version','display_name','reason','links'] : ['id','version','message','note'];
  if (!value || Array.isArray(value) || Object.keys(value).some(k => !allowed.includes(k)) ||
      !uuid.test(value.id ?? '') || !Number.isSafeInteger(value.version) || value.version < 0) throw Error('BADGE_INVALID');
  const text = (key: string, min: number, max: number) => {
    const s = value[key] ?? '';
    if (typeof s !== 'string' || s.trim().length < min || [...s].length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(s)) throw Error('BADGE_INVALID');
    return s.trim();
  };
  return {id:value.id, version:value.version, ...(submit
    ? {displayName:text('display_name',1,120),reason:text('reason',10,1500),links:discussionLinks(value.links)}
    : {message:text('message',3,1500),note:text('note',0,2000)})};
}
type Deps = {auth:any; actor(c:any):string; admin(c:any,write:boolean):Promise<void>; limit(c:any):Promise<any>;
  rpc(c:any,name:string,body:any):Promise<any>; query(c:any,table:string,options:any):Promise<any[]>; eq(v:string):string};
export function mountAccountBadges(api:any,d:Deps) {
  const safe = (row:any) => { if (!row) return null; const {decided_by,...rest}=row; return rest; };
  const wrap = (fn:any) => async(c:any) => {
    c.header('Cache-Control','private, no-store');
    try { return await d.limit(c) || await fn(c); }
    catch(error) {
      const message=String((error as Error)?.message || '');
      const status=message.includes('FORBIDDEN')?403:message.includes('CONFLICT')?409:error instanceof DiscussionInputError||error instanceof SyntaxError||message.includes('INVALID')||message.includes('HTTPS')?400:503;
      return c.json({detail:status===403?'This account cannot perform this action.':status===409?'This application changed. Refresh before trying again.':status===400?'Check the application fields and HTTPS links.':'Could not complete verification. Try again.',code:'BADGE_REQUEST_FAILED'},status);
    }
  };
  api.get('/verification/me',d.auth,wrap(async(c:any)=>{
    const actor=d.actor(c);
    const [rows,users]=await Promise.all([
      d.query(c,'app_badge_applications',{filters:{user_id:d.eq(actor)},limit:1}),
      d.query(c,'app_users',{select:'is_verified',filters:{id:d.eq(actor)},limit:1})]);
    return c.json({application:safe(rows[0]),is_verified:users[0]?.is_verified===true});
  }));
  api.post('/verification/apply',d.auth,wrap(async(c:any)=>{
    const {id,...data}=badgeInput('submit',await c.req.json());
    return c.json(await d.rpc(c,'captro_badge_mutate',{p_actor:d.actor(c),p_target:d.actor(c),p_action:'submit',p_id:id,p_data:data}));
  }));
  api.get('/admin/verification',d.auth,wrap(async(c:any)=>{
    await d.admin(c,false);
    const status=c.req.query('status')||'under_review', offset=Number(c.req.query('offset')||0);
    if (!['under_review','approved','needs_changes','declined','revoked'].includes(status)||!Number.isSafeInteger(offset)||offset<0||offset>100000) throw Error('BADGE_INVALID');
    const rows=await d.query(c,'app_badge_applications',{filters:{status:d.eq(status)},order:'updated_at.asc,user_id.asc',offset,limit:26});
    return c.json({items:rows.slice(0,25),nextOffset:rows.length>25?offset+25:null});
  }));
  api.get('/admin/verification/:id',d.auth,wrap(async(c:any)=>{
    await d.admin(c,false);
    const target=c.req.param('id');
    const [rows,history]=await Promise.all([
      d.query(c,'app_badge_applications',{filters:{user_id:d.eq(target)},limit:1}),
      d.query(c,'app_badge_audit',{filters:{target_id:d.eq(target)},order:'created_at.desc',limit:50})]);
    return c.json({application:rows[0]??null,history});
  }));
  api.post('/admin/verification/:target/:action',d.auth,wrap(async(c:any)=>{
    await d.admin(c,true);
    const action=c.req.param('action');
    if (!['approve','request_changes','decline','revoke'].includes(action)) throw Error('BADGE_INVALID');
    const {id,...data}=badgeInput(action,await c.req.json());
    return c.json(await d.rpc(c,'captro_badge_mutate',{p_actor:d.actor(c),p_target:c.req.param('target'),p_action:action,p_id:id,p_data:data}));
  }));
}

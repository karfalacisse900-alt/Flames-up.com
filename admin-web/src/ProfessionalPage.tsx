import {useEffect,useRef,useState} from 'react';
import {request} from './api';
import './professional.css';
type Row={user_id:string;role:string;status:string;version:number;public_data:{displayName:string;category:string;description:string;area:string;pickup:boolean;links:string[]};applicant_message:string;reviewer_message:string};
type Detail={application:Row;role:Row|null;history:{id:string;actor_id:string;action:string;reason:string;internal_note:string;created_at:string;result:{ok?:boolean;error?:string}}[]};
const label=(value:string)=>value.replaceAll('_',' ');
export function ProfessionalPage({token,canWrite}:{token:string;canWrite:boolean}){
 const [status,setStatus]=useState(new URLSearchParams(location.search).get('applicationStatus')||'under_review');
 const [offset,setOffset]=useState(0),[items,setItems]=useState<Row[]>(),[next,setNext]=useState<number|null>(null),[selected,setSelected]=useState<Row>(),[detail,setDetail]=useState<Detail>();
 const [error,setError]=useState(''),[detailError,setDetailError]=useState(''),[refresh,setRefresh]=useState(0),[busy,setBusy]=useState(false);
 const [action,setAction]=useState(''),[reason,setReason]=useState(''),[message,setMessage]=useState(''),[note,setNote]=useState('');
 const operation=useRef<{key:string;id:string} | undefined>(undefined);
 useEffect(()=>{let alive=true;setError('');setItems(undefined);request<{items:Row[];nextOffset:number|null}>(`/admin/professional?status=${status}&offset=${offset}`,token).then(r=>{if(alive){setItems(r.items);setNext(r.nextOffset);}}).catch(e=>{if(alive)setError(e.message);});return()=>{alive=false;};},[token,status,offset,refresh]);
 useEffect(()=>{let alive=true;setDetail(undefined);setDetailError('');setAction('');if(selected)request<Detail>(`/admin/professional/${encodeURIComponent(selected.user_id)}/${selected.role}`,token).then(d=>{if(alive)setDetail(d);}).catch(e=>{if(alive)setDetailError(e.message);});return()=>{alive=false;};},[token,selected,refresh]);
 const changeStatus=(value:string)=>{setStatus(value);setOffset(0);const url=new URL(location.href);url.searchParams.set('applicationStatus',value);history.replaceState(null,'',url);};
 async function decide(){
  if(!selected||!detail||busy)return;
  const version=['suspend','restore','remove'].includes(action)?detail.role!.version:detail.application.version;
  const data={version,reason,message,note};const key=JSON.stringify([selected.user_id,selected.role,action,data]);
  if(operation.current?.key!==key)operation.current={key,id:crypto.randomUUID()};
  setBusy(true);setDetailError('');
  try{await request(`/admin/professional/${encodeURIComponent(selected.user_id)}/${selected.role}/${action}`,token,{method:'POST',body:JSON.stringify({...data,id:operation.current.id})});setAction('');setReason('');setMessage('');setNote('');setRefresh(x=>x+1);}
  catch(e){setDetailError((e as Error).message+' If the response was lost, retry this same decision to reconcile its outcome.');}
  finally{setBusy(false);}
 }
 return <div className="professional-grid">
  <section className="console-panel professional-panel"><h2>Professional applications</h2><label>Application status<select value={status} onChange={e=>changeStatus(e.target.value)}>{['under_review','needs_changes','approved','declined','draft'].map(s=><option key={s} value={s}>{label(s)}</option>)}</select></label>
   {error?<div role="alert">{error}<button onClick={()=>setRefresh(x=>x+1)}>Retry</button></div>:!items?<p role="status">Loading applications…</p>:!items.length?<p>No applications with this status.</p>:<ul className="professional-list">{items.map(row=><li key={row.user_id+row.role}><button aria-pressed={selected?.user_id===row.user_id&&selected?.role===row.role} onClick={()=>setSelected(row)}><strong>{row.public_data.displayName||'Untitled draft'}</strong><span>{row.role==='creator'?'Creator / Gig':'Business'} · {label(row.status)}</span><small>{row.user_id}</small></button></li>)}</ul>}
   <div className="professional-actions"><button disabled={!offset} onClick={()=>setOffset(Math.max(0,offset-25))}>Previous</button><button disabled={next===null} onClick={()=>setOffset(next!)}>Next</button></div>
  </section>
  <section className="console-panel professional-panel" aria-label="Application inspector">
   {!selected?<p>Select an application to review.</p>:<><h2>{selected.public_data.displayName}</h2>{detailError&&<p role="alert">{detailError}<button onClick={()=>setRefresh(x=>x+1)}>Reload application</button></p>}{!detail&&!detailError?<p role="status">Loading application…</p>:detail&&<>
    <p>{label(detail.application.public_data.category)} · {detail.role?label(detail.role.status):label(detail.application.status)}</p><p>{detail.application.public_data.description}</p>
    {detail.application.public_data.area&&<p>Operating area: {detail.application.public_data.area} · Pickup: {detail.application.public_data.pickup?'Yes':'No'}</p>}
    <div className="professional-actions">{detail.application.public_data.links.map(url=><a key={url} href={url} target="_blank" rel="noopener noreferrer">{new URL(url).hostname}</a>)}</div>
    {detail.application.applicant_message&&<><h3>Applicant message · private</h3><p>{detail.application.applicant_message}</p></>}
    {detail.application.reviewer_message&&<><h3>Message shown to applicant</h3><p>{detail.application.reviewer_message}</p></>}
    {canWrite&&<div className="professional-actions">{(detail.application.status==='under_review'?['request_changes','approve','decline']:detail.role?.status==='active'?['suspend','remove']:detail.role?['restore',...(detail.role.status==='removed'?[]:['remove'])]:[]).map(a=><button key={a} onClick={()=>setAction(a)}>{label(a)}</button>)}</div>}
    {action&&<form onSubmit={e=>{e.preventDefault();void decide();}} className="professional-form"><h3>Confirm {label(action)} · {selected.role}</h3><p>This affects only this professional role. Existing transactions, regular posts and the other role are preserved. Approval does not enable Support payments.</p><label>Decision reason<input required maxLength={800} value={reason} onChange={e=>setReason(e.target.value)}/></label><label>Message to applicant<textarea required={action!=='approve'} maxLength={1500} value={message} onChange={e=>setMessage(e.target.value)}/></label><label>Internal note · admin only<textarea maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></label><div className="professional-actions"><button type="button" disabled={busy} onClick={()=>setAction('')}>Cancel</button><button disabled={busy}>{busy?'Saving…':'Confirm decision'}</button></div></form>}
    <h3>Protected decision history</h3><ol className="professional-history">{detail.history.map(item=><li key={item.id}><strong>{label(item.action)} · {item.result.ok?'Confirmed':'Failed'}</strong><small>{new Date(item.created_at).toLocaleString()} · {item.actor_id}</small><p>{item.reason}</p>{item.internal_note&&<p>Internal: {item.internal_note}</p>}</li>)}</ol>
   </>}</>}
  </section>
 </div>;
}

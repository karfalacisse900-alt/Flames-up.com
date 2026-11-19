import { useEffect, useRef, useState } from "react";
import { request } from "./api";
import { safePreviewURL } from "./console-state";
import "./professional.css";
type Application = {user_id:string;display_name:string;reason:string;links:string[];status:string;version:number;reviewer_message:string};
type Detail = {application:Application|null;history:{id:string;actor_id:string;action:string;created_at:string;request:{data:{message?:string;note?:string}}}[]};
const label=(s:string)=>s.replaceAll("_"," ");
export function VerificationPage({token,canWrite}:{token:string;canWrite:boolean}) {
  const [status,setStatus]=useState("under_review"),[offset,setOffset]=useState(0),[next,setNext]=useState<number|null>(null);
  const [rows,setRows]=useState<Application[]>(),[selected,setSelected]=useState<string>(),[detail,setDetail]=useState<Detail>();
  const [error,setError]=useState(""),[detailError,setDetailError]=useState(""),[refresh,setRefresh]=useState(0),[busy,setBusy]=useState(false);
  const [action,setAction]=useState(""),[message,setMessage]=useState(""),[note,setNote]=useState("");
  const operation=useRef<{key:string;id:string}|undefined>(undefined);
  useEffect(()=>{let alive=true;setRows(undefined);setError("");
    request<{items:Application[];nextOffset:number|null}>(`/admin/verification?status=${status}&offset=${offset}`,token)
      .then(r=>{if(alive){setRows(r.items);setNext(r.nextOffset);}}).catch(e=>{if(alive)setError(e.message);});
    return()=>{alive=false;};},[token,status,offset,refresh]);
  useEffect(()=>{let alive=true;setDetail(undefined);setDetailError("");setAction("");setMessage("");setNote("");
    if(selected) request<Detail>(`/admin/verification/${encodeURIComponent(selected)}`,token).then(r=>{if(alive)setDetail(r);}).catch(e=>{if(alive)setDetailError(e.message);});
    return()=>{alive=false;};},[token,selected,refresh]);
  async function decide(){
    if(busy||!detail?.application||!selected||!action)return;
    const data={version:detail.application.version,message,note},key=JSON.stringify([selected,action,data]);
    if(operation.current?.key!==key)operation.current={key,id:crypto.randomUUID()};
    setBusy(true);setDetailError("");
    try{await request(`/admin/verification/${encodeURIComponent(selected)}/${action}`,token,{method:"POST",body:JSON.stringify({...data,id:operation.current.id})});setRefresh(x=>x+1);}
    catch(e){setDetailError((e as Error).message+" Retry the same decision to reconcile an uncertain response.");}
    finally{setBusy(false);}
  }
  return <div className="professional-grid">
    <section className="console-panel professional-panel"><h2>Account verification</h2>
      <p>Review account identity and supporting links. This badge grants no professional role, payment capability or access entitlement.</p>
      <label>Status<select disabled={busy} value={status} onChange={e=>{setStatus(e.target.value);setOffset(0);setSelected(undefined);}}>{["under_review","needs_changes","approved","declined","revoked"].map(s=><option key={s} value={s}>{label(s)}</option>)}</select></label>
      {error?<p role="alert">{error}<button onClick={()=>setRefresh(x=>x+1)}>Retry</button></p>:!rows?<p role="status">Loading applications…</p>:!rows.length?<p>No applications with this status.</p>:<ul className="professional-list">{rows.map(r=><li key={r.user_id}><button disabled={busy} aria-pressed={selected===r.user_id} onClick={()=>setSelected(r.user_id)}><strong>{r.display_name}</strong><span>{label(r.status)}</span><small>{r.user_id}</small></button></li>)}</ul>}
      <div className="professional-actions"><button disabled={busy||offset===0} onClick={()=>setOffset(Math.max(0,offset-25))}>Previous</button><button disabled={busy||next===null||!rows} onClick={()=>setOffset(next!)}>Next</button></div>
    </section>
    <section className="console-panel professional-panel" aria-label="Verification application">
      {detailError&&<p role="alert">{detailError}<button disabled={busy} onClick={()=>setRefresh(x=>x+1)}>Reload application</button></p>}
      {!selected?<p>Select an application.</p>:!detail?<p role="status">Loading application…</p>:!detail.application?<p>Application no longer available.</p>:<>
        <h2>{detail.application.display_name}</h2><p>{detail.application.reason}</p>
        <ul>{detail.application.links.map(url=><li key={url}><a href={safePreviewURL(url)} target="_blank" rel="noopener noreferrer">{url}</a></li>)}</ul>
        <p>Status: {label(detail.application.status)}</p>{detail.application.reviewer_message&&<p>Applicant message: {detail.application.reviewer_message}</p>}
        {canWrite&&["under_review","approved"].includes(detail.application.status)&&<fieldset disabled={busy}>
          <legend>Review decision</legend><label>Action<select value={action} onChange={e=>setAction(e.target.value)}><option value="">Choose action</option>{(detail.application.status==="approved"?["revoke"]:["approve","request_changes","decline"]).map(s=><option value={s} key={s}>{label(s)}</option>)}</select></label>
          <label>Message visible to applicant<textarea maxLength={1500} value={message} onChange={e=>setMessage(e.target.value)}/></label>
          <label>Private reviewer note<textarea maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></label>
          <button disabled={!action||message.trim().length<3} onClick={decide}>{busy?"Saving…":"Save decision"}</button>
        </fieldset>}
        <h3>Review history</h3>{detail.history.map(h=><article key={h.id}><strong>{label(h.action)}</strong><p>{h.actor_id} · {new Date(h.created_at).toLocaleString()}</p>{h.request.data.message&&<p>Applicant message: {h.request.data.message}</p>}{h.request.data.note&&<p>Private note: {h.request.data.note}</p>}</article>)}
      </>}
    </section>
  </div>;
}

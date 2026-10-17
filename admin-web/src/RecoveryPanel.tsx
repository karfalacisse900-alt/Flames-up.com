import {useEffect,useRef,useState} from 'react';
import {AdminApi} from './api';
import {formatProviderMoney} from '../../backend-cf/src/currency';
export type RecoveryCase={purchaseId:string;amount:number;currency:string;purchaseStatus:string;status:string;decision:string|null;
 providerStatus:string;paymentId:string;mode:string;observedAt:string;events:Array<{operator:string;event:string;decision:string;note:string;at:string}>};
export type RecoveryQueue={cases:Array<{purchaseId:string;status:string;decision:string|null;owner:string|null;attempts:number;createdAt:string;lastAttemptAt:string|null}>;
 alerts:Array<{purchaseId:string;outcome:string;attempts:number;firstSeenAt:string;nextAttemptAt:string}>;actionsEnabled:boolean};
export function RecoveryPanel({token,canResolve}:{token:string;canResolve:boolean}) {
 const [queue,setQueue]=useState<RecoveryQueue|null>(null),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const [busy,setBusy]=useState(false),[refresh,setRefresh]=useState(0),[selected,setSelected]=useState('');
 const [decision,setDecision]=useState<'fulfill'|'refund'>('fulfill'),[note,setNote]=useState('');
 const generation=useRef(0);
 const [caseView,setCaseView]=useState<RecoveryCase|null>(null);
 useEffect(()=>{let current=true;setCaseView(null);if(selected)AdminApi.paymentRecoveryCase(token,selected)
  .then(value=>{if(current)setCaseView(value);}).catch(()=>{if(current)setError('Provider verification unavailable. No decision can be submitted.');});
  return()=>{current=false;};
 },[token,selected]);
 useEffect(()=>{const current=++generation.current;setQueue(null);setSelected('');setNote('');setError('');setNotice('');setBusy(false);
  AdminApi.paymentRecovery(token).then(value=>{if(generation.current===current)setQueue(value);})
   .catch(()=>{if(generation.current===current)setError('Recovery queue unavailable. Retry; no case is marked resolved.');});
  return()=>{generation.current++;};
 },[token,refresh]);
 async function resolve() {
  if(busy||!selected||caseView?.purchaseId!==selected||note.trim().length<10||!canResolve||!queue?.actionsEnabled)return;
  if(!window.confirm(decision==='refund'?'Authorize a full refund for this reviewed case?':'Authorize fulfillment only if availability and capacity still permit it?'))return;
  const current=generation.current;setBusy(true);setError('');setNotice('');
  try{const result=await AdminApi.resolvePaymentRecovery(token,selected,{decision,note});
   if(current!==generation.current)return;
   setNotice(result.status==='refund_pending'?'Refund is pending with the provider. This case is NOT resolved. Recheck after its lease expires.':`Recovery ${result.status}. Refresh to verify the updated queue.`);
  }catch{if(current===generation.current)setError('Recovery is not complete. Check provider state, case ownership and the audit trail before retrying.');}
  finally{if(current===generation.current)setBusy(false);}
 }
 return <section className="panel"><h2>Payment recovery</h2>
  <p>First 100 unresolved cases and reconciliation alerts. A received payment is not fulfilled merely because it appears here. Existing purchase snapshots remain unchanged.</p>
  <button disabled={busy} onClick={()=>setRefresh(x=>x+1)}>Reload recovery queue</button>
  {error&&<p role="alert">{error}</p>}{notice&&<p role="status">{notice}</p>}
  {!queue&&!error&&<p role="status">Loading recovery cases…</p>}
  {queue&&<><p>{queue.cases.length} cases shown · {queue.alerts.length} scheduling alerts shown</p>
   {!queue.actionsEnabled&&<p>Actions are disabled pending the approved coordinated rollout.</p>}
   <ul>{queue.cases.map(item=><li key={item.purchaseId}><code>{item.purchaseId}</code> · {item.status} · {item.attempts} attempts · Owner: {item.owner??'Unassigned'} · Decision: {item.decision??'Undecided'}
    <button disabled={busy} onClick={()=>{setSelected(item.purchaseId);setDecision(item.decision==='refund'?'refund':'fulfill');setNote('');setError('');}}>Review case</button></li>)}</ul>
   <ul>{queue.alerts.map(item=><li key={item.purchaseId}>Reconciliation <code>{item.purchaseId}</code>: {item.outcome} · {item.attempts} attempts · First seen {new Date(item.firstSeenAt).toLocaleString()} · Next attempt {new Date(item.nextAttemptAt).toLocaleString()}</li>)}</ul>
  </>}
  {selected&&<fieldset disabled={busy}><legend>Review {selected}</legend>
   {caseView?<><p>{caseView.mode.toUpperCase()} · {formatProviderMoney(caseView.amount,caseView.currency)} · Purchase: {caseView.purchaseStatus} · Provider: {caseView.providerStatus}</p>
    <p>Provider reference: <code>{caseView.paymentId}</code> · Checked {new Date(caseView.observedAt).toLocaleString()}</p>
    <details><summary>Recorded decisions and attempts</summary><ul>{caseView.events.map((event,i)=><li key={i}>{event.at} · {event.operator} · {event.event} · {event.decision}: {event.note}</li>)}</ul></details>
   </>:<p role="status">Verifying provider state…</p>}
   <p>Verify the provider transaction and the buyer’s request first. Fulfillment rechecks capacity. Refund handles only an unfulfilled, released purchase and never creates access.</p>
   <label>Decision <select value={decision} onChange={e=>setDecision(e.target.value as 'fulfill'|'refund')}><option value="fulfill">Fulfill if available</option><option value="refund">Full refund</option></select></label>
   <label>Review note <textarea value={note} maxLength={1000} onChange={e=>setNote(e.target.value)}/></label>
   <p>Do not include card details, credentials or private messages in the note. Ownership and the decision are recorded server-side. Uncertain responses remain open.</p>
   <button disabled={busy||!canResolve||!queue?.actionsEnabled||caseView?.purchaseId!==selected||note.trim().length<10} onClick={()=>void resolve()}>Confirm reviewed decision</button>
   <button onClick={()=>setSelected('')}>Cancel</button>
  </fieldset>}
 </section>;
}

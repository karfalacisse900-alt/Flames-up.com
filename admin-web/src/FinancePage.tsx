import {useEffect,useState} from 'react';
import {AdminApi,ApiError} from './api';
import {RecoveryPanel} from './RecoveryPanel';
import type {FinanceSummary,FinanceRecord,FinanceOrder,CreatorSupportEnrollment} from './types';
import {formatProviderMoney as money} from '../../backend-cf/src/currency';
const supportApprovalReady=(readiness:CreatorSupportEnrollment['readiness'])=>readiness.status==='ready'||readiness.blockers.every(blocker=>blocker.code==='rollout_disabled');
const categories=[['event','Events'],['club','Clubs'],['meetup','Meetups'],['deal','Deals'],['group_access','Group access'],['local_offer','Local offers'],['creator_support','Creator support']] as const;
// Ledger release is not proof of a currently withdrawable Stripe balance.
function Totals({row}:{row:FinanceRecord}){return <dl className="finance-totals"><div><dt>Pending</dt><dd>{money(row.pending,row.currency)}</dd></div><div><dt>Released / unpaid</dt><dd>{money(row.available,row.currency)}</dd></div><div><dt>Paid out to date</dt><dd>{money(row.paid_out,row.currency)}</dd></div></dl>;}
export function FinancePage({token,canResolve=false,canRelease=false,canManageSupport=false}:{token:string;canResolve?:boolean;canRelease?:boolean;canManageSupport?:boolean}){
 const [summary,setSummary]=useState<FinanceSummary|null>(null);
 const [selection,setSelection]=useState<{category:string;currency:string;objectId?:string;sellerId?:string}|null>(null);
 const [records,setRecords]=useState<FinanceRecord[]>([]);
 const [orderId,setOrderId]=useState<string|null>(null);
 const [order,setOrder]=useState<FinanceOrder|null>(null);
 const [offset,setOffset]=useState(0),[next,setNext]=useState<number|null>(null);
 const [refresh,setRefresh]=useState(0),[loading,setLoading]=useState(false),[error,setError]=useState('');
 const [releaseNote,setReleaseNote]=useState(''),[releaseBusy,setReleaseBusy]=useState(false),[releaseMessage,setReleaseMessage]=useState('');
 const [supportCreatorId,setSupportCreatorId]=useState(''),[supportReason,setSupportReason]=useState('');
 const [supportEnrollment,setSupportEnrollment]=useState<CreatorSupportEnrollment|null>(null);
 const [supportEnrollmentBusy,setSupportEnrollmentBusy]=useState(false),[supportEnrollmentError,setSupportEnrollmentError]=useState(''),[supportEnrollmentMessage,setSupportEnrollmentMessage]=useState('');
 useEffect(()=>{let current=true;setError('');setLoading(true);
  const load=async()=>{
   try{
    if(orderId){const result=await AdminApi.financeOrder(token,orderId,offset);if(current){setOrder(result);setNext(result.nextOffset);}}
    else if(selection){const q=new URLSearchParams({...selection,offset:String(offset)});const result=await AdminApi.financeRecords(token,'?'+q);if(current){setRecords(result.items);setNext(result.nextOffset);}}
    else{const result=await AdminApi.financePools(token);if(current){setSummary(result);setNext(null);}}
   }catch(e){if(current){setError(e instanceof Error?e.message:'Could not load funds.');if(e instanceof ApiError&&[401,403].includes(e.status)){setSummary(null);setOrder(null);setRecords([]);setNext(null);}}}
   finally{if(current)setLoading(false);}
  };void load();return()=>{current=false;};
 },[token,selection,orderId,offset,refresh]);
 function openCategory(category:string,currency:string){setOrderId(null);setOrder(null);setRecords([]);setSelection({category,currency});setOffset(0);}
 function back(){setOffset(0);setOrder(null);setRecords([]);setReleaseNote('');setReleaseMessage('');if(orderId)setOrderId(null);else if(selection?.objectId)setSelection({category:selection.category,currency:selection.currency});else setSelection(null);}
 async function loadSupportEnrollment(){
  if(supportEnrollmentBusy)return;setSupportEnrollmentBusy(true);setSupportEnrollmentError('');setSupportEnrollmentMessage('');
  try{const result=await AdminApi.creatorSupportEnrollment(token,supportCreatorId.trim());setSupportEnrollment(result);}
  catch(e){setSupportEnrollment(null);setSupportEnrollmentError(e instanceof Error?e.message:'Could not load creator approval state.');}
  finally{setSupportEnrollmentBusy(false);}
 }
 async function setSupportApproval(enabled:boolean){
  if(supportEnrollmentBusy||!supportEnrollment||!canManageSupport||supportReason.trim().length<10)return;
  if(enabled&&!supportApprovalReady(supportEnrollment.readiness))return;
  const action=enabled?'approve this creator for one-time Support':'pause Support for this creator';
  if(!window.confirm('Confirm: '+action+' in '+supportEnrollment.mode.toUpperCase()+' mode? This changes eligibility only; no payment or transfer is made.'))return;
  setSupportEnrollmentBusy(true);setSupportEnrollmentError('');setSupportEnrollmentMessage('');
  try{const result=await AdminApi.setCreatorSupportEnrollment(token,supportEnrollment.creator.id,{enabled,expectedReviewedAt:supportEnrollment.reviewedAt,reason:supportReason.trim()});
   setSupportEnrollment(result);setSupportReason('');setSupportEnrollmentMessage(enabled?'Creator approved for the current mode.':'Creator Support paused for the current mode.');
  }catch(e){setSupportEnrollmentError((e instanceof Error?e.message:'Approval was not confirmed.')+' Reload current state before retrying.');}
  finally{setSupportEnrollmentBusy(false);}
 }
 async function approveSupportRelease(){
  if(releaseBusy||!canRelease||!orderId||order?.order.category!=='creator_support'||order.order.purchase?.status!=='confirmed'||order.order.purchase.transferId||releaseNote.trim().length<10)return;
  if(!window.confirm(`Approve a ${order.order.purchase?.stripeMode?.toUpperCase()??'Stripe'} transfer of the confirmed creator net to this creator’s existing Stripe account? The creator’s normal payout flow remains separate.`))return;
  setReleaseBusy(true);setReleaseMessage('');
  try{const result=await AdminApi.releaseEarning(token,orderId,{releaseAfter:new Date().toISOString(),note:releaseNote.trim()});
   setReleaseMessage(result.status==='transferred'?'Stripe transfer confirmed to the creator’s existing connected account. Refreshing the ledger…':'Release review recorded. Refresh to confirm the current transfer state.');
   setReleaseNote('');setRefresh(x=>x+1);
  }catch(e){setReleaseMessage((e instanceof Error?e.message:'Release was not confirmed.')+' Reload this order and verify its transfer status before retrying.');}
  finally{setReleaseBusy(false);}
 }
 return <section className="page">
  <div className="page-header"><div><span className="eyebrow">Private finance reporting</span><h1>Captro Funds</h1><p>Virtual categories, not bank accounts. Stripe cash and seller earnings are reported separately.</p></div><button className="secondary-button" disabled={loading} onClick={()=>setRefresh(x=>x+1)}>Refresh</button></div>
  {error&&<p role="alert" className="error-banner">{error}</p>}
  {!selection&&canManageSupport&&<section className="panel support-enrollment-review">
   <h2>Creator Support approval</h2><p>Approve one creator at a time for the current Stripe mode. The server rechecks account readiness; this does not charge or move funds.</p>
   <label>Canonical creator ID<input value={supportCreatorId} onChange={e=>setSupportCreatorId(e.target.value)} maxLength={36} autoComplete="off" placeholder="Creator account ID" /></label>
   <button className="secondary-button" disabled={supportEnrollmentBusy||supportCreatorId.trim().length<1} onClick={()=>void loadSupportEnrollment()}>{supportEnrollmentBusy?'Checking…':'Check creator'}</button>
   {supportEnrollmentError&&<p role="alert" className="error-banner">{supportEnrollmentError}</p>}
   {supportEnrollment&&<div aria-live="polite"><p>Creator: {supportEnrollment.creator.username?('@'+supportEnrollment.creator.username):'Username unavailable'} · {supportEnrollment.mode.toUpperCase()} mode · {supportEnrollment.enabled?'Approved':'Not approved'}</p>
    <p>Readiness: {supportEnrollment.readiness.status}</p>{!supportEnrollment.checkoutEnabled&&<p className="muted">Global checkout remains off. This creator approval records eligibility only; customers still cannot pay until the server rollout is separately enabled.</p>}
    {supportEnrollment.readiness.blockers.map(b=><p key={b.code} className="muted">{b.message}</p>)}
    <label>Review reason<textarea value={supportReason} maxLength={800} onChange={e=>setSupportReason(e.target.value)} placeholder="Record why this creator is approved or paused…" /></label>
    <div className="header-actions"><button className="primary-button" disabled={supportEnrollmentBusy||supportEnrollment.enabled||!supportApprovalReady(supportEnrollment.readiness)||supportReason.trim().length<10} onClick={()=>void setSupportApproval(true)}>Approve Support</button>
     <button className="secondary-button" disabled={supportEnrollmentBusy||!supportEnrollment.enabled||supportReason.trim().length<10} onClick={()=>void setSupportApproval(false)}>Pause Support</button></div>
   </div>}
   {supportEnrollmentMessage&&<p role="status">{supportEnrollmentMessage}</p>}
  </section>}
  {!selection&&<RecoveryPanel token={token} canResolve={canResolve}/>}
  {loading&&<p role="status">Updating finance records…</p>}
  {selection&&<button className="ghost-button" onClick={back}>← Back</button>}
  {!selection&&summary&&<>
   <section className="panel"><h2>Stripe-tracked platform funds</h2><p>{summary.mode.toUpperCase()} · Read {new Date(summary.asOf).toLocaleString()}</p>
    <p>Released / unpaid is an accounting allocation, not a guarantee of payout eligibility. Paid out is historical and is not current cash.</p>{summary.platform?<><p>Actual platform balances. These are not the same as seller earnings and must not be added to the category totals.</p>{summary.platform.available.map(x=><p key={'a'+x.currency}>Stripe available: {money(x.amount,x.currency)}</p>)}{summary.platform.pending.map(x=><p key={'p'+x.currency}>Stripe pending: {money(x.amount,x.currency)}</p>)}</>:<p>Stripe balance unavailable. Accounting records remain below; refresh to retry.</p>}
   </section>
   <div className="finance-grid">{categories.map(([category,label])=><section className="panel" key={category}><h2>{label}</h2>{summary.pools.filter(x=>x.category===category).map(row=><div key={row.currency}><p>{row.currency} · {row.orders} orders</p><p>Gross less refunds: {money(row.gross,row.currency)}</p><Totals row={row}/><button className="secondary-button" onClick={()=>openCategory(category,row.currency)}>View records</button></div>)}{!summary.pools.some(x=>x.category===category)&&<p>No recorded earnings.</p>}</section>)}</div>
   {summary.pools.filter(x=>x.category==='unassigned').map(row=><section className="panel" key={row.currency}><h2>Reconciliation required</h2><p>Legacy or unmatched movements have not been assigned to a category. They are not silently included in another seller or category.</p><Totals row={row}/><button onClick={()=>openCategory(row.category,row.currency)}>Review unassigned movements</button></section>)}
  </>}
  {selection&&!orderId&&<section className="panel"><h2>{selection.category.replaceAll('_',' ')} · {selection.currency}</h2>{records.length===0&&!loading&&!error&&<p>No records.</p>}{records.map((row,i)=><article className="finance-record" key={row.order_id??row.object_id??i}>
   <h3>{row.title??row.item_title??'Unassigned movement'}</h3><p>Seller: <code>{row.seller_id}</code> · {row.orders??1} order(s)</p><p>Gross less refunds: {money(row.gross,row.currency)}</p><Totals row={row}/>
   {row.order_id?<button onClick={()=>{setOrderId(row.order_id!);setOrder(null);setOffset(0);}}>View order</button>:row.object_id?<button onClick={()=>{setSelection({...selection,objectId:row.object_id!,sellerId:row.seller_id});setRecords([]);setOffset(0);}}>View orders</button>:<p>Source-order attribution requires reconciliation.</p>}
  </article>)}</section>}
  {orderId&&order&&<section className="panel"><h2>{order.order.item_title}</h2><p>Order: <code>{orderId}</code></p><p>Buyer: <code>{order.order.buyer_id}</code></p><p>Seller: <code>{order.order.seller_id}</code></p><Totals row={order.order}/><p>Payment: <code>{order.order.stripe_payment_intent_id??'Unavailable'}</code></p><p>Transfer: <code>{order.order.stripe_transfer_id??order.order.purchase?.transferId??'Not transferred'}</code></p><p>Platform fee: {order.order.captro_fee==null?'Not yet known':money(order.order.captro_fee,order.order.currency)} · Processing: {order.order.processing_fee==null?'Not yet known':money(order.order.processing_fee,order.order.currency)}</p>
   {order.order.category==='creator_support'&&<section className="panel support-release-review"><h3>Support release review</h3><p>Creator Support is a separate per-creator ledger category, not a separate Stripe bank balance. Approval releases this confirmed net amount to the creator’s existing connected Stripe account. Their normal payout flow may combine categories.</p><p>Payment state: {order.order.purchase?.status??'Unknown'} · Mode: {(order.order.purchase?.stripeMode??order.order.stripe_mode??'unknown').toUpperCase()} · Creator net after actual processor fees: {order.order.processing_fee==null?'Pending fee verification':money(Math.max(0,order.order.gross-(order.order.captro_fee??0)-order.order.processing_fee),order.order.currency)} · Actual processing fee: {order.order.processing_fee==null?'Verified by Stripe before transfer':money(order.order.processing_fee,order.order.currency)}</p>{order.order.purchase?.transferId?<p role="status">Stripe transfer recorded: <code>{order.order.purchase.transferId}</code></p>:order.order.purchase?.status!=='confirmed'?<p>Only a webhook-confirmed successful payment can be released.</p>:!order.order.purchase?.supportReleaseEnabled?<p>Support releases are disabled for this Stripe environment.</p>:<><label>Review reason (required)<textarea value={releaseNote} maxLength={500} onChange={e=>setReleaseNote(e.target.value)} placeholder="Confirm the provider payment and release basis…"/></label><button className="primary-button" disabled={!canRelease||releaseBusy||releaseNote.trim().length<10} onClick={()=>void approveSupportRelease()}>{releaseBusy?'Verifying with Stripe…':'Approve and release Support earnings'}</button>{!canRelease&&<p>This administrator role can view finance records but cannot release funds.</p>}</>}{releaseMessage&&<p role="status">{releaseMessage}</p>}</section>}
   <div className="table-wrap"><table><caption>Immutable order ledger</caption><thead><tr><th>Date</th><th>Movement</th><th>Account</th><th>Amount</th><th>Stripe reference</th></tr></thead><tbody>{order.entries.map(x=><tr key={x.id}><td>{new Date(x.created_at).toLocaleString()}</td><td>{x.event_type}</td><td>{x.account}</td><td>{money(x.amount,x.currency)}</td><td><code>{x.stripe_object_id??'—'}</code></td></tr>)}</tbody></table></div>
  </section>}
  {selection&&<div className="header-actions"><button disabled={offset===0||loading} onClick={()=>setOffset(Math.max(0,offset-(orderId?100:50)))}>Previous</button><button disabled={next===null||loading} onClick={()=>next!==null&&setOffset(next)}>Next</button></div>}
 </section>;
}

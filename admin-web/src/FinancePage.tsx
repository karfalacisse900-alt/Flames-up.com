import {useEffect,useState} from 'react';
import {AdminApi,ApiError} from './api';
import type {FinanceSummary,FinanceRecord,FinanceOrder} from './types';
const categories=[['event','Events'],['club','Clubs'],['meetup','Meetups'],['deal','Deals'],['group_access','Group access'],['local_offer','Local offers']] as const;
function money(amount:number,currency:string){
 const formatter=new Intl.NumberFormat(undefined,{style:'currency',currency});
 return Number.isSafeInteger(amount)?formatter.format(amount/10**(formatter.resolvedOptions().maximumFractionDigits??2)):'Amount unavailable';
}
// Ledger release is not proof of a currently withdrawable Stripe balance.
function Totals({row}:{row:FinanceRecord}){return <dl className="finance-totals"><div><dt>Pending</dt><dd>{money(row.pending,row.currency)}</dd></div><div><dt>Released / unpaid</dt><dd>{money(row.available,row.currency)}</dd></div><div><dt>Paid out to date</dt><dd>{money(row.paid_out,row.currency)}</dd></div></dl>;}
export function FinancePage({token}:{token:string}){
 const [summary,setSummary]=useState<FinanceSummary|null>(null);
 const [selection,setSelection]=useState<{category:string;currency:string;objectId?:string;sellerId?:string}|null>(null);
 const [records,setRecords]=useState<FinanceRecord[]>([]);
 const [orderId,setOrderId]=useState<string|null>(null);
 const [order,setOrder]=useState<FinanceOrder|null>(null);
 const [offset,setOffset]=useState(0),[next,setNext]=useState<number|null>(null);
 const [refresh,setRefresh]=useState(0),[loading,setLoading]=useState(false),[error,setError]=useState('');
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
 function back(){setOffset(0);setOrder(null);setRecords([]);if(orderId)setOrderId(null);else if(selection?.objectId)setSelection({category:selection.category,currency:selection.currency});else setSelection(null);}
 return <section className="page">
  <div className="page-header"><div><span className="eyebrow">Private finance reporting</span><h1>Captro Funds</h1><p>Virtual categories, not bank accounts. Stripe cash and seller earnings are reported separately.</p></div><button className="secondary-button" disabled={loading} onClick={()=>setRefresh(x=>x+1)}>Refresh</button></div>
  {error&&<p role="alert" className="error-banner">{error}</p>}
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
  {orderId&&order&&<section className="panel"><h2>{order.order.item_title}</h2><p>Order: <code>{orderId}</code></p><p>Buyer: <code>{order.order.buyer_id}</code></p><p>Seller: <code>{order.order.seller_id}</code></p><Totals row={order.order}/><p>Payment: <code>{order.order.stripe_payment_intent_id??'Unavailable'}</code></p><p>Transfer: <code>{order.order.stripe_transfer_id??'Not transferred'}</code></p><p>Platform fee: {order.order.captro_fee==null?'Not yet known':money(order.order.captro_fee,order.order.currency)} · Processing: {order.order.processing_fee==null?'Not yet known':money(order.order.processing_fee,order.order.currency)}</p>
   <div className="table-wrap"><table><caption>Immutable order ledger</caption><thead><tr><th>Date</th><th>Movement</th><th>Account</th><th>Amount</th><th>Stripe reference</th></tr></thead><tbody>{order.entries.map(x=><tr key={x.id}><td>{new Date(x.created_at).toLocaleString()}</td><td>{x.event_type}</td><td>{x.account}</td><td>{money(x.amount,x.currency)}</td><td><code>{x.stripe_object_id??'—'}</code></td></tr>)}</tbody></table></div>
  </section>}
  {selection&&<div className="header-actions"><button disabled={offset===0||loading} onClick={()=>setOffset(Math.max(0,offset-(orderId?100:50)))}>Previous</button><button disabled={next===null||loading} onClick={()=>next!==null&&setOffset(next)}>Next</button></div>}
 </section>;
}

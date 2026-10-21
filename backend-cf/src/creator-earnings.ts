// Creator-owned projections of the existing ledger. Never a second wallet.
export const EARNING_CATEGORIES = ['event','club','meetup','creator_support','deal','group_access','local_offer','unassigned'] as const;
const standard = EARNING_CATEGORIES.slice(0,4);
export class EarningsError extends Error {
  status: number;
  constructor(message: string, status = 400) { super(message); this.status = status; }
}
function units(value: unknown): number {
  const amount = Number(value);
  if (value == null || !Number.isSafeInteger(amount)) throw new EarningsError('EARNINGS_AMOUNT_INVALID',503);
  return amount;
}
export function poolPayload(row: any) {
  return { category: row.category, currency: row.currency, transactions: units(row.transactions ?? 1),
    grossReceived: units(row.gross_received), refunded: units(row.refunded), captroFee: units(row.captro_fee),
    processingFees: row.processing_fee == null ? null : units(row.processing_fee),
    creatorNet: row.creator_net == null ? null : units(row.creator_net), pending: units(row.pending),
    available: units(row.available), paidOut: units(row.paid_out), held: units(row.held) };
}
export function creatorPools(rows: any[], currency: string) {
  const actual = rows.map(poolPayload);
  // Zero is asserted only after a successful authoritative query, not on failure.
  for (const category of standard) if (!actual.some(r=>r.category===category && r.currency===currency)) {
    actual.push({category,currency,transactions:0,grossReceived:0,refunded:0,captroFee:0,
      processingFees:0,creatorNet:0,pending:0,available:0,paidOut:0,held:0});
  }
  return actual.sort((a,b)=>EARNING_CATEGORIES.indexOf(a.category)-EARNING_CATEGORIES.indexOf(b.category)||a.currency.localeCompare(b.currency));
}
export function earningsPage(query: Record<string,string>) {
  if (Object.keys(query).some(k=>!['currency','offset','limit','section'].includes(k))) throw new EarningsError('EARNINGS_FILTER_INVALID');
  if (!/^[A-Z]{3}$/.test(query.currency || '')) throw new EarningsError('EARNINGS_CURRENCY_REQUIRED');
  if (!/^\d{1,6}$/.test(query.offset ?? '0') || !/^\d{1,2}$/.test(query.limit ?? '25')) throw new EarningsError('EARNINGS_PAGE_INVALID');
  const offset = Number(query.offset ?? 0), limit = Number(query.limit ?? 25);
  if (limit<1 || limit>50 || offset>100000) throw new EarningsError('EARNINGS_PAGE_INVALID');
  const section = query.section ?? 'transactions';
  if (!['transactions','payouts'].includes(section)) throw new EarningsError('EARNINGS_PAGE_INVALID');
  return { currency:query.currency,offset,limit,section };
}
type Services = {
  identity(c:any):Promise<{sellerId:string,mode:string,currency:string}>;
  limit(c:any):Promise<Response|null>;
  query(c:any,table:string,options:any):Promise<any[]>;
  eq(value:string):string;
  readiness(c:any,sellerId:string):Promise<any>;
};
export function registerCreatorEarningsRoutes(api:any,auth:any,s:Services) {
  const guard = (fn:(c:any)=>Promise<Response>)=>async(c:any)=>{
    c.header('Cache-Control','private, no-store');
    try { const limited=await s.limit(c); return limited ?? await fn(c); }
    catch(error) { return c.json({code:error instanceof EarningsError?error.message:'EARNINGS_READ_FAILED',
      detail:'Could not load earnings. Your recorded balance has not changed.'},error instanceof EarningsError?error.status:503); }
  };
  api.get('/commerce/earnings/pools',auth,guard(async c=>{
    if(Object.keys(c.req.query()).length) throw new EarningsError('EARNINGS_FILTER_INVALID');
    const who=await s.identity(c);
    const filters={seller_id:s.eq(who.sellerId),stripe_mode:s.eq(who.mode)};
    const rows=await s.query(c,'app_creator_finance_pools',{filters,limit:100});
    return c.json({mode:who.mode,payoutScope:'creator_currency_all_categories_fifo',
      pools:creatorPools(rows,who.currency)});
  }));
  api.get('/commerce/earnings/support-readiness',auth,guard(async c=>{
    if(Object.keys(c.req.query()).length) throw new EarningsError('EARNINGS_FILTER_INVALID');
    const who=await s.identity(c);
    const readiness=await s.readiness(c,who.sellerId).catch(()=>({status:'unavailable',blockers:[],retryable:true}));
    return c.json(readiness);
  }));
  api.get('/commerce/earnings/pools/:category',auth,guard(async c=>{
    const category=c.req.param('category');
    if(!EARNING_CATEGORIES.includes(category)) throw new EarningsError('EARNINGS_CATEGORY_INVALID');
    const page=earningsPage(c.req.query()),who=await s.identity(c);
    const filters={seller_id:s.eq(who.sellerId),stripe_mode:s.eq(who.mode),category:s.eq(category),currency:s.eq(page.currency)};
    const payout=page.section==='payouts';
    const rows=await s.query(c,payout?'app_creator_finance_payouts':'app_creator_finance_orders',{
      filters,order:payout?'created_at.desc,payout_id.desc':'created_at.desc,earning_id.desc',offset:page.offset,limit:page.limit+1});
    const items=rows.slice(0,page.limit).map(row=>payout?{
      id:row.payout_id,status:row.status,createdAt:row.created_at,paidAt:row.paid_at,arrivalAt:row.arrival_at,
      attributedAmount:units(row.attributed_amount),payoutAmount:units(row.payout_amount),
      payoutFee:row.payout_fee==null?null:units(row.payout_fee),currency:row.currency,
    }:{id:row.earning_id,purchaseId:row.order_id,title:row.item_title,status:row.status,createdAt:row.created_at,
      purchasedAt:row.purchased_at,...poolPayload(row)});
    return c.json({category,currency:page.currency,section:page.section,items,
      nextOffset:rows.length>page.limit?page.offset+page.limit:null});
  }));
}

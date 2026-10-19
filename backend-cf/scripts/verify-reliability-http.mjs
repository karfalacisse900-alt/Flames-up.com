const base='https://flames-up-api.karfalacisse900.workers.dev/api';
for(const [method,path] of [['GET','/users/me/follow-requests?paged=1'],['POST','/notifications/mark-read'],
 ['POST','/messages'],['GET','/admin/dashboard'],['POST','/commerce/purchases']]) {
 const r=await fetch(base+path,{method,headers:method==='POST'?{'Content-Type':'application/json'}:{},
 body:method==='POST'?'{}':undefined,signal:AbortSignal.timeout(20000)});
 if(r.status!==401)throw Error(`${method} ${path}: expected anonymous denial, got ${r.status}`);
 console.log('PASS anonymous denial:',method,path);
}

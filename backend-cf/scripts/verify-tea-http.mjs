import assert from 'node:assert/strict';
const base='https://flames-up-api.karfalacisse900.workers.dev/api';
for(const path of ['/tea/conversations','/tea']) {
  const r=await fetch(base+path,{signal:AbortSignal.timeout(20000)});
  assert.equal(r.status,200,path);const b=await r.json();assert.ok(Array.isArray(b.items));
  // Deliberately log no post contents, links, account IDs or personal data.
  console.log('PASS: '+path+' returns a typed page.');
}
const r=await fetch(base+'/tea/conversations',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(20000)});
assert.equal(r.status,401,'Anonymous writes must be denied');
console.log('PASS: anonymous conversation creation denied.');

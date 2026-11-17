import assert from 'node:assert/strict';
const base='https://flames-up-api.karfalacisse900.workers.dev/api';
for(const path of ['/tea/conversations','/tea']) {
  const r=await fetch(base+path,{signal:AbortSignal.timeout(20000)});
  assert.equal(r.status,200,path);const b=await r.json();assert.ok(Array.isArray(b.items));
  if(path==='/tea/conversations' && process.argv.includes('--require-author-photos')) {
    for(const item of b.items) {
      assert.ok(Object.hasOwn(item.author??{},'photoURL'),'Tea response is missing the deployed photo field');
      assert.ok(item.author.photoURL===null || typeof item.author.photoURL==='string','Invalid Tea photo reference');
    }
    console.log(JSON.stringify({authorPhotoContract:true,returnedAuthors:b.items.length,
      withPhoto:b.items.filter(item=>!!item.author.photoURL).length}));
  }
  // Deliberately log no post contents, links, account IDs or personal data.
  console.log('PASS: '+path+' returns a typed page.');
}
const r=await fetch(base+'/tea/conversations',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(20000)});
assert.equal(r.status,401,'Anonymous writes must be denied');
console.log('PASS: anonymous conversation creation denied.');

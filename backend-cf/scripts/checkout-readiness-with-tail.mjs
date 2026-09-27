// Observe only the synthetic read failure. Never print raw tail request headers/body.
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import assert from 'node:assert/strict';
assert.equal(process.env.GITHUB_ACTIONS,'true');
const tail=spawn('./node_modules/.bin/wrangler',['tail','--env','production','--format','json','--search','commerce_post_read_failed'],{cwd:'backend-cf',stdio:['ignore','pipe','pipe']});
let output='';
tail.stdout.on('data',chunk=>{if(output.length<1024*1024)output+=chunk.toString()});
tail.stderr.on('data',()=>{}); // CLI may include environment details; don't print them.
let tailError=false;
tail.on('error',()=>{tailError=true});
try {
 await new Promise(r=>setTimeout(r,6000));
 if(tail.exitCode!==null||tailError)console.log(JSON.stringify({event:'checkout_tail_unavailable'}));
 const run=spawn(process.execPath,['backend-cf/scripts/production-checkout-readiness.mjs'],{stdio:'inherit'});
 const [code]=await once(run,'exit');
 await new Promise(r=>setTimeout(r,2000));
 process.exitCode=code;
} finally {
 tail.kill('SIGTERM');
 // Decode balanced JSON records, ignoring CLI banners. Output only allowlisted diagnostics.
 let start=-1,depth=0,quoted=false,escape=false;
 for(let i=0;i<output.length;i++){
  const c=output[i];
  if(start<0){if(c==='{'){start=i;depth=1;}continue;}
  if(quoted){if(escape)escape=false;else if(c==='\\')escape=true;else if(c==='"')quoted=false;continue;}
  if(c==='"')quoted=true;else if(c==='{')depth++;else if(c==='}')depth--;
  if(depth!==0)continue;
  try {
   const item=JSON.parse(output.slice(start,i+1));
   for(const log of item.logs||[])for(const message of log.message||[]){
    let data;try{data=JSON.parse(message)}catch{continue;}
    if(data.event==='commerce_post_read_failed')console.log(JSON.stringify({event:data.event,stage:data.stage,code:data.code,diagnostic:data.diagnostic,requestId:data.request_id}));
   }
  }catch{}
  start=-1;
 }
}

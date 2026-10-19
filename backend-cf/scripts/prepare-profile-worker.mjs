import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import ts from 'typescript';
import assert from 'node:assert/strict';
// Build a narrowly scoped release artifact; never edit the candidate checkout.
const candidate=resolve(process.argv[2]);
const baseline=resolve(process.argv[3]);
assert.notEqual(candidate,baseline);
const source=readFileSync(candidate,'utf8');
const original=readFileSync(baseline,'utf8');
const functions=new Set(['supabasePublicUserPayload','supabaseFollowStats','supabaseBlockPair','supabaseBlockedUserIds','supabaseSetFollowState','supabaseAppUserToLegacyUser','safeUserPayload','authUserPayload']);
const routes=new Set(['put /users/me','get /users/:userId','get /users/:userId/posts','get /users/:userId/showcase','put /users/me/showcase','get /users/me/follow-requests','post /users/me/follow-requests/:requesterId']);
function nodes(text){
 const ast=ts.createSourceFile('index.ts',text,ts.ScriptTarget.Latest,true);
 const found=new Map();
 for(const n of ast.statements){
  let key;
  if(ts.isFunctionDeclaration(n)&&functions.has(n.name?.text))key=n.name.text;
  if(ts.isExpressionStatement(n)&&ts.isCallExpression(n.expression)){
   const c=n.expression; const head=c.expression.getText(ast);
   if(head.startsWith('api.')&&ts.isStringLiteral(c.arguments[0])){
    const r=head.slice(4)+' '+c.arguments[0].text;if(routes.has(r))key=r;
   }
  }
  if(key){assert(!found.has(key),'Duplicate '+key);found.set(key,{start:n.getStart(ast),end:n.end,text:n.getText(ast)});}
 }
 return found;
}
const from=nodes(source),to=nodes(original);
assert.equal(from.size,functions.size+routes.size,'Missing scoped production code');
let result=original;
for(const [key,n] of [...to].sort((a,b)=>b[1].start-a[1].start)){
 result=result.slice(0,n.start)+from.get(key).text+result.slice(n.end);
}
const additions=[...from].filter(([key])=>!to.has(key));
assert(additions.every(([key])=>routes.has(key)),'Missing baseline function');
// Hono routes must be registered before the app mounts api.
const marker="api.get('/users/:userId',";
assert(result.includes(marker));
result=result.replace(marker,additions.map(([,n])=>n.text).join('\n\n')+'\n\n'+marker);
const final=nodes(result);
for(const [key,n] of from)assert.equal(final.get(key)?.text,n.text,'Artifact mismatch '+key);
writeFileSync(baseline,result);
console.log('Prepared profile-only Worker: '+[...from.keys()].join(', '));

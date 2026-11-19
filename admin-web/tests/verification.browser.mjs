// Every API call is intercepted: no production applications or approvals.
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
const browser=await chromium.launch({headless:true,channel:'msedge'});
try {
  const context=await browser.newContext({viewport:{width:1280,height:900}});
  await context.addInitScript(()=>sessionStorage.setItem('captro.admin.token','fixture-verification'));
  let row={user_id:'fixture',display_name:'Fixture photographer',reason:'Portfolio for identity review.',links:['https://example.com/work'],status:'under_review',version:1,reviewer_message:''};
  let lost=true;const requests=[];
  await context.route('https://api.flames-up.com/api/**',async route=>{
    const req=route.request(),url=new URL(req.url()),path=url.pathname.replace('/api','');
    const send=(body,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
    if(path==='/admin/me')return send({user:{id:'owner',full_name:'Fixture admin',username:'owner',status:'active'},role:'owner',permissions:['*'],environment:'Isolated test'});
    if(path==='/admin/console-summary')return send({cards:{},errors:{}});
    if(path==='/admin/verification')return send({items:row.status===(url.searchParams.get('status')||'under_review')?[row]:[],nextOffset:null});
    if(path==='/admin/verification/fixture')return send({application:row,history:[]});
    if(path==='/admin/verification/fixture/approve'){
      requests.push(req.postDataJSON());
      if(lost){lost=false;return send({detail:'Temporary network failure'},503);}
      row={...row,status:'approved',version:2};return send({ok:true});
    }
    return send({detail:'Unexpected fixture request'},404);
  });
  const page=await context.newPage();
  await page.goto('http://127.0.0.1:4178/?section=verification');
  await page.getByRole('button',{name:/Fixture photographer/}).click();
  await page.getByRole('combobox',{name:/^Action/}).selectOption('approve');
  await page.getByLabel('Message visible to applicant').fill('Your application was approved.');
  await page.getByLabel('Private reviewer note').fill('Fixture review only.');
  await page.getByRole('button',{name:'Save decision',exact:true}).click();
  await page.getByText(/Retry the same decision/).waitFor();
  await page.getByRole('button',{name:'Save decision',exact:true}).click();
  await page.getByText('Status: approved',{exact:true}).waitFor();
  assert.equal(requests.length,2);assert.equal(requests[0].id,requests[1].id);assert.equal(requests[0].version,1);
  await page.getByRole('combobox',{name:/^Status/}).selectOption('approved');
  await page.getByRole('button',{name:/Fixture photographer/}).click();
  await page.getByRole('combobox',{name:/^Action/}).selectOption('revoke');
  await page.setViewportSize({width:390,height:844});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Review must fit mobile width');
  console.log('PASS: verification queue, application detail, approve, safe retry identity, approved queue, revoke option and mobile width.');
} finally {await browser.close();}

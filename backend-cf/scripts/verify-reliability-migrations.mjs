import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const output=readFileSync(process.argv[2],'utf8');
const allowed=new Set(['20261016214657_additional_commerce_lifecycle.sql','20261017002255_reliable_payment_reconciliation.sql',
  '20261017002807_payment_recovery_resolution.sql','20261017131303_admin_console_workflows.sql','20261019013048_retryable_account_cleanup.sql']);
const pending=new Set(output.match(/\b\d{14}_[\w-]+\.sql\b/g)??[]);
for(const file of pending)assert.ok(allowed.has(file),'Unexpected migration: '+file);
assert.ok(pending.size>0||/No migrations to apply|Remote database is up to date/.test(output),'No usable migration evidence');
console.log('Verified pending migration allowlist:',[...pending]);

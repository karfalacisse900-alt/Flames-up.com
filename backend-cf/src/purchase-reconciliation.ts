export type ReconciliationOutcome = 'processing' | 'transient_failure' | 'missing_identity' | 'confirmed' | 'released' | 'recovery';
export type ReconciliationJob = {purchase: any; token: string; attempts: number; age_seconds: number};

/** Database leases own the schedule. No process-local retry loops or customer logs. */
export async function runPurchaseReconciliation(io: {
  claim: () => Promise<ReconciliationJob[]>;
  renew: (job: ReconciliationJob) => Promise<boolean>;
  inspect: (purchase: any) => Promise<ReconciliationOutcome>;
  finish: (job: ReconciliationJob, outcome: ReconciliationOutcome) => Promise<boolean>;
}) {
  const jobs = await io.claim();
  const metrics = {claimed: jobs.length, completed: 0, deferred: 0, lostLease: 0, checkpointFailure: 0, attention: 0};
  let next = 0;
  await Promise.all(Array.from({length: Math.min(4,jobs.length)}, async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      try {
        if (!await io.renew(job)) { metrics.lostLease++; continue; }
        let outcome: ReconciliationOutcome;
        try { outcome = await io.inspect(job.purchase); }
        catch { outcome = job.purchase.provider_payment_id || job.purchase.provider_checkout_id ? 'transient_failure' : 'missing_identity'; }
        if (!await io.finish(job,outcome)) { metrics.lostLease++; continue; }
        if (['confirmed','released','recovery'].includes(outcome)) metrics.completed++;
        else metrics.deferred++;
        if (outcome === 'recovery' || job.attempts >= 8 || job.age_seconds >= 86400) metrics.attention++;
      } catch { metrics.checkpointFailure++; } // lease expiry permits recovery; do not lose the entire batch.
    }
  }));
  return metrics;
}

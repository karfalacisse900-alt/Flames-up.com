/** One bounded batch per lease; mandatory failures never advance a checkpoint. */
export async function runAccountCleanup(job: any, steps: Array<() => Promise<boolean>>,
  checkpoint: (phase: number, error: string | null) => Promise<unknown>) {
  if (!job?.lease_token || !Number.isInteger(job.phase) || job.phase >= steps.length) return;
  try {
    const done = await steps[job.phase]();
    const saved = await checkpoint(job.phase + (done ? 1 : 0), null);
    if (saved !== true) throw new Error('CLEANUP_LEASE_LOST');
  } catch (error: any) {
    // Never retain raw provider errors, URLs or personal data in job diagnostics.
    const code = error?.message === 'CLEANUP_FINANCIAL_RETENTION_REVIEW'
      ? 'CLEANUP_FINANCIAL_RETENTION_REVIEW' : 'CLEANUP_STEP_FAILED';
    await checkpoint(job.phase, code);
    throw error;
  }
}

type Session = { status: string; payment_status: string; payment_intent?: string | { id: string } | null };
export async function reconcileHostedHold(io: {
  readSession: () => Promise<Session>;
  expireSession: () => Promise<unknown>;
  readIntent: (id: string) => Promise<{ status: string }>;
  cancelIntent: (id: string) => Promise<unknown>;
  confirm: (session: Session) => Promise<unknown>;
  release: () => Promise<unknown>;
}) {
  let session = await io.readSession();
  if (session.status === 'open') {
    // Completion may win the race with expiration. Re-read either way.
    try { await io.expireSession(); } catch {}
    session = await io.readSession();
  }
  if (session.payment_status === 'paid') {
    const result: any = await io.confirm(session);
    return result?.recoveryRequired ? 'recovery' : 'paid';
  }
  if (!['expired', 'complete'].includes(session.status)) return 'pending';
  const id = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id;
  if (id) {
    let intent = await io.readIntent(id);
    if (['processing', 'succeeded'].includes(intent.status)) return 'pending';
    if (intent.status !== 'canceled') {
      try { await io.cancelIntent(id); } catch { return 'pending'; }
      intent = await io.readIntent(id);
    }
    if (intent.status !== 'canceled') return 'pending';
  } else if (session.status !== 'expired') return 'pending';
  await io.release();
  return 'released';
}

export async function chatOperationID(sender: string, kind: string, target: string, key: string): Promise<string> {
  if (!/^[a-zA-Z0-9_.:-]{1,120}$/.test(key)) throw Error('CHAT_REQUEST_ID_INVALID');
  const bytes = new TextEncoder().encode(['captro-chat-v1',sender,kind,target,key.toLowerCase()].join('\0'));
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
export function sameChatOperation(existing: any, intended: any) {
  for (const key of ['sender_id','receiver_id','group_id','body','media_url','media_type']) {
    if ((existing[key]??null)!==(intended[key]??null)) throw Error('CHAT_REQUEST_ID_CONFLICT');
  }
  return existing;
}
export async function persistChatOperation(row: any, read: () => Promise<any>, insert: () => Promise<void>) {
  const prior = await read();
  if (prior) return { row:sameChatOperation(prior,row), created:false };
  try { await insert(); return { row, created:true }; }
  catch(error) {
    // A dropped response or uniqueness race is reconciled, never overwritten.
    const committed = await read();
    if (committed) return { row:sameChatOperation(committed,row), created:false };
    throw error;
  }
}

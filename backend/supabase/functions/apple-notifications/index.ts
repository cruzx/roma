import { apple, admin, refresh, json } from '../_shared/apple.ts';
Deno.serve(async request => {
  if (request.method !== 'POST') return json({ error:'POST required' },405);
  try {
    const text = await request.text();
    if (text.length > 65536) return json({ error:'Request too large' },413);
    const { signedPayload } = JSON.parse(text);
    if (typeof signedPayload !== 'string') return json({ error:'Invalid notification' },400);
    let verified; let source = apple('Production');
    try { verified = await source.verifier.verifyAndDecodeNotification(signedPayload); }
    catch {
      source = apple('Sandbox'); // Throws unless sandbox explicitly enabled.
      verified = await source.verifier.verifyAndDecodeNotification(signedPayload);
    }
    if (verified.notificationType === 'TEST') return json({ ok:true });
    if (!verified.data?.signedTransactionInfo) return json({ ok:true });
    const tx = await source.verifier.verifyAndDecodeTransaction(verified.data.signedTransactionInfo);
    const { data: row, error } = await admin().from('roam_memberships').select('user_id,environment').eq('original_transaction_id', tx.originalTransactionId).maybeSingle();
    if (error) throw error;
    if (row) {
      // Expire cache before current-state fetch, so failed refund processing fails closed.
      const { error: invalidateError } = await admin().from('roam_memberships').update({ checked_until:new Date(0).toISOString() }).eq('user_id',row.user_id);
      if (invalidateError) throw invalidateError;
      await refresh(row.user_id, tx.originalTransactionId!, row.environment);
    }
    return json({ ok:true });
  } catch { return json({ error:'Verification failed; retry notification' },503); }
});

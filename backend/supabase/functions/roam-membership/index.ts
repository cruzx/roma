import { admin, apple, refresh, json } from '../_shared/apple.ts';
Deno.serve(async request => {
  if (request.method !== 'POST') return json({ error: 'POST required' },405);
  const jwt = request.headers.get('Authorization')?.match(/^Bearer (.+)$/)?.[1];
  if (!jwt) return json({ error: 'Authentication required' },401);
  try {
    const db = admin();
    const { data: { user }, error } = await db.auth.getUser(jwt);
    if (error || !user) return json({ error: 'Authentication required' },401);
    apple('Production'); // Fail before a purchase when Apple credentials/root CAs are not configured.
    const text = await request.text();
    if (text.length > 32768) return json({ error: 'Request too large' },413);
    const body = JSON.parse(text || '{}');
    const { data: row, error: lookupError } = await db.from('roam_memberships').select('*').eq('user_id',user.id).maybeSingle();
    if (lookupError) throw lookupError;
    if (body.transactionId !== undefined) {
      if (typeof body.transactionId !== 'string' || !/^\d{1,32}$/.test(body.transactionId)) return json({ error:'Invalid transaction' },400);
      if (body.signedTransaction !== undefined && (typeof body.signedTransaction !== 'string' || body.signedTransaction.length > 24576)) return json({ error:'Invalid proof' },400);
      return json(await refresh(user.id, body.transactionId, undefined, body.signedTransaction));
    }
    if (!row) return json({ active:false, validUntil:null });
    if (Date.parse(row.checked_until) > Date.now()) return json({ active:Date.parse(row.valid_until)>Date.now(), validUntil:Date.parse(row.valid_until)/1000 });
    return json(await refresh(user.id, row.original_transaction_id, row.environment));
  } catch {
    // No token, transaction payload, private key, or underlying provider error is logged.
    return json({ error:'Membership verification unavailable; please retry' },503);
  }
});

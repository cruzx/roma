import { productID, entitlement } from './policy.ts';

// Dependencies are injected so ownership, revocation and atomic binding can be tested.
export async function verifyMembership(db: any, source: any, user: string, transactionID: string, signedTransaction?: string, now = Date.now()) {
  const { data: existing, error: lookupError } = await db.from('roam_memberships').select('original_transaction_id').eq('user_id', user).maybeSingle();
  if (lookupError) throw lookupError;
  let boundOriginal = existing?.original_transaction_id;
  if (signedTransaction !== undefined) {
    const proof = await source.verifier.verifyAndDecodeTransaction(signedTransaction);
    if (proof.transactionId !== transactionID) throw new Error('Purchase proof mismatch');
    // This validates bundle, product, ownership, environment, and ID before using the proof.
    entitlement(proof, null, 1, user, source.environment, now, proof.appAccountToken ? undefined : proof.originalTransactionId);
    const { data: owner, error: ownerError } = await db.from('roam_memberships').select('user_id').eq('original_transaction_id', proof.originalTransactionId).maybeSingle();
    if (ownerError) throw ownerError;
    if (owner && owner.user_id !== user) throw new Error('Purchase already linked');
    boundOriginal = proof.originalTransactionId;
  }
  const result = await source.api.getAllSubscriptionStatuses(transactionID);
  const candidates = [];
  for (const group of result.data ?? []) for (const item of group.lastTransactions ?? []) {
    if (!item.signedTransactionInfo) continue;
    const tx = await source.verifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
    if (tx.productId !== productID) continue;
    const renewal = item.signedRenewalInfo ? await source.verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo) : null;
    candidates.push(entitlement(tx, renewal, Number(item.status), user, source.environment, now, boundOriginal));
  }
  if (!candidates.length) throw new Error('No matching subscription');
  const selected = candidates.sort((a,b) => b.validUntil-a.validUntil)[0];
  const { error } = await db.from('roam_memberships').upsert({
    user_id: user, original_transaction_id: selected.originalTransactionId, product_id: productID,
    environment: source.environment, valid_until: new Date(selected.validUntil).toISOString(),
    checked_until: new Date(now+15*60*1000).toISOString(), updated_at: new Date().toISOString(),
  }, { onConflict: 'user_id' });
  if (error) throw new Error('Could not persist membership');
  return { active: selected.active, validUntil: selected.active ? selected.validUntil/1000 : null };
}

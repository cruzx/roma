import { Environment } from 'npm:@apple/app-store-server-library@3.1.0';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { Buffer } from 'node:buffer';
import { EdgeAppleAPI } from './apple-api.ts';
import { SignedDataVerifier } from './apple-verifier.js';
import { bundleID, productID, entitlement } from './policy.ts';
const required = (key: string) => { const value = Deno.env.get(key); if (!value) throw new Error(`Missing configuration: ${key}`); return value; };
export const admin = () => createClient(required('SUPABASE_URL'), required('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
export function apple(environment: string) {
  if (environment !== 'Production' && !(environment === 'Sandbox' && Deno.env.get('APPLE_ALLOW_SANDBOX') === 'true')) throw new Error('Environment not allowed');
  const env = environment === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;
  const roots = JSON.parse(required('APPLE_ROOT_CA_BASE64_JSON')).map((v: string) => Buffer.from(v, 'base64'));
  const verifier = new SignedDataVerifier(roots, true, env, bundleID, Number(required('APPLE_APP_ID')));
  const api = new EdgeAppleAPI(required('APPLE_PRIVATE_KEY').replace(/\\n/g, '\n'), required('APPLE_KEY_ID'), required('APPLE_ISSUER_ID'), bundleID, env);
  return { api, verifier };
}
export async function locate(id: string) {
  const production = apple('Production');
  try { return { ...production, environment: 'Production', response: await production.api.getTransactionInfo(id) }; }
  catch (e) {
    // Only Apple's transaction-not-found response allows Sandbox lookup, never a network/signature error.
    if ((e as any).apiError !== 4040010 || Deno.env.get('APPLE_ALLOW_SANDBOX') !== 'true') throw e;
    const sandbox = apple('Sandbox');
    return { ...sandbox, environment: 'Sandbox', response: await sandbox.api.getTransactionInfo(id) };
  }
}
export async function refresh(user: string, transactionID: string, knownEnvironment?: string) {
  const source = knownEnvironment ? { ...apple(knownEnvironment), environment: knownEnvironment } : await locate(transactionID);
  const result = await source.api.getAllSubscriptionStatuses(transactionID);
  const candidates = [];
  for (const group of result.data ?? []) for (const item of group.lastTransactions ?? []) {
    if (!item.signedTransactionInfo) continue;
    const tx = await source.verifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
    if (tx.productId !== productID) continue;
    const renewal = item.signedRenewalInfo ? await source.verifier.verifyAndDecodeRenewalInfo(item.signedRenewalInfo) : null;
    candidates.push(entitlement(tx, renewal, Number(item.status), user, source.environment));
  }
  if (!candidates.length) throw new Error('No matching subscription');
  const selected = candidates.sort((a,b) => b.validUntil-a.validUntil)[0];
  const db = admin();
  const { error } = await db.from('roam_memberships').upsert({
    user_id: user, original_transaction_id: selected.originalTransactionId, product_id: productID,
    environment: source.environment, valid_until: new Date(selected.validUntil).toISOString(),
    checked_until: new Date(Date.now()+15*60*1000).toISOString(), updated_at: new Date().toISOString(),
  }, { onConflict: 'user_id' });
  if (error) throw new Error('Could not persist membership');
  return { active: selected.active, validUntil: selected.active ? selected.validUntil/1000 : null };
}
export const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type':'application/json', 'Cache-Control':'no-store' } });

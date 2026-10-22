import { Environment } from 'npm:@apple/app-store-server-library@3.1.0';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { Buffer } from 'node:buffer';
import { EdgeAppleAPI } from './apple-api.ts';
import { SignedDataVerifier } from './apple-verifier.js';
import { bundleID } from './policy.ts';
import { verifyMembership } from './membership-verification.ts';
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
export async function refresh(user: string, transactionID: string, knownEnvironment?: string, signedTransaction?: string) {
  const source = knownEnvironment ? { ...apple(knownEnvironment), environment: knownEnvironment } : await locate(transactionID);
  return await verifyMembership(admin(), source, user, transactionID, signedTransaction);
}
export const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type':'application/json', 'Cache-Control':'no-store' } });

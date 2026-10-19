// Integration check using Apple's TEST notification responses, never production customer data.
// deno run --allow-read --allow-env --allow-net backend/tests/apple-verifier.ts
// APPLE_TEST_ROOTS_JSON_PATH: JSON array of base64 DER roots downloaded from Apple PKI.
// APPLE_TEST_PRODUCTION_PATH / APPLE_TEST_SANDBOX_PATH: test status JSON with signedPayload.
import { readFileSync } from 'node:fs';
import { Buffer } from 'node:buffer';
import assert from 'node:assert/strict';
import { SignedDataVerifier } from '../supabase/functions/_shared/apple-verifier.js';
const required = (name: string) => { const v = Deno.env.get(name); if (!v) throw new Error(`Set ${name}`); return v; };
const roots = JSON.parse(readFileSync(required('APPLE_TEST_ROOTS_JSON_PATH'), 'utf8')).map((v: string) => Buffer.from(v, 'base64'));
for (const environment of ['Production', 'Sandbox']) {
  const payload = JSON.parse(readFileSync(required(`APPLE_TEST_${environment.toUpperCase()}_PATH`), 'utf8')).signedPayload;
  const verifier = new SignedDataVerifier(roots, true, environment, 'com.xiangchengjin.roam', 6818919203);
  assert.equal((await verifier.verifyAndDecodeNotification(payload)).notificationType, 'TEST');
  const parts = payload.split('.');
  const data = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
  data.notificationUUID = 'tampered';
  parts[1] = Buffer.from(JSON.stringify(data)).toString('base64url');
  await assert.rejects(() => verifier.verifyAndDecodeNotification(parts.join('.')));
  const wrongApp = new SignedDataVerifier(roots, true, environment, 'invalid.bundle', 6818919203);
  await assert.rejects(() => wrongApp.verifyAndDecodeNotification(payload));
  const wrongRoot = new SignedDataVerifier([], true, environment, 'com.xiangchengjin.roam', 6818919203);
  await assert.rejects(() => wrongRoot.verifyAndDecodeNotification(payload));
  console.log(environment, 'genuine TEST accepted; altered payload, wrong bundle and untrusted chain rejected');
}

// The two read-only Apple endpoints used by membership verification.
// WebCrypto signing avoids Deno's incompatible node:crypto EC curve metadata.
import { importPKCS8, SignJWT } from 'npm:jose@6.1.0';
import { TransactionInfoResponseValidator } from 'npm:@apple/app-store-server-library@3.1.0/dist/models/TransactionInfoResponse.js';
import { StatusResponseValidator } from 'npm:@apple/app-store-server-library@3.1.0/dist/models/StatusResponse.js';
export class EdgeAppleAPI {
  constructor(private signingKey: string, private keyId: string, private issuerId: string, private bundleId: string, private environment: string) {
    if (!['Production', 'Sandbox'].includes(environment)) throw new Error('Invalid Apple environment');
  }
  private async get(path: string, validator: { validate(value: unknown): boolean }) {
    const token = await new SignJWT({ bid: this.bundleId })
      .setProtectedHeader({ alg: 'ES256', kid: this.keyId, typ: 'JWT' })
      .setIssuer(this.issuerId).setAudience('appstoreconnect-v1').setIssuedAt().setExpirationTime('5m')
      .sign(await importPKCS8(this.signingKey, 'ES256'));
    const base = this.environment === 'Production' ? 'https://api.storekit.apple.com' : 'https://api.storekit-sandbox.apple.com';
    const response = await fetch(base + path, { headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' }, signal: AbortSignal.timeout(15000) });
    const body = await response.json().catch(() => null);
    if (!response.ok) throw Object.assign(new Error('Apple API request failed'), { httpStatusCode: response.status, apiError: body?.errorCode });
    if (!validator.validate(body)) throw new Error('Unexpected Apple response format');
    return body;
  }
  getTransactionInfo(id: string) { return this.get('/inApps/v1/transactions/' + encodeURIComponent(id), new TransactionInfoResponseValidator()); }
  getAllSubscriptionStatuses(id: string) { return this.get('/inApps/v1/subscriptions/' + encodeURIComponent(id), new StatusResponseValidator()); }
}

// Compatibility adapter for Supabase Edge's incomplete node:crypto X509Certificate.
// Uses the same jsrsasign dependency as Apple's verifier; no validation is skipped.
import { X509, KEYUTIL, ASN1HEX } from 'npm:jsrsasign@11.1.0';
import { createPublicKey, verify } from 'node:crypto';
import { Buffer } from 'node:buffer';
export class EdgeX509Certificate {
  raw: Buffer;
  private cert: any;
  constructor(input: Buffer | string) {
    this.cert = new X509();
    if (typeof input === 'string' && input.includes('BEGIN CERTIFICATE')) {
      this.cert.readCertPEM(input);
      this.raw = Buffer.from(this.cert.hex, 'hex');
    } else {
      this.raw = Buffer.from(input);
      this.cert.readCertHex(this.raw.toString('hex'));
    }
  }
  toString() { return '-----BEGIN CERTIFICATE-----\n' + this.raw.toString('base64').match(/.{1,64}/g)!.join('\n') + '\n-----END CERTIFICATE-----\n'; }
  get publicKey() { return createPublicKey(KEYUTIL.getPEM(this.cert.getPublicKey())); }
  get subject() { return this.cert.getSubjectString(); }
  get issuer() { return this.cert.getIssuerString(); }
  get ca() { return this.cert.getExtBasicConstraints()?.cA === true; }
  get infoAccess() { return (this.cert.getExtAIAInfo()?.ocsp ?? []).map((uri: string) => 'OCSP - URI:' + uri).join('\n'); }
  get validFrom() { return this.date(this.cert.getNotBefore()); }
  get validTo() { return this.date(this.cert.getNotAfter()); }
  private date(value: string) {
    const full = value.length === 13 ? (Number(value.slice(0,2)) >= 50 ? '19' : '20') + value : value;
    if (!/^\d{14}Z$/.test(full)) throw new Error('Unsupported certificate date');
    return full.replace(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/, '$1-$2-$3T$4:$5:$6Z');
  }
  verify(key: any) {
    const alg = this.cert.getSignatureAlgorithmField();
    const hashes: Record<string,string> = { SHA256withRSA:'sha256', SHA384withRSA:'sha384', SHA512withRSA:'sha512', SHA256withECDSA:'sha256', SHA384withECDSA:'sha384', SHA512withECDSA:'sha512', SHA1withRSA:'sha1' };
    if (!hashes[alg]) return false;
    const tbs = ASN1HEX.getTLVbyList(this.cert.hex, 0, [0]);
    return verify(hashes[alg], Buffer.from(tbs, 'hex'), key, Buffer.from(this.cert.getSignatureValueHex(), 'hex'));
  }
}

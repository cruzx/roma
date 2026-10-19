# Apple verification in Supabase Edge

`apple-verifier.js` is adapted from `@apple/app-store-server-library` 3.1.0, `dist/jws_verification.js`. Apple's MIT notice is preserved in APPLE-LICENSE.txt.

Changes from upstream:
- CommonJS imports/exports converted to ESM with pinned npm dependencies.
- Explicit node:buffer import.
- X509Certificate replaced with x509-compat.ts because Supabase's Deno runtime does not implement its raw/toString interfaces. jsrsasign parses DER, native crypto verifies certificate and OCSP signatures.
- JWT signature verification uses jose/WebCrypto, explicitly restricted to ES256. Deno's EC curve naming is incompatible with jsonwebtoken's Node validation. No signature check is disabled.

Upstream certificate chain, CA, validity, Apple-specific OID, OCSP revocation, bundle, app ID, environment and payload validation remain. Online checks are enabled. Failures deny entitlement and notifications return a retryable failure.

`apple-api.ts` implements only the two read-only Apple API requests used here. It signs five-minute ES256 tokens via WebCrypto, restricts hosts to Apple's production/sandbox endpoints, keeps Apple's response validators, and preserves Apple error codes. Only transaction-not-found permits the production-to-sandbox fallback.

Validation: 15 entitlement policy tests; actual Apple TEST notifications in both environments accepted, tampered signatures rejected; actual Apple API authenticated requests rejected nonexistent transactions as expected. Live Apple notification delivery status was SUCCESS for both environments on 2026-10-19. These are not proof of a completed sandbox purchase.

`backend/tests/apple-verifier.ts` accepts externally stored Apple TEST fixtures through environment variables. Never commit private keys, bearer tokens or notification payloads. Re-run after updating Apple, jose, jsrsasign or the Deno runtime.

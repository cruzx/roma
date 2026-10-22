# Current implementation and rollout — 2026-10-19

## Delivered
- Email OTP login; account-isolated itinerary and journal metadata; photos remain in private iCloud.
- Automatic workspace activation for eligible accounts and 30-second sync while the app runs. Logout restores the original local workspace. No manual enable/restart controls.
- Annual StoreKit subscription (China CNY18/year) is configured and added to an App Store review draft. Apple credentials/root certificates are stored in Supabase Secrets; both verification functions are deployed. No private key is committed.
- `membership.sql` and `complimentary-sync.sql` have now been applied to the live database. The owner-requested verified account has a server-maintained complimentary grant. All other accounts require an active verified subscription. Grants cannot be read or modified directly by clients; the status RPC returns only the caller's grant.
- Complimentary sync does not depend on Apple transaction verification. No purchase or subscription was performed. Grants can be revoked by an administrator; deleting an account also removes its grant.
- The complimentary client build was installed and launched on the connected iPhone and installed on Mac. Live authenticated-role SQL confirmed the owner has sync access. Full two-device photo propagation has not been verified.
- iOS newly added journal photos use non-overlapping placement considering scaled/rotated images and text. Existing items stay fixed; a full viewport extends right and reveals the new photo. Both camera and photo-library insertion use the same placement path.

## Validation
- 23 database entitlement checks cover paid membership, complimentary grants, expiry, revocation, isolation and unauthorized writes.
- Signed iOS and Mac builds for the complimentary feature succeeded.
- 27 iOS layout/store/account tests passed (3 placement, 13 persistence, 11 account). Camera and photo-library call sites both use the tested layout helper.

Earlier deployment/installation status documents are historical snapshots; this file supersedes conflicting rollout status. Never reapply membership.sql to the live database: it is a one-time migration.

## App Store release preparation — 2026-10-19
- iOS 1.1 build 2026101902 uploaded, processed and selected. Chinese/English descriptions, release notes, review notes and export-compliance answers saved.
- Subscription screenshot and review notes saved; subscription 6823544188 is in the review draft, not submitted.
- Privacy site version 2 published; App Privacy labels updated for email, user ID, travel content/expenses and purchase history (functionality, linked, no tracking).
- Both production and sandbox Apple notification URLs saved. Apple TEST notification deliveries returned SUCCESS in both environments.
- Supabase Deno required certificate/JWS compatibility adaptations; see _shared/APPLE-VERIFIER.md. Real TEST payload verification passed, altered payload/wrong bundle/untrusted root rejected; Apple API authenticated read requests correctly rejected nonexistent transactions. Membership endpoint rejects missing authentication with HTTP 401. 15 entitlement policy checks pass.
- iOS and Mac compile with PurchaseIntent handling. Current Xcode 27.1 build 27A9269 is identified by App Store Connect as Beta. Apple blocks adding this binary to review. A formal Xcode download/rebuild with a new build number is required; no review submission has occurred.
- Full sandbox purchase/renewal/refund flow remains unverified. TEST delivery is not a purchase test.
- Mac settings are aligned with iOS (Language, Account, Trash, New Trip); previous installed Mac build contains that simplification. The newest PurchaseIntent changes are compiled but not installed on the user's devices.

## Submission completed — 2026-10-20
- Xcode updated by user to 27.1 (27A9275). iOS 1.1 build 2026102001 archived and uploaded successfully; App Store beta-build restriction cleared.
- App version, annual subscription and subscription group submitted together. All three are Waiting for Review. Submission ID: 8038bbc6-47f5-4792-851a-cb6d30ea0bde, 2026-10-20 10:03 Asia/Shanghai.
- New Paid Applications Schedule acceptance was requested and user answered agree; final acceptance triggered SMS two-factor authentication, which remains user-dependent. Do not claim agreement accepted. It did not prevent this review submission.
- Export warns missing dSYM for app and share extension; upload and review submission succeeded. No installation on devices was performed this turn.

## Rejection remediation — 2026-10-20
- Build 2026102001 rejected under Guideline 5.0 at 10:58. Reviewer cited ChatGPT/GPT references in metadata. The old static privacy site's hostname contained that brand; app Swift sources have no corresponding service integration.
- Bilingual policy moved to https://roam.iiife.com/ on Cloudflare Pages (`roam-privacy-support`); custom-domain SSL active, HTTP 200 and page rendered verified. Support uses user-provided https://www.instagram.com/cruzxcx/.
- Both iOS and Mac in-app policy URLs updated. iOS 1.1 build 2026102002 archived and uploaded with official Xcode 27A9275. Missing dSYM warnings remain non-blocking.
- Chinese/English iOS descriptions, support URLs, App Privacy policy URLs and review notes updated. Awaiting new-build processing and resubmission at this checkpoint.
- Resubmitted successfully at 2026-10-20 11:34 Asia/Shanghai: iOS 1.1 (2026102002), annual subscription and subscription group all show Waiting for Review. Same submission ID 8038bbc6-47f5-4792-851a-cb6d30ea0bde. Reply explaining the static-hosting domain was sent at 11:28. China availability retained.

## Guideline 5.1.1(v) purchase-flow fix — 2026-10-22
- Both platforms allow subscribing and restoring before email login. StoreKit entitlement/expiry is read independently of the optional cloud account; purchase does not require a server preflight or personal data. Restore is visible outside the disclosure group.
- New purchases do not use appAccountToken. Optional later login submits Apple's signed transaction proof. Server validates the signature, product, bundle, environment, current Apple status and original transaction ID. A database-unique original transaction binding prevents cross-account duplicate claims, including concurrent first claims. Existing token-bound subscriptions retain strict owner checks.
- Server membership and Apple notification functions deployed via Supabase dashboard. Authenticated private document access stays server-gated; unauthenticated membership probe returned HTTP 401. No schema migration or owner grant changes.
- Validation: 13 iOS account/StoreKit tests passed. StoreKitTest supplies simulated transactions and bypasses system purchase/restore dialogs; no real charge, Sandbox end-to-end purchase or real two-device linking was performed. 21 entitlement policy checks and 16 proof/binding/refund/race checks passed.
- iOS and Mac 1.1 build 2026102201 archived and uploaded successfully with official Xcode. Privacy site updated on roam.iiife.com with optional-email purchase/restore disclosure. Both localizations and review notes updated in App Store Connect.
- Previous Mac submission was withdrawn to replace its affected purchase flow. Awaiting Apple build processing before selecting the new binaries and resubmitting at this checkpoint.

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

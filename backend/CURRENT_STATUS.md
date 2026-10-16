# Current implementation and rollout — 2026-10-16

## Delivered
- Email OTP login; account-isolated itinerary and journal metadata; photos remain in private iCloud.
- Automatic workspace activation for eligible accounts and 30-second sync while the app runs. Logout restores the original local workspace. No manual enable/restart controls.
- Annual StoreKit subscription product is configured as a draft. Production Apple transaction verification still needs server credentials and deployment.
- `membership.sql` and `complimentary-sync.sql` have now been applied to the live database. The owner-requested verified account has a server-maintained complimentary grant. All other accounts require an active verified subscription. Grants cannot be read or modified directly by clients; the status RPC returns only the caller's grant.
- Complimentary sync does not depend on Apple transaction verification. No purchase or subscription was performed. Grants can be revoked by an administrator; deleting an account also removes its grant.
- The complimentary client build was installed and launched on the connected iPhone and installed on Mac. Live authenticated-role SQL confirmed the owner has sync access. Full two-device photo propagation has not been verified.
- iOS newly added journal photos use non-overlapping placement considering scaled/rotated images and text. Existing items stay fixed; a full viewport extends right and reveals the new photo. Both camera and photo-library insertion use the same placement path.

## Validation
- 23 database entitlement checks cover paid membership, complimentary grants, expiry, revocation, isolation and unauthorized writes.
- Signed iOS and Mac builds for the complimentary feature succeeded.
- 27 iOS layout/store/account tests passed (3 placement, 13 persistence, 11 account). Camera and photo-library call sites both use the tested layout helper.

Earlier deployment/installation status documents are historical snapshots; this file supersedes conflicting rollout status. Never reapply membership.sql to the live database: it is a one-time migration.

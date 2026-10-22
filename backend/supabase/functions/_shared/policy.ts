export const productID = 'com.xiangchengjin.roam.sync.annual';
export const bundleID = 'com.xiangchengjin.roam';
export function entitlement(transaction: any, renewal: any, status: number, user: string, environment: string, now = Date.now(), boundOriginalTransactionId?: string) {
  if (transaction.bundleId !== bundleID || transaction.productId !== productID ||
      transaction.type !== 'Auto-Renewable Subscription' || transaction.environment !== environment ||
      !ownsSubscription(transaction, user, boundOriginalTransactionId) ||
      transaction.inAppOwnershipType !== 'PURCHASED' || !/^\d+$/.test(transaction.originalTransactionId ?? '')) {
    throw new Error('Transaction ownership or product mismatch');
  }
  const end = status === 4 ? renewal?.gracePeriodExpiresDate : transaction.expiresDate;
  const active = [1, 4].includes(status) && !transaction.revocationDate && Number.isFinite(end) && end > now;
  return { active, validUntil: active ? end : 0, originalTransactionId: transaction.originalTransactionId };
}

// Tokenless purchases may be linked only using a verified purchase proof or an
// existing server-owned row. A transaction ID alone never authorizes a new claim.
export function ownsSubscription(transaction: any, user: string, boundOriginalTransactionId?: string) {
  if (transaction.appAccountToken) return transaction.appAccountToken.toLowerCase() === user.toLowerCase();
  return !!boundOriginalTransactionId && transaction.originalTransactionId === boundOriginalTransactionId;
}

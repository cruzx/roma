export const productID = 'com.xiangchengjin.roam.sync.annual';
export const bundleID = 'com.xiangchengjin.roam';
export function entitlement(transaction: any, renewal: any, status: number, user: string, environment: string, now = Date.now()) {
  if (transaction.bundleId !== bundleID || transaction.productId !== productID ||
      transaction.type !== 'Auto-Renewable Subscription' || transaction.environment !== environment ||
      transaction.appAccountToken?.toLowerCase() !== user.toLowerCase() ||
      transaction.inAppOwnershipType !== 'PURCHASED' || !/^\d+$/.test(transaction.originalTransactionId ?? '')) {
    throw new Error('Transaction ownership or product mismatch');
  }
  const end = status === 4 ? renewal?.gracePeriodExpiresDate : transaction.expiresDate;
  const active = [1, 4].includes(status) && !transaction.revocationDate && Number.isFinite(end) && end > now;
  return { active, validUntil: active ? end : 0, originalTransactionId: transaction.originalTransactionId };
}

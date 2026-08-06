import { doc, setDoc } from 'firebase/firestore';

const activeUntil = new Date('2099-01-01T00:00:00.000Z');

export async function seedActiveAppAccess(adminContext, userIds) {
  await Promise.all(userIds.map((userId) => setDoc(
    doc(adminContext.firestore(), `users/${userId}/entitlements/app_access`),
    {
      schemaVersion: 1,
      uid: userId,
      entitlementId: 'app_access',
      isActive: true,
      productId: 'test_yearly',
      expiresAt: activeUntil,
      accessUntil: activeUntil,
      revenueCatAppId: 'test-app',
      revenueCatRequestDateMs: Date.now(),
      sourceEventId: 'test-seed',
      sourceEventType: 'TEST',
      verifiedAt: new Date(),
    }
  )));
}

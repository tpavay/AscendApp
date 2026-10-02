import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
} from 'firebase/firestore';

import { seedActiveAppAccess } from './paid-access-fixture.mjs';

// How a climber's athlete looks on Ascend Mountain: preset choices only, published by the owner
// before or after purchase (onboarding asks ahead of the paywall), read by paid climbers whose
// stairs it runs on, and always deletable by the owner.
const projectId = 'demo-ascendapp-rules-athlete-look';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const ownerId = 'climber-123';
const paidRivalId = 'rival-456';
const unpaidStrangerId = 'stranger-789';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: firestoreRules,
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await seedActiveAppAccess(adminContext, [paidRivalId]);
  });
});

after(async () => {
  await testEnv.cleanup();
});

function look(overrides = {}) {
  return {
    schemaVersion: 1,
    body: 'b',
    skinTone: 'tone3',
    hairStyle: 'long',
    hairColor: 'dark_brown',
    top: 'lime',
    bottom: 'black',
    shoes: 'white',
    size: 'regular',
    muscle: 'some',
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function lookRef(context, userId = ownerId, docId = 'current') {
  return doc(context.firestore(), 'users', userId, 'athlete_look', docId);
}

async function seedLook(data = look()) {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(lookRef(adminContext), { ...data, updatedAt: Timestamp.now() });
  });
}

test('the owner publishes their look before they have paid, as onboarding does', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  await assertSucceeds(setDoc(lookRef(owner), look()));
  await assertSucceeds(setDoc(lookRef(owner), look({ size: 'big', muscle: 'defined' })));
});

test('every option the editor offers is accepted', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  const options = {
    body: ['a', 'b'],
    skinTone: ['tone1', 'tone2', 'tone3', 'tone4', 'tone5', 'tone6'],
    hairStyle: ['parted', 'long', 'buns', 'buzzed', 'short'],
    hairColor: ['black', 'dark_brown', 'brown', 'blond', 'red', 'grey'],
    top: ['lime', 'white', 'blue', 'pink', 'orange', 'black'],
    bottom: ['lime', 'white', 'blue', 'pink', 'orange', 'black'],
    shoes: ['lime', 'white', 'blue', 'pink', 'orange', 'black'],
    size: ['slim', 'regular', 'solid', 'big'],
    muscle: ['smooth', 'some', 'defined'],
  };
  for (const [field, values] of Object.entries(options)) {
    for (const value of values) {
      await assertSucceeds(setDoc(lookRef(owner), look({ [field]: value })));
    }
  }
});

test('a value outside the presets is refused, so nothing free-form is ever published', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  await assertFails(setDoc(lookRef(owner), look({ skinTone: '#ff00ff' })));
  await assertFails(setDoc(lookRef(owner), look({ hairStyle: 'mohawk' })));
  await assertFails(setDoc(lookRef(owner), look({ top: 'gold' })));
  await assertFails(setDoc(lookRef(owner), look({ size: 'huge' })));
  await assertFails(setDoc(lookRef(owner), look({ body: 'c' })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 0 })));
  await assertFails(setDoc(lookRef(owner), look({ updatedAt: Timestamp.fromMillis(0) })));
});

test('a look wears at most one unlocked item per slot, and only ones the app draws', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  const items = [
    'pumpkin_classic', 'pumpkin_ghost', 'pumpkin_lantern', 'pumpkin_heirloom', 'pumpkin_midnight', 'pumpkin_giant',
    'pumpkin_giant_lantern', 'harvest_gourd', 'cornucopia', 'roast_turkey', 'pumpkin_pie', 'golden_turkey', 'turkey_giant',
  ];
  for (const carry of items) {
    await assertSucceeds(setDoc(lookRef(owner), look({ schemaVersion: 2, carry })));
  }
  for (const head of ['witch_hat', 'pumpkin_head']) {
    await assertSucceeds(setDoc(lookRef(owner), look({ schemaVersion: 2, head })));
  }
  await assertSucceeds(setDoc(lookRef(owner), look({ schemaVersion: 2, carry: 'pumpkin_giant', head: 'witch_hat', costume: 'ghost_sheet' })));
  await assertSucceeds(setDoc(lookRef(owner), look({
    schemaVersion: 2, tank: 'spiderweb_tank', shorts: 'witching_shorts', trainers: 'ember_trainers',
  })));
  await assertSucceeds(setDoc(lookRef(owner), look({ schemaVersion: 2, tank: 'pumpkin_stripe_tank', trainers: 'glow_trainers' })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, tank: 'glow_trainers' })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, shorts: 'spiderweb_tank' })));
  // Each slot takes only its own items.
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, head: 'pumpkin_giant' })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, carry: 'witch_hat' })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, costume: 'witch_hat' })));
  // Carrying nothing is the field's absence, which every earlier build already writes.
  await assertSucceeds(setDoc(lookRef(owner), look({ schemaVersion: 2 })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, carry: 'chainsaw' })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, carry: '' })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, carry: null })));
  await assertFails(setDoc(lookRef(owner), look({ schemaVersion: 2, carry: ['pumpkin_giant'] })));
});

test('the document is exactly the look: no extra field and none missing', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  await assertFails(setDoc(lookRef(owner), look({ displayName: 'Sam' })));
  const { muscle, ...missingMuscle } = look();
  await assertFails(setDoc(lookRef(owner), missingMuscle));
});

test('only the one document "current" exists', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  await assertFails(setDoc(lookRef(owner, ownerId, 'previous'), look()));
});

test('nobody writes another climber\'s look', async () => {
  const rival = testEnv.authenticatedContext(paidRivalId);
  await assertFails(setDoc(lookRef(rival, ownerId), look()));
  await seedLook();
  await assertFails(deleteDoc(lookRef(rival, ownerId)));
});

test('a paid climber reads the look of anyone on their stairs; an unpaid stranger does not', async () => {
  await seedLook();
  await assertSucceeds(getDoc(lookRef(testEnv.authenticatedContext(paidRivalId))));
  await assertFails(getDoc(lookRef(testEnv.authenticatedContext(unpaidStrangerId))));
  await assertFails(getDoc(lookRef(testEnv.unauthenticatedContext())));
});

test('the owner reads and deletes their own look without paying, so account deletion always can', async () => {
  await seedLook();
  const owner = testEnv.authenticatedContext(ownerId);
  await assertSucceeds(getDoc(lookRef(owner)));
  await assertSucceeds(deleteDoc(lookRef(owner)));
});

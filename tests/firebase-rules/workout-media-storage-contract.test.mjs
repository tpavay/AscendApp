import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteObject,
  getBytes,
  getMetadata,
  listAll,
  ref,
  uploadBytes,
} from 'firebase/storage';

const projectId = 'demo-ascendapp-rules-storage-media';
const storageRules = readFileSync(new URL('../../storage.rules', import.meta.url), 'utf8');

const ownerId = 'owner-123';
const intruderId = 'intruder-456';

// A one-pixel JPEG is enough: the rules only inspect size and content type.
const jpegBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xdb, 0x00, 0x43, 0x00, 0xff, 0xd9]);
const mp4Bytes = new Uint8Array([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]);

const legacyPhotoPath = 'photos/2B3C4D5E-6F70-4812-9345-A6B7C8D9E0F1.jpg';
const legacyVideoPath = 'videos/3C4D5E6F-7081-4923-A456-B7C8D9E0F1A2.mov';

const ownedPhotoPath = `users/${ownerId}/photos/5E6F7081-92A3-4B45-C678-D9E0F1A2B3C4.jpg`;
const ownedVideoPath = `users/${ownerId}/videos/6F708192-A3B4-4C56-D789-E0F1A2B3C4D5.mov`;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    storage: {
      rules: storageRules,
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearStorage();
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    const storage = adminContext.storage();
    await uploadBytes(ref(storage, legacyPhotoPath), jpegBytes, { contentType: 'image/jpeg' });
    await uploadBytes(ref(storage, legacyVideoPath), mp4Bytes, { contentType: 'video/quicktime' });
    await uploadBytes(ref(storage, ownedPhotoPath), jpegBytes, { contentType: 'image/jpeg' });
    await uploadBytes(ref(storage, ownedVideoPath), mp4Bytes, { contentType: 'video/quicktime' });
  });
});

after(async () => {
  await testEnv.cleanup();
});

// The legacy flat prefixes carry no owner segment, so no rule over them can tell
// one climber's media from another's. Nothing may reach them.

test('another climber cannot read legacy root workout media', async () => {
  const storage = testEnv.authenticatedContext(intruderId).storage();

  await assertFails(getBytes(ref(storage, legacyPhotoPath)));
  await assertFails(getMetadata(ref(storage, legacyPhotoPath)));
  await assertFails(getBytes(ref(storage, legacyVideoPath)));
  await assertFails(getMetadata(ref(storage, legacyVideoPath)));
});

test('another climber cannot delete legacy root workout media', async () => {
  const storage = testEnv.authenticatedContext(intruderId).storage();

  await assertFails(deleteObject(ref(storage, legacyPhotoPath)));
  await assertFails(deleteObject(ref(storage, legacyVideoPath)));
});

test('no signed-in climber can enumerate the legacy root workout media prefixes', async () => {
  const storage = testEnv.authenticatedContext(intruderId).storage();

  await assertFails(listAll(ref(storage, 'photos')));
  await assertFails(listAll(ref(storage, 'videos')));
});

// A flat path cannot name an owner, so the prefixes are closed to everyone -
// including whoever originally uploaded the object.
test('the original uploader cannot reach legacy root workout media either', async () => {
  const storage = testEnv.authenticatedContext(ownerId).storage();

  await assertFails(getBytes(ref(storage, legacyPhotoPath)));
  await assertFails(deleteObject(ref(storage, legacyPhotoPath)));
  await assertFails(getBytes(ref(storage, legacyVideoPath)));
  await assertFails(deleteObject(ref(storage, legacyVideoPath)));
});

test('no signed-in climber can write to the legacy root workout media prefixes', async () => {
  const storage = testEnv.authenticatedContext(intruderId).storage();

  await assertFails(
    uploadBytes(ref(storage, 'photos/7081A2B3-C4D5-4E67-F890-A1B2C3D4E5F6.jpg'), jpegBytes, {
      contentType: 'image/jpeg',
    })
  );
  await assertFails(
    uploadBytes(ref(storage, 'videos/8192B3C4-D5E6-4F78-A901-B2C3D4E5F6A7.mov'), mp4Bytes, {
      contentType: 'video/quicktime',
    })
  );
});

test('an unauthenticated visitor cannot reach the legacy root prefixes', async () => {
  const storage = testEnv.unauthenticatedContext().storage();

  await assertFails(getBytes(ref(storage, legacyPhotoPath)));
  await assertFails(deleteObject(ref(storage, legacyPhotoPath)));
  await assertFails(getBytes(ref(storage, legacyVideoPath)));
  await assertFails(deleteObject(ref(storage, legacyVideoPath)));
});

// The owner-scoped paths the app actually writes today keep working, and stay
// closed to everyone else.

test('an owner can read, list, upload, and delete their own workout media', async () => {
  const storage = testEnv.authenticatedContext(ownerId).storage();

  await assertSucceeds(getBytes(ref(storage, ownedPhotoPath)));
  await assertSucceeds(getBytes(ref(storage, ownedVideoPath)));
  await assertSucceeds(listAll(ref(storage, `users/${ownerId}/photos`)));
  await assertSucceeds(listAll(ref(storage, `users/${ownerId}/videos`)));

  await assertSucceeds(
    uploadBytes(
      ref(storage, `users/${ownerId}/photos/92A3B4C5-D6E7-4089-A123-B4C5D6E7F809.jpg`),
      jpegBytes,
      { contentType: 'image/jpeg' }
    )
  );
  await assertSucceeds(
    uploadBytes(
      ref(storage, `users/${ownerId}/videos/A3B4C5D6-E7F8-4190-B234-C5D6E7F8091A.mov`),
      mp4Bytes,
      { contentType: 'video/quicktime' }
    )
  );

  await assertSucceeds(deleteObject(ref(storage, ownedPhotoPath)));
  await assertSucceeds(deleteObject(ref(storage, ownedVideoPath)));
});

test('another climber cannot read, list, or delete owner-scoped workout media', async () => {
  const storage = testEnv.authenticatedContext(intruderId).storage();

  await assertFails(getBytes(ref(storage, ownedPhotoPath)));
  await assertFails(getBytes(ref(storage, ownedVideoPath)));
  await assertFails(listAll(ref(storage, `users/${ownerId}/photos`)));
  await assertFails(listAll(ref(storage, `users/${ownerId}/videos`)));
  await assertFails(deleteObject(ref(storage, ownedPhotoPath)));
  await assertFails(deleteObject(ref(storage, ownedVideoPath)));
});

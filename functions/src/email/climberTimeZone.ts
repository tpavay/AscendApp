import * as admin from "firebase-admin";
import {DEFAULT_BIRTHDAY_TIME_ZONE, isValidTimeZone} from "./birthday";

/** Devices read per climber to find the newest one that reported a zone. */
const DEVICES_READ_PER_CLIMBER = 5;

/**
 * Finds the zone a climber's newest device reported, which is how the birthday
 * email picks their morning and the trial reminder names their charge date.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<string>} A valid IANA zone, or the default
 */
export async function resolveClimberTimeZone(
  firestore: admin.firestore.Firestore,
  uid: string
): Promise<string> {
  const devices = await firestore
    .collection("users")
    .doc(uid)
    .collection("notification_devices")
    .orderBy("lastSeenAt", "desc")
    .limit(DEVICES_READ_PER_CLIMBER)
    .get();
  for (const device of devices.docs) {
    const zone = device.get("timeZone");
    if (typeof zone === "string" && isValidTimeZone(zone)) {
      return zone;
    }
  }
  return DEFAULT_BIRTHDAY_TIME_ZONE;
}

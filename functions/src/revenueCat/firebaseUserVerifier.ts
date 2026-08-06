import * as admin from "firebase-admin";
import type {FirebaseUserVerifier} from "./types";

export class AdminFirebaseUserVerifier implements FirebaseUserVerifier {
  async isFirebaseUser(uid: string): Promise<boolean> {
    try {
      await admin.auth().getUser(uid);
      return true;
    } catch (error) {
      if (isUserNotFoundError(error)) {
        return false;
      }
      throw error;
    }
  }
}

function isUserNotFoundError(error: unknown): boolean {
  return error !== null && typeof error === "object" &&
    "code" in error && error.code === "auth/user-not-found";
}

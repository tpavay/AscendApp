export const BUILD_UPLOAD_STATES = new Set([
  "AWAITING_UPLOAD",
  "PROCESSING",
  "FAILED",
  "COMPLETE",
]);

export function readBuildUploadState(upload) {
  return upload?.attributes?.state?.state;
}

export function buildUploadState(upload) {
  const state = readBuildUploadState(upload);
  if (!BUILD_UPLOAD_STATES.has(state)) {
    throw new Error(
      `App Store Connect returned unknown build upload state '${state ?? "(missing)"}'.`,
    );
  }
  return state;
}

export function buildUploadFailureSummary(upload) {
  const state = upload?.attributes?.state ?? {};
  const details = ["errors", "warnings", "infos"]
    .flatMap((kind) => state[kind] ?? [])
    .map((detail) => detail?.message ?? detail?.description ?? detail?.code)
    .filter(Boolean);

  return details.length > 0 ? details.join("; ") : "Apple reported no failure details";
}

// Apple explicitly permits reusing the build number of a failed upload.
// Every other state is an active or completed reservation that a later
// allocator must not collide with. An unknown or missing state is read as a
// reservation rather than a fault: the allocator sweeps the whole upload
// history, so one record Apple starts reporting differently would otherwise
// block every deploy for the app instead of costing a single build number.
export function buildUploadReservesNumber(upload) {
  return readBuildUploadState(upload) !== "FAILED";
}

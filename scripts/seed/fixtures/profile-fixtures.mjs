import {canonicalWorkoutDocumentId} from "../../lib/workout-document-id.mjs";

export const PROFILE_SEED_PACK_ID = "v1-profile-test";
export const PROFILE_SEED_SOURCE = "seed-test-users";
export const PROFILE_SCHEMA_VERSION = 2;

export const LEADERBOARD_TIME_FRAMES = [
  "daily",
  "weekly",
  "monthly",
  "yearly",
  "all_time",
];

export const PROFILE_SEED_PERSONAS = [
  {id: "profile_veteran_champion", name: "Tyler R.", age: 32, gender: "man", weightLb: 178, country: "US", region: "IL", climbs: 47, firstAscents: 4, top1: 3, top3: 11, top10: 18, top100: 31, streak: 15, weeklySteps: 42000, climbIds: ["empire-state-building", "space-needle", "statue-of-liberty", "burj-khalifa", "eiffel-tower"]},
  {id: "profile_newcomer", name: "Jonas B.", age: 27, gender: "man", weightLb: 165, country: "DE", region: "BE", climbs: 0, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 0, streak: 0, joinedOffsetDays: -1, climbIds: []},
  {id: "profile_active_recent", name: "Mara S.", age: 41, gender: "woman", weightLb: 145, country: "AU", region: "NSW", climbs: 6, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 0, streak: 3, climbIds: ["sydney-tower", "space-needle", "statue-of-liberty"]},
  {id: "profile_fa_collector", name: "Ren K.", age: 28, gender: "non_binary", weightLb: 152, country: "JP", region: "13", climbs: 8, firstAscents: 5, top1: 0, top3: 0, top10: 0, top100: 0, streak: 4, climbIds: ["tokyo-tower", "tokyo-skytree", "cairo-tower", "gateway-arch"]},
  {id: "profile_medal_heavy", name: "Naledi M.", age: 55, gender: "woman", weightLb: 168, country: "ZA", region: "WC", climbs: 22, firstAscents: 0, top1: 1, top3: 6, top10: 14, top100: 22, streak: 8, climbIds: ["table-mountain", "eiffel-tower", "cn-tower", "gateway-arch"]},
  {id: "profile_peer_veteran", name: "Caleb H.", age: 27, gender: "man", weightLb: 175, country: "US", region: "TX", climbs: 5, firstAscents: 0, top1: 0, top3: 1, top10: 2, top100: 5, streak: 2, climbIds: ["empire-state-building", "space-needle", "statue-of-liberty"]},
  {id: "profile_no_overlap_peer", name: "Dayo A.", age: 27, gender: "man", weightLb: 180, country: "NG", region: "LA", climbs: 4, firstAscents: 0, top1: 0, top3: 0, top10: 1, top100: 4, streak: 1, climbIds: ["cairo-tower", "sagrada-familia", "colosseum", "leaning-tower-of-pisa"]},
  {id: "profile_tied_gold", name: "Mateo G.", age: 30, gender: "man", weightLb: 170, country: "ES", region: "MD", climbs: 12, firstAscents: 1, top1: 1, top3: 2, top10: 6, top100: 12, streak: 5, weeklySteps: 42000, climbIds: ["sagrada-familia", "gateway-arch", "eiffel-tower"]},
  {id: "profile_streak_heavy", name: "Hana W.", age: 35, gender: "woman", weightLb: 138, country: "NZ", region: "AUK", climbs: 33, firstAscents: 1, top1: 0, top3: 4, top10: 9, top100: 20, streak: 28, climbIds: ["sky-tower-auckland", "sydney-tower", "space-needle"]},
  {id: "profile_privacy_edge", name: "Anika P.", age: 19, gender: "woman", weightLb: 110, country: "IN", region: "MH", climbs: 3, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 1, streak: 1, climbIds: ["gateway-arch", "statue-of-liberty"]},
  {id: "profile_older_athlete", name: "Victor P.", age: 68, gender: "man", weightLb: 195, country: "US", region: "AZ", climbs: 18, firstAscents: 1, top1: 0, top3: 2, top10: 8, top100: 18, streak: 9, climbIds: ["willis-tower", "one-world-trade-center", "empire-state-building"]},
  {id: "profile_empty_achievements", name: "Linnea S.", age: 24, gender: "non_binary", weightLb: 160, country: "SE", region: "AB", climbs: 2, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 0, streak: 1, climbIds: ["space-needle", "statue-of-liberty"]},
];

export const PROFILE_FIELD_SETS = {
  user: new Set([
    "email",
    "firstName",
    "lastName",
    "displayName",
    "profilePictureURL",
    "age",
    "gender",
    "weight_kg",
    "height_cm",
    "location_country",
    "location_region",
    "joined_at",
    "createdAt",
    "lastUpdated",
  ]),
  publicProfile: new Set([
    "userId",
    "displayName",
    "photoURL",
    "age",
    "gender",
    "weight_kg",
    "height_cm",
    "location_country",
    "location_region",
    "joined_at",
    "lastUpdated",
  ]),
  profileStats: new Set([
    "total_climbs_completed",
    "total_first_ascents",
    "lifetime_total_steps",
    "lifetime_duration_seconds",
    "total_climbs",
    "average_steps_per_minute",
    "top_1_finishes",
    "top_3_finishes",
    "top_10_finishes",
    "top_100_finishes",
    "most_completed_climb_id",
    "current_streak_weeks",
    "best_streak_weeks",
    "pr_most_steps",
    "pr_longest_climb_seconds",
    "pr_highest_spm",
    "lastUpdated",
  ]),
  profileWorkout: new Set([
    "name",
    "startedAt",
    "durationSeconds",
    "steps",
    "source",
    "climbId",
    "climbTier",
    "climbCompletionStatus",
    "climbCompletionDurationSeconds",
    "lastUpdated",
  ]),
  leaderboardStats: new Set([
    "userId",
    "displayName",
    "photoURL",
    "timeFrame",
    "schemaVersion",
    "periodKey",
    "periodStartAt",
    "totalSteps",
    "totalFloors",
    "totalWorkouts",
    "totalDuration",
    "stepsPerMinute",
    "age",
    "weight_kg",
    "location_country",
    "location_region",
    "lastUpdated",
  ]),
};

export function buildProfileSeedWrites({
  db,
  catalog,
  Timestamp,
  FieldValue,
  avatarURLs = new Map(),
  now = new Date(),
  includeLeaderboardRows = true,
}) {
  const writes = [];

  for (const persona of PROFILE_SEED_PERSONAS) {
    const joinedAt = daysFromNow(persona.joinedOffsetDays ?? -60, now);
    const userRef = db.collection("users").doc(persona.id);
    const publicRef = userRef.collection("public_profile").doc("current");
    const statsRef = userRef.collection("profile_stats").doc("current");
    const workouts = buildWorkouts(persona, catalog, now, Timestamp, FieldValue);
    const stats = statsFor(persona, workouts);

    const photoURL = profilePhotoURL(persona, avatarURLs);

    writes.push(write(userRef, privateUserData(persona, joinedAt, photoURL, Timestamp, FieldValue), "user"));
    writes.push(write(publicRef, publicProfileData(persona, joinedAt, Timestamp, FieldValue), "publicProfile"));
    writes.push(write(statsRef, profileStatsData(stats, FieldValue), "profileStats"));

    for (const workout of workouts) {
      writes.push(write(userRef.collection("profile_workouts").doc(workout.id), workout.data, "profileWorkout"));
    }

    for (const achievement of buildAchievements(persona, now, Timestamp)) {
      writes.push({
        ref: userRef.collection("achievements").doc(achievement.id),
        data: achievement.data,
        shape: "achievement",
      });
    }

    if (includeLeaderboardRows) {
      writes.push(...leaderboardWritesForPersona(db, persona, stats, now, Timestamp, FieldValue));
    }
  }

  return writes;
}

export function buildLeaderboardSeedWrites({
  db,
  catalog,
  Timestamp,
  FieldValue,
  now = new Date(),
}) {
  return PROFILE_SEED_PERSONAS.flatMap((persona) => {
    const workouts = buildWorkouts(persona, catalog, now, Timestamp, FieldValue);
    const stats = statsFor(persona, workouts);
    return leaderboardWritesForPersona(db, persona, stats, now, Timestamp, FieldValue);
  });
}

export function expectedProfileUserIds() {
  return PROFILE_SEED_PERSONAS.map((persona) => persona.id);
}

export function expectedLeaderboardDocIds() {
  return PROFILE_SEED_PERSONAS.flatMap((persona) =>
    LEADERBOARD_TIME_FRAMES.map((timeFrame) => {
      const period = currentPeriod(timeFrame);
      return leaderboardDocId(persona.id, timeFrame, period.key);
    })
  );
}

export function legacyLeaderboardDocIds() {
  return PROFILE_SEED_PERSONAS.flatMap((persona) =>
    LEADERBOARD_TIME_FRAMES.map((timeFrame) => `${persona.id}_${timeFrame}`)
  );
}

export function leaderboardDocId(userId, timeFrame, periodKey) {
  return `${timeFrame}_${periodKey}_${userId}`;
}

export function validateSeedWrite(writeItem) {
  const allowed = PROFILE_FIELD_SETS[writeItem.shape];
  if (!allowed) {
    return;
  }

  const extra = Object.keys(writeItem.data).filter((key) => !allowed.has(key));
  if (extra.length > 0) {
    throw new Error(
      `${writeItem.ref.path} has field(s) outside ${writeItem.shape}: ${extra.join(", ")}`
    );
  }
}

export function validateDocumentKeys(path, data, shape, failures) {
  const allowed = PROFILE_FIELD_SETS[shape];
  if (!allowed) {
    return;
  }

  const extra = Object.keys(data).filter((key) => !allowed.has(key));
  if (extra.length > 0) {
    failures.push(`${path} has unexpected field(s): ${extra.join(", ")}`);
  }
}

export function statsFromWorkoutDocuments(workouts) {
  const lifetimeSteps = workouts.reduce((sum, workout) => sum + integerValue(workout.steps), 0);
  const lifetimeDuration = workouts.reduce((sum, workout) => sum + numberValue(workout.durationSeconds), 0);
  const completed = workouts.filter((workout) => workout.climbCompletionStatus === "completed").length;
  const maxSteps = Math.max(0, ...workouts.map((workout) => integerValue(workout.steps)));
  const maxDuration = Math.max(0, ...workouts.map((workout) => numberValue(workout.durationSeconds)));
  const maxSpm = Math.max(0, ...workouts.map((workout) => {
    const duration = numberValue(workout.durationSeconds);
    return duration > 0 ? integerValue(workout.steps) / (duration / 60) : 0;
  }));

  return {
    total_climbs_completed: completed,
    lifetime_total_steps: lifetimeSteps,
    lifetime_duration_seconds: Math.round(lifetimeDuration),
    total_climbs: workouts.length,
    average_steps_per_minute: lifetimeDuration > 0 ? lifetimeSteps / (lifetimeDuration / 60) : 0,
    pr_most_steps: maxSteps,
    pr_longest_climb_seconds: Math.round(maxDuration),
    pr_highest_spm: maxSpm,
  };
}

export function currentPeriod(timeFrameKey, date = new Date()) {
  switch (timeFrameKey) {
    case "daily": {
      const year = date.getUTCFullYear();
      const month = date.getUTCMonth() + 1;
      const day = date.getUTCDate();
      return {
        key: `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
        startAt: utcDate(year, month - 1, day),
      };
    }
    case "weekly": {
      const {year, week, startAt} = weekInfoUTC(date);
      return {
        key: `${year}-W${String(week).padStart(2, "0")}`,
        startAt,
      };
    }
    case "monthly": {
      const year = date.getUTCFullYear();
      const month = date.getUTCMonth() + 1;
      return {
        key: `${year}-M${String(month).padStart(2, "0")}`,
        startAt: utcDate(year, month - 1, 1),
      };
    }
    case "yearly": {
      const year = date.getUTCFullYear();
      return {
        key: `${year}`,
        startAt: utcDate(year, 0, 1),
      };
    }
    case "all_time":
      return {
        key: "all",
        startAt: new Date(0),
      };
    default:
      throw new Error(`Unknown time frame: ${timeFrameKey}`);
  }
}

function write(ref, data, shape) {
  const item = {ref, data, shape};
  validateSeedWrite(item);
  return item;
}

function privateUserData(persona, joinedAt, photoURL, Timestamp, FieldValue) {
  return {
    email: `${persona.id}@example.invalid`,
    firstName: persona.name.split(" ")[0],
    lastName: persona.name.split(" ").slice(1).join(" "),
    displayName: persona.name,
    profilePictureURL: photoURL,
    age: persona.age,
    gender: persona.gender,
    weight_kg: poundsToKg(persona.weightLb),
    height_cm: heightCmFor(persona),
    location_country: persona.country,
    location_region: persona.region,
    joined_at: Timestamp.fromDate(joinedAt),
    createdAt: Timestamp.fromDate(joinedAt),
    lastUpdated: FieldValue.serverTimestamp(),
  };
}

function publicProfileData(persona, joinedAt, Timestamp, FieldValue) {
  return {
    userId: persona.id,
    displayName: "Climber",
    photoURL: "",
    age: persona.age,
    gender: persona.gender,
    weight_kg: poundsToKg(persona.weightLb),
    height_cm: heightCmFor(persona),
    location_country: persona.country,
    location_region: persona.region,
    joined_at: Timestamp.fromDate(joinedAt),
    lastUpdated: FieldValue.serverTimestamp(),
  };
}

function profileStatsData(stats, FieldValue) {
  return {
    ...stats,
    lastUpdated: FieldValue.serverTimestamp(),
  };
}

function buildWorkouts(persona, catalog, now, Timestamp, FieldValue) {
  const workouts = [];
  for (let index = 0; index < persona.climbs; index += 1) {
    const climbId = persona.climbIds[index % Math.max(persona.climbIds.length, 1)];
    const climb = catalog.get(climbId);
    const steps = climb?.realStairCount ?? climb?.totalSteps ?? 1000 + index * 50;
    const durationSeconds = Math.max(360, Math.floor(steps / (72 + (index % 16)) * 60));
    const date = new Date(now.getTime() - index * 2 * 24 * 60 * 60 * 1000);
    const data = {
      name: climb ? `${climb.name} Climb` : "Stair Climb",
      startedAt: Timestamp.fromDate(date),
      durationSeconds,
      steps,
      source: climb ? "headphone_motion" : "manual",
      lastUpdated: FieldValue.serverTimestamp(),
    };

    if (climb) {
      data.climbId = climb.id;
      data.climbTier = climb.tier ?? "common";
      data.climbCompletionStatus = "completed";
      data.climbCompletionDurationSeconds = durationSeconds;
    }

    workouts.push({
      id: deterministicUUID(`${persona.id}-${index}`),
      data,
    });
  }

  return workouts;
}

function statsFor(persona, workouts) {
  const workoutData = workouts.map((workout) => workout.data);
  const derived = statsFromWorkoutDocuments(workoutData);
  const climbCounts = new Map();
  for (const workout of workoutData) {
    if (workout.climbId) {
      climbCounts.set(workout.climbId, (climbCounts.get(workout.climbId) ?? 0) + 1);
    }
  }
  const mostCompleted = [...climbCounts.entries()]
    .sort((lhs, rhs) => rhs[1] - lhs[1] || lhs[0].localeCompare(rhs[0]))[0]?.[0] ?? "";

  return {
    total_climbs_completed: derived.total_climbs_completed,
    total_first_ascents: Math.min(persona.firstAscents, derived.total_climbs_completed),
    lifetime_total_steps: derived.lifetime_total_steps,
    lifetime_duration_seconds: derived.lifetime_duration_seconds,
    total_climbs: derived.total_climbs,
    average_steps_per_minute: derived.average_steps_per_minute,
    top_1_finishes: persona.top1,
    top_3_finishes: persona.top3,
    top_10_finishes: persona.top10,
    top_100_finishes: persona.top100,
    most_completed_climb_id: mostCompleted,
    current_streak_weeks: persona.streak,
    best_streak_weeks: Math.max(persona.streak, persona.streak + 3),
    pr_most_steps: derived.pr_most_steps,
    pr_longest_climb_seconds: derived.pr_longest_climb_seconds,
    pr_highest_spm: derived.pr_highest_spm,
  };
}

function leaderboardWritesForPersona(db, persona, stats, now, Timestamp, FieldValue) {
  return LEADERBOARD_TIME_FRAMES
    .map((timeFrame) => leaderboardDataForPersona(persona, stats, timeFrame, now, Timestamp, FieldValue))
    .filter((data) => data.totalSteps > 0)
    .map((data) => {
      const docId = leaderboardDocId(persona.id, data.timeFrame, data.periodKey);
      return write(db.collection("leaderboard_stats").doc(docId), data, "leaderboardStats");
    });
}

function leaderboardDataForPersona(persona, stats, timeFrame, now, Timestamp, FieldValue) {
  const period = currentPeriod(timeFrame, now);
  const totalSteps = leaderboardSteps(persona, stats, timeFrame);
  const totalWorkouts = totalSteps > 0
    ? Math.max(1, Math.min(stats.total_climbs, Math.ceil(totalSteps / 2200)))
    : 0;
  const stepsPerMinute = stats.average_steps_per_minute > 0
    ? stats.average_steps_per_minute
    : 78;

  return {
    userId: persona.id,
    displayName: "Climber",
    photoURL: "",
    timeFrame,
    schemaVersion: PROFILE_SCHEMA_VERSION,
    periodKey: period.key,
    periodStartAt: Timestamp.fromDate(period.startAt),
    totalSteps,
    totalFloors: Math.floor(totalSteps / 16),
    totalWorkouts,
    totalDuration: totalSteps > 0 ? totalSteps / stepsPerMinute * 60 : 0,
    stepsPerMinute,
    age: persona.age,
    weight_kg: poundsToKg(persona.weightLb),
    location_country: persona.country,
    location_region: persona.region,
    lastUpdated: FieldValue.serverTimestamp(),
  };
}

function leaderboardSteps(persona, stats, timeFrame) {
  const lifetimeSteps = stats.lifetime_total_steps;
  const weekly = persona.weeklySteps ??
    Math.min(lifetimeSteps, Math.max(0, Math.round(lifetimeSteps / Math.max(persona.streak || 4, 4))));

  switch (timeFrame) {
    case "daily":
      return Math.round(weekly / 6);
    case "weekly":
      return weekly;
    case "monthly":
      return Math.min(lifetimeSteps, Math.max(weekly, Math.round(lifetimeSteps * 0.35)));
    case "yearly":
      return lifetimeSteps;
    case "all_time":
      return lifetimeSteps;
    default:
      return 0;
  }
}

function buildAchievements(persona, now, Timestamp) {
  const achievements = [];
  addAchievements(achievements, persona, "weekly_top_1", persona.top1, now, Timestamp);
  addAchievements(achievements, persona, "weekly_top_3", persona.top3 - persona.top1, now, Timestamp);
  addAchievements(achievements, persona, "weekly_top_10", persona.top10 - persona.top3, now, Timestamp);
  addAchievements(achievements, persona, "weekly_top_100", persona.top100 - persona.top10, now, Timestamp);
  for (let index = 0; index < persona.firstAscents; index += 1) {
    achievements.push({
      id: `${persona.id}_first_ascent_${index}`,
      data: {
        type: "first_ascent",
        climbId: persona.climbIds[index % persona.climbIds.length] ?? "unknown",
        earnedAt: Timestamp.fromDate(daysFromNow(-90 - index, now)),
        rank: 1,
        source: PROFILE_SEED_SOURCE,
        seedPackId: PROFILE_SEED_PACK_ID,
      },
    });
  }
  return achievements;
}

function addAchievements(items, persona, type, count, now, Timestamp) {
  for (let index = 0; index < Math.max(count, 0); index += 1) {
    const periodStartAt = daysFromNow(-7 * (index + 2), now);
    const periodEndAt = daysFromNow(-7 * (index + 1), now);
    items.push({
      id: `${persona.id}_${type}_${index}`,
      data: {
        type,
        scope: "global",
        metric: "steps",
        value: Math.max(300, Math.round((persona.weeklySteps ?? 12000) - index * 175)),
        valueUnit: "steps",
        periodKey: `2026-W${String(20 - (index % 10)).padStart(2, "0")}`,
        periodStartAt: Timestamp.fromDate(periodStartAt),
        periodEndAt: Timestamp.fromDate(periodEndAt),
        earnedAt: Timestamp.fromDate(daysFromNow(-7 * (index + 1), now)),
        rank: rankForType(type),
        source: PROFILE_SEED_SOURCE,
        seedPackId: PROFILE_SEED_PACK_ID,
      },
    });
  }
}

function rankForType(type) {
  if (type.endsWith("top_1")) return 1;
  if (type.endsWith("top_3")) return 3;
  if (type.endsWith("top_10")) return 7;
  return 42;
}

function utcDate(year, month, day) {
  return new Date(Date.UTC(year, month, day));
}

function startOfUTCDay(date) {
  return utcDate(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

function startOfWeekUTC(date) {
  const start = startOfUTCDay(date);
  const daysSinceMonday = (start.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - daysSinceMonday);
  return start;
}

function weekInfoUTC(date) {
  const normalizedDate = startOfUTCDay(date);
  const weekStart = startOfWeekUTC(normalizedDate);
  const calendarYear = normalizedDate.getUTCFullYear();

  const firstWeekStart = startOfWeekUTC(utcDate(calendarYear, 0, 1));
  if (weekStart < firstWeekStart) {
    return weekInfoUTC(utcDate(calendarYear - 1, 11, 31));
  }

  const nextYearFirstWeekStart = startOfWeekUTC(utcDate(calendarYear + 1, 0, 1));
  if (weekStart >= nextYearFirstWeekStart) {
    return {
      year: calendarYear + 1,
      week: 1,
      startAt: weekStart,
    };
  }

  const diffMs = weekStart.getTime() - firstWeekStart.getTime();
  const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));
  return {
    year: calendarYear,
    week: Math.floor(diffDays / 7) + 1,
    startAt: weekStart,
  };
}

function poundsToKg(value) {
  return Math.round(value * 0.453592 * 10) / 10;
}

function heightCmFor(persona) {
  const baseInches = persona.gender === "woman" ? 66 : persona.gender === "non_binary" ? 68 : 70;
  const hash = [...persona.id].reduce((sum, char) => sum + char.charCodeAt(0), 0);
  return Math.round((baseInches + (hash % 7) - 3) * 2.54 * 10) / 10;
}

function daysFromNow(days, base = new Date()) {
  return new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
}

function avatarURL(name) {
  return `https://ui-avatars.com/api/?name=${encodeURIComponent(name)}&size=200&background=2F3136&color=fff&bold=true&format=png`;
}

function profilePhotoURL(persona, avatarURLs) {
  return avatarURLs.get(persona.id) ?? avatarURL(persona.name);
}

// These ids key `users/{uid}/profile_workouts` documents, which obey the one-spelling rule
// the private workout collection does, so the generator has to emit the canonical form or
// the fixtures reseed exactly the case variants the cleanup migration exists to remove.
function deterministicUUID(input) {
  let hash = 0;
  for (let index = 0; index < input.length; index += 1) {
    hash = (hash * 31 + input.charCodeAt(index)) >>> 0;
  }
  const hex = hash.toString(16).padStart(8, "0");
  return canonicalWorkoutDocumentId(
    `${hex.slice(0, 8)}-0000-4000-8000-${hex}${hex}`.slice(0, 36)
  );
}

function integerValue(value) {
  return Number.isFinite(Number(value)) ? Math.trunc(Number(value)) : 0;
}

function numberValue(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

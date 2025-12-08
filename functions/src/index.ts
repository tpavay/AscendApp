/**
 * Console Scan Cloud Function
 *
 * Scans stair stepper console photos using OpenAI Vision API
 * and extracts workout metrics (steps, floors, time, etc.)
 */

import {onRequest} from "firebase-functions/v2/https";
import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";
import OpenAI from "openai";

admin.initializeApp();

// Global options for cost control
setGlobalOptions({maxInstances: 10});

// ============================================
// TYPES & INTERFACES
// ============================================

interface ScanConfig {
  provider: "openai" | "anthropic" | "google";
  modelId: string;
  prompt: string;
  dailyLimit: number;
  enabled: boolean;
  imageDetail: "low" | "high" | "auto";
}

interface ConsoleMetrics {
  steps_climbed: number | null;
  floors_climbed: number | null;
  steps_per_minute: number | null;
  machine_level: number | null;
  calories: number | null;
  heart_rate_bpm: number | null;
  elapsed_time_seconds: number | null;
  notes: string | null;
}

// Provider abstraction - enables swapping OpenAI for Claude/Gemini later
interface VisionOcrProvider {
  scanConsole(imageBase64: string, config: ScanConfig): Promise<ConsoleMetrics>;
}

// ============================================
// OPENAI PROVIDER (Current Implementation)
// ============================================

const openAiProvider: VisionOcrProvider = {
  async scanConsole(
    imageBase64: string,
    config: ScanConfig
  ): Promise<ConsoleMetrics> {
    const openai = new OpenAI({apiKey: process.env.OPENAI_API_KEY});

    const response = await openai.chat.completions.create({
      model: config.modelId,
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: config.prompt},
            {
              type: "image_url",
              image_url: {
                url: `data:image/jpeg;base64,${imageBase64}`,
                detail: config.imageDetail,
              },
            },
          ],
        },
      ],
      max_tokens: 500,
    });

    const text = response.choices[0]?.message?.content || "{}";
    return JSON.parse(text);
  },
};

// Add later: anthropicProvider, googleProvider

/**
 * Get the appropriate vision provider based on config
 * @param {ScanConfig} config - The scan configuration
 * @return {VisionOcrProvider} The vision provider instance
 */
function getProvider(config: ScanConfig): VisionOcrProvider {
  switch (config.provider) {
  case "openai":
    return openAiProvider;
    // case "anthropic": return anthropicProvider;  // Future
    // case "google": return googleProvider;        // Future
  default:
    throw new Error(`Unsupported provider: ${config.provider}`);
  }
}

// ============================================
// CONFIG (Cached from Firestore)
// ============================================

// In-memory cache to avoid Firestore read on every request
let cachedConfig: ScanConfig | null = null;
let lastConfigFetch = 0;
const CONFIG_TTL_MS = 60_000; // 1 minute cache

/* eslint-disable max-len */
const DEFAULT_PROMPT = `You are a vision + OCR assistant specialized in reading stair stepper / stair climber gym machine consoles.

Goal: Extract all visible workout metrics from the image of the stair stepper console and return them in the JSON schema below.

Rules:
1. Treat every metric as independent. Do not assume metrics toggle in/out.
2. Do NOT convert between steps and floors. If it says FLOORS, map to floors_climbed. If it says STEPS, map to steps_climbed.
3. SPM explicitly maps to steps_per_minute. Accepted labels: STEPS/MIN, SPM, STEPS PER MIN.
4. Only report numbers actually visible. If something is missing or too blurry, use null.
5. Convert all visible times into seconds. Acceptable formats: MM:SS, HH:MM:SS.
6. Distance: DIST, DISTANCE - extract if visible.
7. Heart rate: HR, HEART RATE, BPM, heart icon + number.
8. Level/resistance: LEVEL, RESISTANCE.

OUTPUT: Return ONLY a valid JSON object. Do not wrap it in backticks or markdown. Do not include any commentary.
{
  "steps_climbed": <int or null>,
  "floors_climbed": <float or int or null>,
  "steps_per_minute": <float or int or null>,
  "machine_level": <float or int or null>,
  "calories": <float or int or null>,
  "heart_rate_bpm": <int or null>,
  "elapsed_time_seconds": <int or null>,
  "notes": "<short explanation of any ambiguities>"
}`;
/* eslint-enable max-len */

/**
 * Get config from Firestore with caching
 */
async function getConfig(): Promise<ScanConfig> {
  const now = Date.now();
  if (cachedConfig && now - lastConfigFetch < CONFIG_TTL_MS) {
    return cachedConfig;
  }

  const doc = await admin.firestore().doc("config/consoleScan").get();
  if (!doc.exists) {
    // Default config if document doesn't exist yet
    cachedConfig = {
      provider: "openai",
      modelId: "gpt-4.1-mini",
      prompt: DEFAULT_PROMPT,
      dailyLimit: 5,
      enabled: true,
      imageDetail: "high",
    };
  } else {
    cachedConfig = doc.data() as ScanConfig;
  }

  lastConfigFetch = now;
  return cachedConfig;
}

// ============================================
// MAIN CLOUD FUNCTION
// ============================================

export const consoleScan = onRequest(
  {
    secrets: ["OPENAI_API_KEY"],
    timeoutSeconds: 60, // Vision API can take 10-20 seconds
    memory: "256MiB",
  },
  async (req, res) => {
    try {
      // 1. Verify Firebase Auth token
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ?
        authHeader.substring(7) :
        null;

      if (!idToken) {
        res.status(401).send({error: "Missing auth token"});
        return;
      }

      const decoded = await admin.auth().verifyIdToken(idToken);
      const uid = decoded.uid;

      // 2. Load config from Firestore (allows updates without redeploy)
      const config = await getConfig();

      if (!config.enabled) {
        res.status(503).send({
          error: "Console scanning is temporarily disabled",
        });
        return;
      }

      // 3. Rate limit check
      const usageRef = admin.firestore()
        .collection("consoleScanUsage")
        .doc(uid);
      const today = new Date().toISOString().substring(0, 10);

      await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(usageRef);
        let dailyCount = 0;
        let lastDate = today;

        if (snap.exists) {
          const data = snap.data();
          if (data) {
            lastDate = data.lastDate || today;
            dailyCount = data.dailyCount || 0;
          }

          if (lastDate !== today) {
            dailyCount = 0;
          }
        }

        if (dailyCount >= config.dailyLimit) {
          throw new Error("RATE_LIMIT_EXCEEDED");
        }

        tx.set(
          usageRef,
          {lastDate: today, dailyCount: dailyCount + 1},
          {merge: true}
        );
      });

      // 4. Get image from request
      const imageBase64 = req.body.imageBase64;
      if (!imageBase64) {
        res.status(400).send({error: "Missing imageBase64"});
        return;
      }

      // 5. Call vision provider (abstracted for future Claude/Gemini support)
      const provider = getProvider(config);

      let metrics: ConsoleMetrics;
      try {
        metrics = await provider.scanConsole(imageBase64, config);
      } catch (providerError) {
        // Handle provider-level errors (network, API issues)
        console.error("Provider error:", providerError);
        throw new Error("PROVIDER_ERROR");
      }

      // Validate we got a valid metrics object
      if (typeof metrics !== "object" || metrics === null) {
        console.error("Invalid metrics object received");

        await admin.firestore().collection("consoleScanLogs").add({
          uid,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          model: config.modelId,
          provider: config.provider,
          success: false,
          errorType: "INVALID_RESPONSE",
        });

        res.status(502).send({
          error: "Unable to interpret console image. Try a clearer photo.",
        });
        return;
      }

      // 6. Log for debugging/metrics (richer logging)
      await admin.firestore().collection("consoleScanLogs").add({
        uid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        provider: config.provider,
        model: config.modelId,
        success: true,
        metricsFound: {
          hasSteps: metrics.steps_climbed !== null,
          hasFloors: metrics.floors_climbed !== null,
          hasTime: metrics.elapsed_time_seconds !== null,
          hasCalories: metrics.calories !== null,
          hasHeartRate: metrics.heart_rate_bpm !== null,
          total: Object.keys(metrics).filter(
            (k) => metrics[k as keyof ConsoleMetrics] !== null
          ).length,
        },
      });

      // 7. Return metrics
      res.status(200).send(metrics);
    } catch (err) {
      const error = err as Error;
      console.error("consoleScan error:", error);

      if (error.message === "RATE_LIMIT_EXCEEDED") {
        res.status(429).send({error: "Daily scan limit reached (5 per day)"});
        return;
      }

      // Specific message for OpenAI/network failures
      res.status(500).send({
        error: "Server error while reading console. Try again in a minute.",
      });
    }
  }
);

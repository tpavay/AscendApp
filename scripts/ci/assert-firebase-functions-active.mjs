#!/usr/bin/env node

const expectedFunctionIds = process.argv.slice(2);
const payload = JSON.parse(await readStandardInput());

if (expectedFunctionIds.length === 0) {
  throw new Error("Pass at least one expected Firebase Function id");
}

if (payload.status !== "success" || !Array.isArray(payload.result)) {
  throw new Error("Firebase functions:list did not return a successful result array");
}

const deployedFunctions = new Map(
  payload.result.map((deployedFunction) => [deployedFunction.id, deployedFunction])
);
const inactive = expectedFunctionIds.filter((functionId) => {
  const deployedFunction = deployedFunctions.get(functionId);
  return deployedFunction?.state !== "ACTIVE";
});

if (inactive.length > 0) {
  console.error(`Missing or inactive Firebase Functions: ${inactive.join(", ")}`);
  process.exitCode = 1;
} else {
  console.log(`Verified ACTIVE Firebase Functions: ${expectedFunctionIds.join(", ")}`);
}

async function readStandardInput() {
  const chunks = [];

  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  return Buffer.concat(chunks).toString("utf8");
}

import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {evaluate, readBaseline, readSchemaFacts} from "../check-swiftdata-schema.mjs";
import {
  checkModelSetAgreement,
  checkShapeDelta,
  parseMigrationPlan,
  parseModels,
  parseVersionedSchema,
  shapeOf,
} from "../lib/swiftdata-schema-shape.mjs";

const PLAN = {customStageCount: 1, lightweightStageCount: 0, schemas: ["V1", "V2"]};
const SCHEMA_V2 = {name: "AscendSchemaV2", versionIdentifier: [2, 0, 0], models: ["Workout"]};
const SCHEMA_V3 = {name: "AscendSchemaV3", versionIdentifier: [3, 0, 0], models: ["Workout"]};

/**
 * A store that already holds rows, with the mix Ascend actually has: required columns that carry no
 * default because they were there from the start, and optional ones that were added later.
 */
const BASELINE = {
  currentSchema: "AscendSchemaV2",
  versionIdentifier: [2, 0, 0],
  customStageCount: 1,
  lightweightStageCount: 0,
  models: {
    Workout: {
      id: {optional: false, hasDefault: false},
      name: {optional: false, hasDefault: false},
      notes: {optional: true, hasDefault: false},
    },
  },
  frozenModels: {
    "AscendSchemaV1.Workout": {id: {optional: false, hasDefault: false}},
  },
};

/** @param {object} overrides Fields to replace. @return {object} A delta-check input. */
function deltaInput(overrides = {}) {
  return {
    baseline: BASELINE,
    currentShape: BASELINE.models,
    frozenShape: BASELINE.frozenModels,
    plan: PLAN,
    currentSchema: SCHEMA_V2,
    ...overrides,
  };
}

test("the repository's own schema passes both checks", () => {
  const facts = readSchemaFacts();
  const {violations, baselineStale} = evaluate(facts, readBaseline());

  assert.deepEqual(violations, []);
  assert.equal(
    baselineStale,
    false,
    "SharedTestVectors/swiftdata-schema-shape.json is out of date; " +
    "run `node scripts/check-swiftdata-schema.mjs --update`"
  );
  assert.equal(facts.currentSchema.name, facts.containerSchema);
});

test("CI runs this check on any app-source change", () => {
  // An @Model can be declared anywhere under AscendApp, so a filter narrowed to
  // the folders models live in today would let the next one ship unchecked.
  const workflow = readFileSync(
    fileURLToPath(new URL("../../.github/workflows/ci.yml", import.meta.url)),
    "utf-8"
  );
  const scriptsFilter = workflow.slice(
    workflow.indexOf("            scripts:\n"),
    workflow.indexOf("            web:\n")
  );

  assert.match(scriptsFilter, /- "AscendApp\/\*\*"/);
  assert.match(scriptsFilter, /- "SharedTestVectors\/\*\*"/);
});

test("an unchanged model set with no shape change is clean", () => {
  assert.deepEqual(checkShapeDelta(deltaInput()), []);
  assert.deepEqual(checkModelSetAgreement({
    liveModels: ["Workout"],
    currentSchema: SCHEMA_V2,
    planSchemas: ["AscendSchemaV1", "AscendSchemaV2"],
    containerSchema: "AscendSchemaV2",
  }), []);
});

test("a model missing from the versioned schema fails, and so does the reverse", () => {
  const missingFromSchema = checkModelSetAgreement({
    liveModels: ["Workout", "Routine"],
    currentSchema: SCHEMA_V2,
    planSchemas: ["AscendSchemaV1", "AscendSchemaV2"],
    containerSchema: "AscendSchemaV2",
  });
  assert.equal(missingFromSchema.length, 1);
  assert.match(missingFromSchema[0], /Routine is declared but missing from AscendSchemaV2\.models/);

  const missingFromModels = checkModelSetAgreement({
    liveModels: [],
    currentSchema: SCHEMA_V2,
    planSchemas: ["AscendSchemaV1", "AscendSchemaV2"],
    containerSchema: "AscendSchemaV2",
  });
  assert.equal(missingFromModels.length, 1);
  assert.match(missingFromModels[0], /lists Workout, which is not a declared @Model type/);
});

test("a plan or container pointing at a stale schema fails", () => {
  const staleplan = checkModelSetAgreement({
    liveModels: ["Workout"],
    currentSchema: SCHEMA_V3,
    planSchemas: ["AscendSchemaV1", "AscendSchemaV2"],
    containerSchema: "AscendSchemaV3",
  });
  assert.match(staleplan[0], /schemas ends at AscendSchemaV2.*newest versioned schema is AscendSchemaV3/s);

  const staleContainer = checkModelSetAgreement({
    liveModels: ["Workout"],
    currentSchema: SCHEMA_V3,
    planSchemas: ["AscendSchemaV1", "AscendSchemaV3"],
    containerSchema: "AscendSchemaV2",
  });
  assert.match(staleContainer[0], /opens its store with AscendSchemaV2/);
});

test("a new required property with no default and no custom stage fails", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {
        ...BASELINE.models.Workout,
        cadence: {optional: false, hasDefault: false},
      },
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.cadence is new, non-optional, and has no default/);
  assert.match(violations[0], /make it optional; give it a default.*or add a custom MigrationStage/s);
});

test("the same property passes optional, defaulted, or backed by a new custom stage", () => {
  const optional = checkShapeDelta(deltaInput({
    currentShape: {Workout: {...BASELINE.models.Workout, cadence: {optional: true, hasDefault: false}}},
    currentSchema: SCHEMA_V3,
  }));
  assert.deepEqual(optional, []);

  const defaulted = checkShapeDelta(deltaInput({
    currentShape: {Workout: {...BASELINE.models.Workout, cadence: {optional: false, hasDefault: true}}},
    currentSchema: SCHEMA_V3,
  }));
  assert.deepEqual(defaulted, []);

  // The third route: a blanket value would be a lie, so a stage computes one per record. This is
  // what AscendMigrationPlan.migrateV1toV2 does for Workout.source.
  const staged = checkShapeDelta(deltaInput({
    currentShape: {Workout: {...BASELINE.models.Workout, cadence: {optional: false, hasDefault: false}}},
    plan: {...PLAN, customStageCount: 2},
    currentSchema: SCHEMA_V3,
  }));
  assert.deepEqual(staged, []);
});

test("an existing required property with no default is not a defect", () => {
  // The default is only ever consulted when the property is new. Sweeping defaults onto columns
  // that already hold values buys nothing, so the check must stay silent about them.
  assert.deepEqual(checkShapeDelta(deltaInput()), []);
});

test("turning an existing optional property required without a default fails", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {Workout: {...BASELINE.models.Workout, notes: {optional: false, hasDefault: false}}},
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.notes is newly required/);
});

test("a brand new model is exempt, because it has no existing rows", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      ...BASELINE.models,
      Streak: {id: {optional: false, hasDefault: false}, length: {optional: false, hasDefault: false}},
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.deepEqual(violations, []);
});

test("changing the shape without a new schema version fails", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {Workout: {...BASELINE.models.Workout, cadence: {optional: true, hasDefault: false}}},
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /AscendSchemaV2 is still the newest versioned schema/);
});

test("editing or deleting a shipped historical schema fails", () => {
  const edited = checkShapeDelta(deltaInput({
    frozenShape: {"AscendSchemaV1.Workout": {id: {optional: true, hasDefault: false}}},
  }));
  assert.match(edited[0], /frozen historical model AscendSchemaV1\.Workout changed/);

  const deleted = checkShapeDelta(deltaInput({frozenShape: {}}));
  assert.match(deleted[0], /frozen historical model AscendSchemaV1\.Workout was deleted/);
});

test("only stored properties count as columns", () => {
  const source = `
    import SwiftData

    @Model
    final class Sample {
        static let pageSize = 100

        var id: UUID
        var label: String = "unnamed"
        var note: String?
        @Attribute(originalName: "old") var renamed: Int = 0
        @Transient var scratch: Int = 0
        var levels: [Int: Set<String>] = [:]

        var derived: String {
            get { label }
            set { label = newValue }
        }

        func recompute() {
            var local = 0
            _ = local
        }
    }
  `;

  const [model] = parseModels(source, "Sample.swift");
  assert.equal(model.name, "Sample");
  assert.equal(model.nested, false);
  assert.deepEqual(shapeOf([model]).Sample, {
    id: {optional: false, hasDefault: false},
    label: {optional: false, hasDefault: true},
    levels: {optional: false, hasDefault: true},
    note: {optional: true, hasDefault: false},
    renamed: {optional: false, hasDefault: true},
  });
});

test("a model nested inside a historical schema is read as frozen", () => {
  const source = `
    extension AscendSchemaV1 {
        @Model
        final class Workout {
            var id: UUID = UUID()
        }
    }
  `;

  const [model] = parseModels(source, "AscendSchemaV1.swift");
  assert.equal(model.nested, true);
});

test("versioned schemas and migration plans are read from their declarations", () => {
  const schema = parseVersionedSchema(`
    enum AscendSchemaV2: VersionedSchema {
        static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

        static var models: [any PersistentModel.Type] {
            [
                Workout.self,
                Routine.self
            ]
        }
    }
  `, "AscendSchemaV2.swift");

  assert.deepEqual(schema, {
    name: "AscendSchemaV2",
    versionIdentifier: [2, 0, 0],
    models: ["Workout", "Routine"],
  });

  const plan = parseMigrationPlan(`
    enum AscendMigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            [AscendSchemaV1.self, AscendSchemaV2.self]
        }

        static var stages: [MigrationStage] { [migrateV1toV2] }

        static let migrateV1toV2 = MigrationStage.custom(
            fromVersion: AscendSchemaV1.self,
            toVersion: AscendSchemaV2.self,
            willMigrate: { _ in },
            didMigrate: { _ in }
        )
    }
  `, "AscendMigrationPlan.swift");

  assert.deepEqual(plan, {
    schemas: ["AscendSchemaV1", "AscendSchemaV2"],
    customStageCount: 1,
    lightweightStageCount: 0,
  });
});

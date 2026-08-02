import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {evaluate, readBaseline, readSchemaFacts} from "../check-swiftdata-schema.mjs";
import {
  baselineMatches,
  baselineRecordsTypes,
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
      id: {type: "UUID", optional: false, hasDefault: false},
      name: {type: "String", optional: false, hasDefault: false},
      notes: {type: "String?", optional: true, hasDefault: false},
    },
  },
  frozenModels: {
    "AscendSchemaV1.Workout": {id: {type: "UUID", optional: false, hasDefault: false}},
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

/** @param {string[]} columns Columns a stage claims. @return {object} A baseline naming them. */
function baselineCovering(columns) {
  return {...BASELINE, customStageColumns: columns};
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
  // the folders models live in today would let the next one ship unchecked. The
  // check owns a job of its own so a Swift-only change is not gated on the
  // scripts package's dependency audit.
  const workflow = readFileSync(
    fileURLToPath(new URL("../../.github/workflows/ci.yml", import.meta.url)),
    "utf-8"
  );
  const schemaFilter = workflow.slice(
    workflow.indexOf("            swiftdata_schema:\n"),
    workflow.indexOf("\n  functions-verify:")
  );

  assert.match(schemaFilter, /- "AscendApp\/\*\*"/);
  assert.match(schemaFilter, /- "SharedTestVectors\/\*\*"/);
  assert.match(workflow, /swiftdata_schema: \$\{\{ steps\.filter\.outputs\.swiftdata_schema \}\}/);

  const job = workflow.slice(
    workflow.indexOf("  swiftdata-schema-verify:"),
    workflow.indexOf("  web-verify:")
  );

  assert.match(job, /if: needs\.changes\.outputs\.swiftdata_schema == 'true'/);
  assert.match(job, /run: node scripts\/check-swiftdata-schema\.mjs/);
  // The job's independence is the point: nothing it installs can fail it.
  assert.doesNotMatch(job, /npm/);
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
        cadence: {type: "Int", optional: false, hasDefault: false},
      },
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.cadence is new, non-optional, and has no default/);
  assert.match(violations[0], /make it optional; give it a default.*or add a custom MigrationStage/s);
});

test("the same property passes optional, defaulted, or backed by a stage that claims it", () => {
  const optional = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {...BASELINE.models.Workout, cadence: {type: "Int?", optional: true, hasDefault: false}},
    },
    currentSchema: SCHEMA_V3,
  }));
  assert.deepEqual(optional, []);

  const defaulted = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {...BASELINE.models.Workout, cadence: {type: "Int", optional: false, hasDefault: true}},
    },
    currentSchema: SCHEMA_V3,
  }));
  assert.deepEqual(defaulted, []);

  // The third route: a blanket value would be a lie, so a stage computes one per record. This is
  // what AscendMigrationPlan.migrateV1toV2 does for Workout.source. The stage has to exist *and*
  // the baseline has to name the column it covers.
  const staged = checkShapeDelta(deltaInput({
    baseline: baselineCovering(["Workout.cadence"]),
    currentShape: {
      Workout: {...BASELINE.models.Workout, cadence: {type: "Int", optional: false, hasDefault: false}},
    },
    plan: {...PLAN, customStageCount: 2},
    currentSchema: SCHEMA_V3,
  }));
  assert.deepEqual(staged, []);
});

test("a stage does not excuse a column it never claimed", () => {
  // The failure this rule exists for: one PR adds a stage that migrates Routine.intervalPlan, and
  // an unrelated required Workout.cadence rides in on it with no value for existing rows.
  const violations = checkShapeDelta(deltaInput({
    baseline: baselineCovering(["Routine.intervalPlan"]),
    currentShape: {
      Workout: {...BASELINE.models.Workout, cadence: {type: "Int", optional: false, hasDefault: false}},
    },
    plan: {...PLAN, customStageCount: 2},
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.cadence is new, non-optional, and has no default/);
});

test("naming a column without adding a stage excuses nothing", () => {
  const violations = checkShapeDelta(deltaInput({
    baseline: baselineCovering(["Workout.cadence"]),
    currentShape: {
      Workout: {...BASELINE.models.Workout, cadence: {type: "Int", optional: false, hasDefault: false}},
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.cadence is new, non-optional, and has no default/);
});

test("changing a stored property's type fails without a stage that claims it", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {...BASELINE.models.Workout, name: {type: "Int", optional: false, hasDefault: false}},
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.name changed type from String to Int/);

  const staged = checkShapeDelta(deltaInput({
    baseline: baselineCovering(["Workout.name"]),
    currentShape: {
      Workout: {...BASELINE.models.Workout, name: {type: "Int", optional: false, hasDefault: false}},
    },
    plan: {...PLAN, customStageCount: 2},
    currentSchema: SCHEMA_V3,
  }));
  assert.deepEqual(staged, []);
});

test("widening an existing column to optional is not a type change", () => {
  // Lightweight migration handles this and no row loses a value, so demanding a stage would only
  // teach people to add stages that do nothing.
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {...BASELINE.models.Workout, name: {type: "String?", optional: true, hasDefault: false}},
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.deepEqual(violations, []);
});

test("an existing required property with no default is not a defect", () => {
  // The default is only ever consulted when the property is new. Sweeping defaults onto columns
  // that already hold values buys nothing, so the check must stay silent about them.
  assert.deepEqual(checkShapeDelta(deltaInput()), []);
});

test("turning an existing optional property required without a default fails", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {...BASELINE.models.Workout, notes: {type: "String", optional: false, hasDefault: false}},
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.notes is newly required/);
});

test("a brand new model is exempt, because it has no existing rows", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      ...BASELINE.models,
      Streak: {
        id: {type: "UUID", optional: false, hasDefault: false},
        length: {type: "Int", optional: false, hasDefault: false},
      },
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.deepEqual(violations, []);
});

test("changing the shape without a new schema version fails", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {...BASELINE.models.Workout, cadence: {type: "Int?", optional: true, hasDefault: false}},
    },
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /AscendSchemaV2 is still the newest versioned schema/);
});

test("editing or deleting a shipped historical schema fails", () => {
  const edited = checkShapeDelta(deltaInput({
    frozenShape: {
      "AscendSchemaV1.Workout": {id: {type: "UUID", optional: true, hasDefault: false}},
    },
  }));
  assert.match(edited[0], /frozen historical model AscendSchemaV1\.Workout changed/);

  const deleted = checkShapeDelta(deltaInput({frozenShape: {}}));
  assert.match(deleted[0], /frozen historical model AscendSchemaV1\.Workout was deleted/);
});

test("a rename carried by @Attribute(originalName:) is the same column, not a new one", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {
        id: BASELINE.models.Workout.id,
        notes: BASELINE.models.Workout.notes,
        title: {type: "String", optional: false, hasDefault: false, originalName: "name"},
      },
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.deepEqual(violations, []);
});

test("a rename that also changes the type still trips the type rule", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {
        id: BASELINE.models.Workout.id,
        notes: BASELINE.models.Workout.notes,
        title: {type: "Int", optional: false, hasDefault: false, originalName: "name"},
      },
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.title \(renamed from name\) changed type from String to Int/);
});

test("a rename without the annotation still trips, because SwiftData drops the old values", () => {
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {
        id: BASELINE.models.Workout.id,
        notes: BASELINE.models.Workout.notes,
        title: {type: "String", optional: false, hasDefault: false},
      },
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.title is new, non-optional, and has no default/);
  assert.match(violations[0], /if it is a rename, carry the old column with @Attribute\(originalName:\)/);
});

test("originalName pointing at a column that still exists is not a rename", () => {
  // Both columns exist, so nothing was carried forward and `duplicate` really is new.
  const violations = checkShapeDelta(deltaInput({
    currentShape: {
      Workout: {
        ...BASELINE.models.Workout,
        duplicate: {type: "String", optional: false, hasDefault: false, originalName: "name"},
      },
    },
    currentSchema: SCHEMA_V3,
  }));

  assert.equal(violations.length, 1);
  assert.match(violations[0], /Workout\.duplicate is new, non-optional, and has no default/);
});

test("the parser reads originalName off the declaration it annotates", () => {
  const source = `
    @Model
    final class Sample {
        @Attribute(originalName: "oldTitle") var title: String = ""
        @Attribute(.unique, originalName: "oldCode")
        var code: String = ""
        var untouched: String = ""
    }
  `;

  const [model] = parseModels(source, "Sample.swift");
  const shape = shapeOf([model]).Sample;

  assert.equal(shape.title.originalName, "oldTitle");
  assert.equal(shape.code.originalName, "oldCode");
  assert.equal("originalName" in shape.untouched, false);
});

test("an originalName the parser cannot read is an error, not a new column", () => {
  const source = `
    @Model
    final class Sample {
        @Attribute(originalName: Self.legacyKey) var title: String = ""
    }
  `;

  assert.throws(
    () => parseModels(source, "Sample.swift"),
    /Sample\.title declares originalName but not as a string literal/
  );
});

test("a baseline with no recorded types stops the check instead of skipping the type rule", () => {
  const typeless = {
    ...BASELINE,
    models: {Workout: {id: {optional: false, hasDefault: false}}},
    frozenModels: {},
  };

  assert.equal(baselineRecordsTypes(typeless), false);
  assert.equal(baselineRecordsTypes(BASELINE), true);
  assert.throws(
    () => checkShapeDelta(deltaInput({
      baseline: typeless,
      currentShape: {Workout: {id: {type: "Int", optional: false, hasDefault: false}}},
      frozenShape: {},
      currentSchema: SCHEMA_V3,
    })),
    /no type for Workout\.id in models.*type-change rule cannot be evaluated/s
  );
});

test("the hand-written stage allowlist is not a stale baseline", () => {
  const record = {...BASELINE};
  delete record.customStageColumns;

  assert.equal(baselineMatches(baselineCovering(["Workout.cadence"]), record), true);
  assert.equal(baselineMatches({...record, currentSchema: "AscendSchemaV3"}, record), false);
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

        var shorthand: String {
            label
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
    id: {type: "UUID", optional: false, hasDefault: false},
    label: {type: "String", optional: false, hasDefault: true},
    levels: {type: "[Int: Set<String>]", optional: false, hasDefault: true},
    note: {type: "String?", optional: true, hasDefault: false},
    renamed: {type: "Int", optional: false, hasDefault: true, originalName: "old"},
  });
});

test("a property with an observer is a column; a declaration split over lines is one too", () => {
  const source = `
    @Model
    final class Sample {
        var attemptCount: Int = 0 { didSet { recompute() } }

        var failureCount: Int = 0 {
            willSet { prepare() }
            didSet { recompute() }
        }

        var summary:
            String = "none"

        var levels: [Int: Set<String>]
            = [:]

        var title: String =
            "untitled"

        func recompute() {}
        func prepare() {}
    }
  `;

  const [model] = parseModels(source, "Sample.swift");
  assert.deepEqual(shapeOf([model]).Sample, {
    attemptCount: {type: "Int", optional: false, hasDefault: true},
    failureCount: {type: "Int", optional: false, hasDefault: true},
    levels: {type: "[Int: Set<String>]", optional: false, hasDefault: true},
    summary: {type: "String", optional: false, hasDefault: true},
    title: {type: "String", optional: false, hasDefault: true},
  });
});

test("a declaration the parser cannot classify fails loudly instead of vanishing", () => {
  const untyped = `
    @Model
    final class Sample {
        var id = UUID()
    }
  `;

  assert.throws(
    () => parseModels(untyped, "Sample.swift"),
    /Sample\.id has no type annotation/
  );
});

test("a brace inside a string literal does not derail the property list", () => {
  const source = `
    @Model
    final class Sample {
        var id: UUID
        var template: String = "a } b { c"
        var caption: String = "trailing"
    }
  `;

  const [model] = parseModels(source, "Sample.swift");
  assert.deepEqual(Object.keys(shapeOf([model]).Sample), ["caption", "id", "template"]);
});

test("a model nested inside a historical schema is read as frozen, keyed to that schema", () => {
  const source = `
    extension AscendSchemaV1 {
        @Model
        final class Workout {
            var id: UUID = UUID()
        }
    }

    extension AscendSchemaV2 {
        @Model
        final class Workout {
            var id: UUID = UUID()
            var cadence: Int = 0
        }
    }
  `;

  const models = parseModels(source, "AscendSchemas.swift");
  assert.equal(models.length, 2);
  assert.deepEqual(models.map((model) => model.nested), [true, true]);

  // Two versions freezing the same class is how a model changes twice. Keyed by bare class name
  // they collapse into one entry, and V1's frozen shape silently loses its immutability guard.
  const shape = shapeOf(models);
  assert.deepEqual(Object.keys(shape), ["AscendSchemaV1.Workout", "AscendSchemaV2.Workout"]);
  assert.deepEqual(Object.keys(shape["AscendSchemaV1.Workout"]), ["id"]);
  assert.deepEqual(Object.keys(shape["AscendSchemaV2.Workout"]), ["cadence", "id"]);
});

test("the repository's own frozen copies are recorded under their schema version", () => {
  const facts = readSchemaFacts();

  assert.ok(facts.frozenModels.length > 0);
  for (const model of facts.frozenModels) {
    assert.match(model.qualifiedName, /^AscendSchemaV\d+\.[A-Za-z_][A-Za-z0-9_]*$/);
  }
  assert.ok(Object.keys(facts.record.frozenModels).includes("AscendSchemaV1.Workout"));
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
    stages: [{name: "migrateV1toV2", kind: "custom"}],
    customStageCount: 1,
    lightweightStageCount: 0,
  });
});

test("a stage nothing wires into `stages` counts for nothing", () => {
  const plan = parseMigrationPlan(`
    enum AscendMigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            [AscendSchemaV1.self, AscendSchemaV2.self]
        }

        static var stages: [MigrationStage] {
            [migrateV1toV2]
        }

        static let migrateV1toV2 = MigrationStage.lightweight(
            fromVersion: AscendSchemaV1.self,
            toVersion: AscendSchemaV2.self
        )

        static let neverWiredIn = MigrationStage.custom(
            fromVersion: AscendSchemaV1.self,
            toVersion: AscendSchemaV2.self,
            willMigrate: { _ in },
            didMigrate: { _ in }
        )
    }
  `, "AscendMigrationPlan.swift");

  assert.equal(plan.customStageCount, 0);
  assert.equal(plan.lightweightStageCount, 1);
});

test("a stage reference the checker cannot resolve is an error, not a free pass", () => {
  assert.throws(() => parseMigrationPlan(`
    enum AscendMigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            [AscendSchemaV1.self, AscendSchemaV2.self]
        }

        static var stages: [MigrationStage] {
            [makeStage()]
        }
    }
  `, "AscendMigrationPlan.swift"), /references makeStage, but nothing declares it/);
});

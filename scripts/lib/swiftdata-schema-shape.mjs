/**
 * Reads the persisted shape of Ascend's SwiftData store out of the Swift sources, so a schema
 * change that would silently default existing rows fails before it ships.
 *
 * Nothing here understands Swift. It reads the declarations that decide what lands on disk -
 * `@Model` classes, their stored `var`s, `VersionedSchema.models`, and `SchemaMigrationPlan.stages`
 * - and treats anything it cannot parse as a reason to fail loudly rather than to pass quietly. A
 * checker that shrugs at a shape it does not recognise is a checker that reports green on the one
 * change it existed to catch.
 */

/** Property attributes that mean "not persisted", so the shape does not include them. */
const NON_PERSISTED_ATTRIBUTES = ["@Transient"];

/**
 * Strips line and block comments while preserving line structure.
 *
 * Comment bodies are full of braces and `var` spellings; counting them would put the brace depth
 * and the property list both wrong.
 * @param {string} source Swift source text.
 * @return {string} Source with comment bodies blanked out.
 */
export function stripComments(source) {
  let output = "";
  let index = 0;
  let inBlockComment = false;
  let inString = false;

  while (index < source.length) {
    const two = source.slice(index, index + 2);

    if (inBlockComment) {
      if (two === "*/") {
        inBlockComment = false;
        index += 2;
        continue;
      }
      output += source[index] === "\n" ? "\n" : " ";
      index += 1;
      continue;
    }

    if (inString) {
      if (source[index] === "\\") {
        output += "  ";
        index += 2;
        continue;
      }
      if (source[index] === "\"") {
        inString = false;
      }
      output += source[index];
      index += 1;
      continue;
    }

    if (two === "/*") {
      inBlockComment = true;
      index += 2;
      continue;
    }

    if (two === "//") {
      while (index < source.length && source[index] !== "\n") {
        output += " ";
        index += 1;
      }
      continue;
    }

    if (source[index] === "\"") {
      inString = true;
    }

    output += source[index];
    index += 1;
  }

  return output;
}

/**
 * Finds every `@Model` class in a source file and the stored properties it persists.
 * @param {string} source Swift source text.
 * @param {string} file Repo-relative path, carried through for error messages.
 * @return {Array<{name: string, file: string, nested: boolean, properties: Array<object>}>} Models.
 */
export function parseModels(source, file) {
  const text = stripComments(source);
  const models = [];
  const modelPattern = /@Model\b/g;
  let match;

  while ((match = modelPattern.exec(text)) !== null) {
    const declaration = /\b(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)/
      .exec(text.slice(match.index, match.index + 400));
    if (!declaration) {
      throw new Error(`${file}: an @Model attribute is not followed by a class declaration`);
    }

    const nameEnd = match.index + declaration.index + declaration[0].length;
    const bodyStart = text.indexOf("{", nameEnd);
    if (bodyStart === -1) {
      throw new Error(`${file}: @Model ${declaration[1]} has no class body`);
    }

    models.push({
      name: declaration[1],
      file,
      nested: isNestedDeclaration(text, match.index),
      properties: parseStoredProperties(text.slice(bodyStart, matchingBraceIndex(text, bodyStart)), file, declaration[1]),
    });
  }

  return models;
}

/**
 * Whether the declaration sits inside another type rather than at file scope.
 *
 * `AscendSchemaV1`'s frozen copies are nested in an extension; the live models are not, and the two
 * are governed by opposite rules - one must never change, the other is expected to.
 * @param {string} text Comment-stripped source.
 * @param {number} index Offset of the `@Model` attribute.
 * @return {boolean} True when the declaration is nested inside another brace scope.
 */
function isNestedDeclaration(text, index) {
  let depth = 0;
  for (let cursor = 0; cursor < index; cursor += 1) {
    if (text[cursor] === "{") depth += 1;
    if (text[cursor] === "}") depth -= 1;
  }
  return depth > 0;
}

/**
 * @param {string} text Comment-stripped source.
 * @param {number} openIndex Offset of the opening brace.
 * @return {number} Offset just past the matching closing brace.
 */
function matchingBraceIndex(text, openIndex) {
  let depth = 0;
  for (let cursor = openIndex; cursor < text.length; cursor += 1) {
    if (text[cursor] === "{") depth += 1;
    if (text[cursor] === "}") {
      depth -= 1;
      if (depth === 0) return cursor;
    }
  }
  throw new Error("unbalanced braces while reading a class body");
}

/**
 * Reads the stored `var`s declared directly in a class body.
 *
 * Only depth-1 declarations count: a `var` inside a computed property's accessor, a nested type, or
 * a function body is not a column.
 * @param {string} body Class body text, starting at its opening brace.
 * @param {string} file Repo-relative path, for error messages.
 * @param {string} model Model name, for error messages.
 * @return {Array<{name: string, type: string, optional: boolean, hasDefault: boolean}>} Properties.
 */
function parseStoredProperties(body, file, model) {
  const lines = body.split("\n");
  const properties = [];
  let depth = 0;
  let pendingAttributes = [];

  for (const raw of lines) {
    const line = raw.trim();
    const depthAtLineStart = depth;
    depth += countOccurrences(raw, "{") - countOccurrences(raw, "}");

    // depth 1 is the class body itself: the brace opened on the declaration line.
    if (depthAtLineStart !== 1 || line.length === 0) continue;

    if (line.startsWith("@")) {
      pendingAttributes.push(line);
      // An attribute may sit on the same line as the declaration it modifies.
      if (!/\bvar\b/.test(line)) continue;
    }

    const declaration = /(?:^|\s)var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)$/.exec(line);
    if (!declaration) {
      if (!line.startsWith("@")) pendingAttributes = [];
      continue;
    }

    const attributes = pendingAttributes;
    pendingAttributes = [];

    if (/\bstatic\b|\bclass\b|\blazy\b/.test(line.slice(0, line.indexOf("var")))) continue;
    if (attributes.some((attribute) => NON_PERSISTED_ATTRIBUTES.some((skip) => attribute.startsWith(skip)))) {
      continue;
    }

    const remainder = declaration[2];
    // A trailing `{` opens an accessor block: computed, not stored.
    if (remainder.includes("{")) continue;

    const [typeText, defaultText] = splitTypeAndDefault(remainder);
    const type = typeText.trim();
    if (type.length === 0) {
      throw new Error(`${file}: ${model}.${declaration[1]} has an unreadable type`);
    }

    properties.push({
      name: declaration[1],
      type,
      optional: isOptional(type),
      hasDefault: defaultText !== null,
    });
  }

  return properties;
}

/**
 * @param {string} remainder Text after the property's colon.
 * @return {[string, string|null]} The type text and the default expression, if any.
 */
function splitTypeAndDefault(remainder) {
  let depth = 0;
  for (let index = 0; index < remainder.length; index += 1) {
    const character = remainder[index];
    if (character === "<" || character === "[" || character === "(") depth += 1;
    if (character === ">" || character === "]" || character === ")") depth -= 1;
    if (character === "=" && depth === 0 && remainder[index + 1] !== "=") {
      return [remainder.slice(0, index), remainder.slice(index + 1)];
    }
  }
  return [remainder, null];
}

/** @param {string} type Swift type spelling. @return {boolean} Whether it is an Optional. */
function isOptional(type) {
  return type.endsWith("?") || /^Optional\s*</.test(type);
}

/** @param {string} text Haystack. @param {string} character Needle. @return {number} Count. */
function countOccurrences(text, character) {
  let count = 0;
  for (const candidate of text) {
    if (candidate === character) count += 1;
  }
  return count;
}

/**
 * Reads a `VersionedSchema`'s declared version and model list.
 * @param {string} source Swift source text.
 * @param {string} file Repo-relative path, for error messages.
 * @return {{name: string, versionIdentifier: number[], models: string[]}|null} The schema.
 */
export function parseVersionedSchema(source, file) {
  const text = stripComments(source);
  const declaration = /\benum\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*VersionedSchema\b/.exec(text);
  if (!declaration) return null;

  const version = /Schema\.Version\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/.exec(text);
  if (!version) {
    throw new Error(`${file}: ${declaration[1]} declares no Schema.Version`);
  }

  const modelsBlock = /static\s+var\s+models\s*:[^{]*\{([\s\S]*?)\n\s*\}/.exec(text);
  if (!modelsBlock) {
    throw new Error(`${file}: ${declaration[1]} declares no models list`);
  }

  return {
    name: declaration[1],
    versionIdentifier: [Number(version[1]), Number(version[2]), Number(version[3])],
    models: [...modelsBlock[1].matchAll(/([A-Za-z_][A-Za-z0-9_]*)\.self/g)].map((entry) => entry[1]),
  };
}

/**
 * Reads which schemas the migration plan carries forward and how many stages of each kind it runs.
 * @param {string} source Swift source text of the migration plan.
 * @param {string} file Repo-relative path, for error messages.
 * @return {{schemas: string[], customStageCount: number, lightweightStageCount: number}} The plan.
 */
export function parseMigrationPlan(source, file) {
  const text = stripComments(source);
  const schemasBlock = /static\s+var\s+schemas\s*:[^{]*\{([\s\S]*?)\n\s*\}/.exec(text);
  if (!schemasBlock) {
    throw new Error(`${file}: the migration plan declares no schemas list`);
  }

  return {
    schemas: [...schemasBlock[1].matchAll(/([A-Za-z_][A-Za-z0-9_]*)\.self/g)].map((entry) => entry[1]),
    customStageCount: countOccurrences2(text, /MigrationStage\.custom\b/g),
    lightweightStageCount: countOccurrences2(text, /MigrationStage\.lightweight\b/g),
  };
}

/** @param {string} text Haystack. @param {RegExp} pattern Global pattern. @return {number} Count. */
function countOccurrences2(text, pattern) {
  return [...text.matchAll(pattern)].length;
}

/**
 * Reduces parsed models to the comparable shape recorded in the baseline.
 * @param {Array<object>} models Parsed models.
 * @return {Record<string, Record<string, {optional: boolean, hasDefault: boolean}>>} The shape.
 */
export function shapeOf(models) {
  const shape = {};
  for (const model of [...models].sort((a, b) => a.name.localeCompare(b.name))) {
    const properties = {};
    for (const property of [...model.properties].sort((a, b) => a.name.localeCompare(b.name))) {
      properties[property.name] = {optional: property.optional, hasDefault: property.hasDefault};
    }
    shape[model.name] = properties;
  }
  return shape;
}

/**
 * The model list and the current versioned schema must name the same set of types.
 *
 * A model registered in the container but absent from the schema, or the reverse, is a store whose
 * shape on disk is not the shape the code believes it wrote.
 * @param {{liveModels: string[], currentSchema: object, planSchemas: string[], containerSchema: string}} input Parsed facts.
 * @return {string[]} Violations, empty when the two agree.
 */
export function checkModelSetAgreement(input) {
  const violations = [];
  const declared = new Set(input.liveModels);
  const registered = new Set(input.currentSchema.models);

  for (const name of [...declared].sort()) {
    if (!registered.has(name)) {
      violations.push(
        `@Model ${name} is declared but missing from ${input.currentSchema.name}.models - ` +
        "a model outside the versioned schema is not migrated and not opened with the store"
      );
    }
  }

  for (const name of [...registered].sort()) {
    if (!declared.has(name)) {
      violations.push(
        `${input.currentSchema.name}.models lists ${name}, which is not a declared @Model type`
      );
    }
  }

  const newestPlanSchema = input.planSchemas.at(-1);
  if (newestPlanSchema !== input.currentSchema.name) {
    violations.push(
      `AscendMigrationPlan.schemas ends at ${newestPlanSchema}, but the newest versioned schema is ` +
      `${input.currentSchema.name} - the plan has no stage leading to the shape the app writes`
    );
  }

  if (input.containerSchema !== input.currentSchema.name) {
    violations.push(
      `the app opens its store with ${input.containerSchema} but the newest versioned schema is ` +
      `${input.currentSchema.name}`
    );
  }

  return violations;
}

/**
 * The rule the captain drew, enforced on the delta rather than swept across the models.
 *
 * A default value is only ever consulted when a property is *new* and the store has to decide what
 * existing rows hold. Adding one to a property that already exists changes nothing, so this fires
 * only on properties that appear now and did not before, and only on models that already have rows.
 * @param {{baseline: object, currentShape: object, frozenShape: object, plan: object, currentSchema: object}} input Parsed facts.
 * @return {string[]} Violations, empty when the change is safe.
 */
export function checkShapeDelta(input) {
  const violations = [];
  const baselineShape = input.baseline.models ?? {};
  const newCustomStages = input.plan.customStageCount - (input.baseline.customStageCount ?? 0);

  for (const [model, properties] of Object.entries(input.currentShape)) {
    const baselineProperties = baselineShape[model];
    // A model that did not exist has no rows, so nothing has to be defaulted into them.
    if (!baselineProperties) continue;

    for (const [name, property] of Object.entries(properties)) {
      const before = baselineProperties[name];
      const isNewColumn = !before;
      const becameRequired = Boolean(before) && before.optional && !property.optional;
      if (!isNewColumn && !becameRequired) continue;
      if (property.optional || property.hasDefault) continue;
      if (newCustomStages > 0) continue;

      violations.push(
        `${model}.${name} is ${isNewColumn ? "new" : "newly required"}, non-optional, and has no ` +
        "default, and the migration plan gained no custom stage to compute one. Existing rows have " +
        "no value to write. Pick one: make it optional; give it a default if a single blanket " +
        "value is honest; or add a custom MigrationStage that computes the right value per record " +
        "(see AscendMigrationPlan.migrateV1toV2)"
      );
    }
  }

  for (const [model, properties] of Object.entries(input.baseline.frozenModels ?? {})) {
    const current = input.frozenShape[model];
    if (!current) {
      violations.push(
        `the frozen historical model ${model} was deleted - a shipped VersionedSchema describes a ` +
        "store shape that exists on real devices and must never be rewritten"
      );
      continue;
    }
    if (JSON.stringify(current) !== JSON.stringify(properties)) {
      violations.push(
        `the frozen historical model ${model} changed - a shipped VersionedSchema describes a store ` +
        "shape that exists on real devices and must never be rewritten. Add a new schema version " +
        "instead"
      );
    }
  }

  const shapeChanged = JSON.stringify(input.currentShape) !== JSON.stringify(baselineShape);
  if (shapeChanged && input.currentSchema.name === input.baseline.currentSchema) {
    violations.push(
      `the persisted shape changed but ${input.baseline.currentSchema} is still the newest ` +
      "versioned schema. A shipped schema version must not be edited: add the next AscendSchemaV*, " +
      "list every model in it, and add a stage to AscendMigrationPlan.stages"
    );
  }

  return violations;
}

/**
 * Whether the recorded baseline still describes the sources.
 * @param {object} baseline Recorded baseline.
 * @param {object} current Freshly parsed baseline-shaped record.
 * @return {boolean} True when they match exactly.
 */
export function baselineMatches(baseline, current) {
  return JSON.stringify(baseline) === JSON.stringify(current);
}

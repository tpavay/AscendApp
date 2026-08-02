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

/** Declaration keywords that end the "modifiers" prefix of a member and say what it is. */
const MEMBER_KEYWORD =
  /(?:^|\s)(var|let|func|init|deinit|subscript|enum|struct|class|actor|extension|typealias|case|protocol)\b/;

/** Type declarations that can enclose a nested `@Model`, so a frozen copy can be named for its schema. */
const TYPE_DECLARATION = /\b(?:extension|enum|struct|actor|class|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)/g;

/** Accessor and observer keywords, matched alongside braces so nesting depth can be tracked. */
const ACCESSOR_KEYWORD =
  /[{}]|\b(get|set|willSet|didSet|_read|_modify|unsafeAddress|unsafeMutableAddress)\b/g;

/** The two keywords that mean "still a stored column", unlike every other accessor. */
const OBSERVER_KEYWORDS = new Set(["willSet", "didSet"]);

/** A declaration ending in one of these is mid-expression, so the next line belongs to it. */
const CONTINUES_AFTER = /[=:,.&|+\-*\/<(\[]$/;

/** A following line starting with one of these continues the declaration above it. */
const CONTINUES_BEFORE = /^[=.,)\]?:&|+*\/{]/;

/**
 * Strips comment and string-literal bodies while preserving line structure and offsets.
 *
 * Comment bodies are full of braces and `var` spellings, and a string literal can hold an unpaired
 * brace; counting either would put the brace depth and the property list both wrong. Only the
 * bodies go - the quotes stay, so a default value is still visible as a default value.
 * @param {string} source Swift source text.
 * @return {string} Source with comment and string bodies blanked out.
 */
export function stripComments(source) {
  let output = "";
  let index = 0;
  let inBlockComment = false;
  let stringDelimiter = null;

  while (index < source.length) {
    const two = source.slice(index, index + 2);
    const three = source.slice(index, index + 3);

    if (inBlockComment) {
      if (two === "*/") {
        inBlockComment = false;
        output += "  ";
        index += 2;
        continue;
      }
      output += source[index] === "\n" ? "\n" : " ";
      index += 1;
      continue;
    }

    if (stringDelimiter !== null) {
      if (stringDelimiter === "\"\"\"") {
        if (three === "\"\"\"") {
          output += "\"\"\"";
          stringDelimiter = null;
          index += 3;
          continue;
        }
      } else {
        if (source[index] === "\\") {
          output += "  ";
          index += 2;
          continue;
        }
        if (source[index] === "\"") {
          output += "\"";
          stringDelimiter = null;
          index += 1;
          continue;
        }
      }
      output += source[index] === "\n" ? "\n" : " ";
      index += 1;
      continue;
    }

    if (two === "/*") {
      inBlockComment = true;
      output += "  ";
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

    if (three === "\"\"\"") {
      stringDelimiter = "\"\"\"";
      output += "\"\"\"";
      index += 3;
      continue;
    }

    if (source[index] === "\"") {
      stringDelimiter = "\"";
      output += "\"";
      index += 1;
      continue;
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
 * @return {Array<object>} Models, each carrying its qualified name and stored properties.
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

    const nested = isNestedDeclaration(text, match.index);
    const enclosingType = nested ? enclosingTypeName(text, match.index) : null;
    if (nested && enclosingType === null) {
      throw new Error(
        `${file}: @Model ${declaration[1]} is nested inside a scope this checker cannot name, so ` +
        "its frozen copy cannot be keyed to the schema version that owns it"
      );
    }

    const qualifiedName = enclosingType === null
      ? declaration[1]
      : `${enclosingType}.${declaration[1]}`;

    models.push({
      name: declaration[1],
      qualifiedName,
      enclosingType,
      file,
      nested,
      properties: parseStoredProperties(
        text.slice(bodyStart, matchingBraceIndex(text, bodyStart)),
        file,
        qualifiedName
      ),
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
  return openBraceStack(text, index).length > 0;
}

/**
 * Names the type a nested declaration lives in, so two schema versions freezing the same class
 * produce two distinct keys rather than one that silently overwrites the other.
 * @param {string} text Comment-stripped source.
 * @param {number} index Offset of the `@Model` attribute.
 * @return {string|null} The innermost enclosing type name, or null at file scope.
 */
function enclosingTypeName(text, index) {
  const openBraces = openBraceStack(text, index);

  for (let position = openBraces.length - 1; position >= 0; position -= 1) {
    const braceIndex = openBraces[position];
    const previous = Math.max(
      text.lastIndexOf("{", braceIndex - 1),
      text.lastIndexOf("}", braceIndex - 1)
    );
    const header = text.slice(previous + 1, braceIndex);
    const declarations = [...header.matchAll(TYPE_DECLARATION)];
    if (declarations.length > 0) return declarations.at(-1)[1];
  }

  return null;
}

/**
 * @param {string} text Comment-stripped source.
 * @param {number} index Offset to stop at.
 * @return {number[]} Offsets of the braces still open at that point, outermost first.
 */
function openBraceStack(text, index) {
  const open = [];
  for (let cursor = 0; cursor < index; cursor += 1) {
    if (text[cursor] === "{") open.push(cursor);
    if (text[cursor] === "}") open.pop();
  }
  return open;
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
 * Cuts a class body into its member declarations, each with the brace block that follows it.
 *
 * A member is not a line. A declaration can wrap onto the next line, and the block that decides
 * whether a `var` is stored or computed can start on one line and close several later. Both were
 * previously invisible to a line-scoped read, and an invisible column is one no rule can fire on.
 * @param {string} body Class body text, with its opening brace already removed.
 * @return {Array<{declaration: string, block: string|null}>} Members in source order.
 */
function splitMembers(body) {
  const members = [];
  let memberStart = -1;
  let blockStart = -1;
  let depth = 0;

  for (let index = 0; index < body.length; index += 1) {
    const character = body[index];

    if (memberStart === -1) {
      if (/\s/.test(character)) continue;
      memberStart = index;
    }

    if (character === "(" || character === "[") {
      depth += 1;
      continue;
    }

    if (character === ")" || character === "]") {
      depth -= 1;
      continue;
    }

    if (character === "{") {
      // A brace after `=` opens a closure the declaration is initialised with, not an accessor
      // block, and reading it as one would drop a genuinely stored column.
      if (depth === 0 && !/=\s*$/.test(body.slice(memberStart, index))) blockStart = index;
      depth += 1;
      continue;
    }

    if (character === "}") {
      depth -= 1;
      if (depth === 0 && blockStart !== -1) {
        members.push({
          declaration: body.slice(memberStart, blockStart).trim(),
          block: body.slice(blockStart + 1, index),
        });
        memberStart = -1;
        blockStart = -1;
      }
      continue;
    }

    if (character === "\n" && depth === 0 && blockStart === -1) {
      const declaration = body.slice(memberStart, index).trim();
      if (declaration.length > 0 && !continuesOnTheNextLine(declaration, body, index)) {
        members.push({declaration, block: null});
        memberStart = -1;
      }
    }
  }

  const trailing = memberStart === -1 ? "" : body.slice(memberStart).trim();
  if (trailing.length > 0) members.push({declaration: trailing, block: null});

  return members;
}

/**
 * @param {string} declaration Text accumulated so far.
 * @param {string} body The class body.
 * @param {number} newlineIndex Offset of the newline being considered as a member boundary.
 * @return {boolean} Whether the declaration continues past that newline.
 */
function continuesOnTheNextLine(declaration, body, newlineIndex) {
  if (CONTINUES_AFTER.test(declaration)) return true;

  const next = /\S/.exec(body.slice(newlineIndex + 1));
  return next !== null && CONTINUES_BEFORE.test(next[0]);
}

/**
 * Reads the stored `var`s declared directly in a class body.
 *
 * Only members of the class body itself count: a `var` inside a computed property's accessor, a
 * nested type, or a function body is not a column.
 * @param {string} body Class body text, starting at its opening brace.
 * @param {string} file Repo-relative path, for error messages.
 * @param {string} model Model name, for error messages.
 * @return {Array<{name: string, type: string, optional: boolean, hasDefault: boolean}>} Properties.
 */
function parseStoredProperties(body, file, model) {
  const properties = [];
  let pendingAttributes = [];

  for (const member of splitMembers(body.slice(1))) {
    const {attributes, remainder} = splitAttributes(member.declaration);
    const allAttributes = [...pendingAttributes, ...attributes];
    pendingAttributes = [];

    if (remainder.length === 0) {
      // A line holding nothing but attributes modifies the declaration that follows it.
      if (member.block === null) pendingAttributes = allAttributes;
      continue;
    }

    const keyword = MEMBER_KEYWORD.exec(remainder);
    if (keyword === null || keyword[1] !== "var") continue;
    if (/(?:^|\s)(?:static|class|lazy)\s/.test(remainder.slice(0, keyword.index + keyword[0].length))) {
      continue;
    }

    const name = /\bvar\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(remainder);
    if (name === null) {
      throw new Error(`${file}: ${model} declares a var this checker cannot read: "${remainder}"`);
    }

    if (allAttributes.some((attribute) =>
      NON_PERSISTED_ATTRIBUTES.some((skip) => attribute.startsWith(skip)))) {
      continue;
    }

    if (member.block !== null) {
      const kind = accessorKind(member.block);
      if (kind === "computed") continue;
      if (kind === "unknown") {
        throw new Error(
          `${file}: ${model}.${name[1]} has an accessor block this checker cannot classify as ` +
          "computed or as a stored property with an observer"
        );
      }
    }

    const rest = remainder.slice(name.index + name[0].length).trim();
    if (!rest.startsWith(":")) {
      throw new Error(
        `${file}: ${model}.${name[1]} has no type annotation, so this checker cannot tell what ` +
        "column it writes. Annotate the type"
      );
    }

    const [typeText, defaultText] = splitTypeAndDefault(rest.slice(1));
    const type = normalizeType(typeText);
    if (type.length === 0) {
      throw new Error(`${file}: ${model}.${name[1]} has an unreadable type`);
    }

    properties.push({
      name: name[1],
      type,
      optional: isOptional(type),
      hasDefault: defaultText !== null,
    });
  }

  return properties;
}

/**
 * @param {string} declaration A member declaration.
 * @return {{attributes: string[], remainder: string}} Leading `@Attribute`s and what follows them.
 */
function splitAttributes(declaration) {
  const attributes = [];
  let rest = declaration.trim();

  while (rest.startsWith("@")) {
    const name = /^@[A-Za-z_][A-Za-z0-9_]*/.exec(rest);
    if (name === null) break;

    let end = name[0].length;
    while (end < rest.length && /\s/.test(rest[end])) end += 1;

    if (rest[end] === "(") {
      let depth = 0;
      while (end < rest.length) {
        if (rest[end] === "(") depth += 1;
        if (rest[end] === ")") {
          depth -= 1;
          if (depth === 0) {
            end += 1;
            break;
          }
        }
        end += 1;
      }
    } else {
      end = name[0].length;
    }

    attributes.push(rest.slice(0, end));
    rest = rest.slice(end).trim();
  }

  return {attributes, remainder: rest};
}

/**
 * Tells a property observer apart from a real accessor block.
 *
 * `var attemptCount: Int = 0 { didSet { ... } }` is a stored column; `var derived: String { label }`
 * is not. Reading both as "has a brace, therefore computed" drops a real column from the shape.
 * @param {string} block The text between the block's braces.
 * @return {"computed"|"observer"|"unknown"} What the block makes the property.
 */
function accessorKind(block) {
  const keywords = topLevelAccessorKeywords(block);
  if (keywords.size === 0) return "computed";

  const found = [...keywords];
  if (found.every((keyword) => OBSERVER_KEYWORDS.has(keyword))) return "observer";
  if (found.every((keyword) => !OBSERVER_KEYWORDS.has(keyword))) return "computed";

  return "unknown";
}

/**
 * @param {string} block The text between a block's braces.
 * @return {Set<string>} Accessor keywords declared by the block itself, not by anything nested.
 */
function topLevelAccessorKeywords(block) {
  const keywords = new Set();
  let depth = 0;
  let match;

  ACCESSOR_KEYWORD.lastIndex = 0;
  while ((match = ACCESSOR_KEYWORD.exec(block)) !== null) {
    if (match[0] === "{") {
      depth += 1;
      continue;
    }
    if (match[0] === "}") {
      depth -= 1;
      continue;
    }
    if (depth === 0) keywords.add(match[1]);
  }

  return keywords;
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
    // `->` is a function arrow, not a closing angle bracket.
    if ((character === ">" && remainder[index - 1] !== "-") || character === "]" || character === ")") {
      depth -= 1;
    }
    if (character === "=" && depth === 0 && remainder[index + 1] !== "=" && remainder[index + 1] !== ">") {
      return [remainder.slice(0, index), remainder.slice(index + 1)];
    }
  }
  return [remainder, null];
}

/**
 * @param {string} type Swift type spelling, possibly wrapped across lines.
 * @return {string} The same type with whitespace collapsed, so a reformat is not a shape change.
 */
function normalizeType(type) {
  return type.replace(/\s+/g, " ").trim();
}

/** @param {string} type Swift type spelling. @return {boolean} Whether it is an Optional. */
function isOptional(type) {
  return type.endsWith("?") || /^Optional\s*</.test(type);
}

/**
 * @param {string} type Swift type spelling.
 * @return {string} The type with one layer of Optional removed, so widening reads as no change.
 */
function unwrappedType(type) {
  if (type.endsWith("?")) return type.slice(0, -1).trim();

  const wrapped = /^Optional\s*<([\s\S]*)>$/.exec(type);
  return wrapped === null ? type : wrapped[1].trim();
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

  const modelsBody = declaredBlockBody(text, /static\s+var\s+models\s*:/);
  if (modelsBody === null) {
    throw new Error(`${file}: ${declaration[1]} declares no models list`);
  }

  return {
    name: declaration[1],
    versionIdentifier: [Number(version[1]), Number(version[2]), Number(version[3])],
    models: [...modelsBody.matchAll(/([A-Za-z_][A-Za-z0-9_]*)\.self/g)].map((entry) => entry[1]),
  };
}

/**
 * Reads which schemas the migration plan carries forward, and the stages `stages` actually runs.
 *
 * Only stages reachable from `stages` count. A `MigrationStage.custom` constant that nothing wires
 * in migrates nothing, so counting it would let dead code excuse a column with no value to write.
 * @param {string} source Swift source text of the migration plan.
 * @param {string} file Repo-relative path, for error messages.
 * @return {{schemas: string[], stages: Array<{name: string|null, kind: string}>, customStageCount: number, lightweightStageCount: number}} The plan.
 */
export function parseMigrationPlan(source, file) {
  const text = stripComments(source);
  const schemasBody = declaredBlockBody(text, /static\s+var\s+schemas\s*:/);
  if (schemasBody === null) {
    throw new Error(`${file}: the migration plan declares no schemas list`);
  }

  const stagesBody = declaredBlockBody(text, /static\s+var\s+stages\s*:/);
  if (stagesBody === null) {
    throw new Error(`${file}: the migration plan declares no stages list`);
  }

  const stages = wiredStages(text, stagesBody, file);

  return {
    schemas: [...schemasBody.matchAll(/([A-Za-z_][A-Za-z0-9_]*)\.self/g)].map((entry) => entry[1]),
    stages,
    customStageCount: stages.filter((stage) => stage.kind === "custom").length,
    lightweightStageCount: stages.filter((stage) => stage.kind === "lightweight").length,
  };
}

/**
 * @param {string} text Comment-stripped source.
 * @param {RegExp} header Pattern matching the declaration whose block is wanted.
 * @return {string|null} The text between that declaration's braces, or null when it is absent.
 */
function declaredBlockBody(text, header) {
  const match = header.exec(text);
  if (match === null) return null;

  const braceIndex = text.indexOf("{", match.index + match[0].length);
  if (braceIndex === -1) return null;

  return text.slice(braceIndex + 1, matchingBraceIndex(text, braceIndex));
}

/**
 * Resolves every stage the `stages` array actually runs to the kind of stage it is.
 * @param {string} text Comment-stripped source of the migration plan.
 * @param {string} stagesBody The body of the `stages` computed property.
 * @param {string} file Repo-relative path, for error messages.
 * @return {Array<{name: string|null, kind: string}>} The wired stages, inline ones first.
 */
function wiredStages(text, stagesBody, file) {
  const declared = new Map();
  const declarationPattern =
    /\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=\n]*)?=\s*MigrationStage\s*\.\s*(custom|lightweight)\b/g;
  for (const match of text.matchAll(declarationPattern)) {
    declared.set(match[1], match[2]);
  }

  const {kinds, rest} = stripInlineStages(stagesBody);
  const stages = kinds.map((kind) => ({name: null, kind}));

  for (const identifier of rest.match(/[A-Za-z_][A-Za-z0-9_]*/g) ?? []) {
    const kind = declared.get(identifier);
    if (kind === undefined) {
      throw new Error(
        `${file}: AscendMigrationPlan.stages references ${identifier}, but nothing declares it as ` +
        `\`static let ${identifier} = MigrationStage.custom(...)\` or \`.lightweight(...)\`. A ` +
        "stage this checker cannot classify cannot excuse a column that existing rows have no " +
        "value for"
      );
    }
    stages.push({name: identifier, kind});
  }

  return stages;
}

/**
 * @param {string} stagesBody The body of the `stages` computed property.
 * @return {{kinds: string[], rest: string}} Inline stage kinds, and the body with them removed.
 */
function stripInlineStages(stagesBody) {
  const kinds = [];
  let rest = "";
  let index = 0;

  while (index < stagesBody.length) {
    const match = /MigrationStage\s*\.\s*(custom|lightweight)\b/.exec(stagesBody.slice(index));
    if (match === null) {
      rest += stagesBody.slice(index);
      break;
    }

    rest += stagesBody.slice(index, index + match.index);
    kinds.push(match[1]);

    let cursor = index + match.index + match[0].length;
    while (cursor < stagesBody.length && /\s/.test(stagesBody[cursor])) cursor += 1;

    if (stagesBody[cursor] === "(") {
      let depth = 0;
      while (cursor < stagesBody.length) {
        if (stagesBody[cursor] === "(") depth += 1;
        if (stagesBody[cursor] === ")") {
          depth -= 1;
          if (depth === 0) {
            cursor += 1;
            break;
          }
        }
        cursor += 1;
      }
    }

    index = cursor;
  }

  return {kinds, rest};
}

/**
 * Reduces parsed models to the comparable shape recorded in the baseline.
 *
 * Frozen copies are keyed by the schema version that owns them, because two versions freezing the
 * same class is the normal way a model changes twice - and a bare class name would collapse them.
 * @param {Array<object>} models Parsed models.
 * @return {Record<string, Record<string, {type: string, optional: boolean, hasDefault: boolean}>>} The shape.
 */
export function shapeOf(models) {
  const shape = {};
  const keyed = models.map((model) => ({model, key: model.qualifiedName ?? model.name}));

  for (const {model, key} of keyed.sort((a, b) => a.key.localeCompare(b.key))) {
    const properties = {};
    for (const property of [...model.properties].sort((a, b) => a.name.localeCompare(b.name))) {
      properties[property.name] = {
        type: property.type,
        optional: property.optional,
        hasDefault: property.hasDefault,
      };
    }
    shape[key] = properties;
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
 *
 * A stage does not excuse a column on its own. `customStageColumns` in the baseline names each
 * column a stage computes, so a second unrelated required column cannot ride in on the first one's
 * stage - the developer has to say, in the diff, which column the stage covers.
 * @param {{baseline: object, currentShape: object, frozenShape: object, plan: object, currentSchema: object}} input Parsed facts.
 * @return {string[]} Violations, empty when the change is safe.
 */
export function checkShapeDelta(input) {
  const violations = [];
  const baselineShape = input.baseline.models ?? {};
  const newCustomStages = input.plan.customStageCount - (input.baseline.customStageCount ?? 0);
  const coveredColumns = new Set(input.baseline.customStageColumns ?? []);

  for (const [model, properties] of Object.entries(input.currentShape)) {
    const baselineProperties = baselineShape[model];
    // A model that did not exist has no rows, so nothing has to be defaulted into them.
    if (!baselineProperties) continue;

    for (const [name, property] of Object.entries(properties)) {
      const before = baselineProperties[name];
      const column = `${model}.${name}`;
      const covered = coveredColumns.has(column) && newCustomStages > 0;
      const isNewColumn = !before;
      const becameRequired = Boolean(before) && before.optional && !property.optional;

      if (isNewColumn || becameRequired) {
        if (property.optional || property.hasDefault || covered) continue;

        violations.push(
          `${model}.${name} is ${isNewColumn ? "new" : "newly required"}, non-optional, and has no ` +
          "default, and no custom stage in this change claims it. Existing rows have no value to " +
          "write. Pick one: make it optional; give it a default if a single blanket value is " +
          "honest; or add a custom MigrationStage that computes the right value per record (see " +
          `AscendMigrationPlan.migrateV1toV2) and list "${column}" in customStageColumns in ` +
          "SharedTestVectors/swiftdata-schema-shape.json"
        );
        continue;
      }

      if (before.type === undefined) continue;
      if (unwrappedType(before.type) === unwrappedType(property.type)) continue;
      if (covered) continue;

      violations.push(
        `${model}.${name} changed type from ${before.type} to ${property.type}. A stored column ` +
        "cannot be reinterpreted in place: lightweight migration drops the old column and takes " +
        "the new one's default, so every existing row loses its value. Decompose the change (see " +
        "the skill's Step 3), or add a custom MigrationStage that converts each record and list " +
        `"${column}" in customStageColumns in SharedTestVectors/swiftdata-schema-shape.json`
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

/** Baseline fields a developer writes by hand, so they are not part of what `--update` records. */
const ANNOTATION_KEYS = new Set(["customStageColumns"]);

/**
 * Whether the recorded baseline still describes the sources.
 *
 * Compared canonically, so re-ordering the JSON is not a stale baseline, and ignoring the
 * hand-written annotations, which describe the change rather than the sources.
 * @param {object} baseline Recorded baseline.
 * @param {object} current Freshly parsed baseline-shaped record.
 * @return {boolean} True when they describe the same shape.
 */
export function baselineMatches(baseline, current) {
  return canonicalJson(withoutAnnotations(baseline)) === canonicalJson(withoutAnnotations(current));
}

/** @param {object} record A baseline-shaped record. @return {object} It, minus the annotations. */
function withoutAnnotations(record) {
  return Object.fromEntries(
    Object.entries(record ?? {}).filter(([key]) => !ANNOTATION_KEYS.has(key))
  );
}

/** @param {unknown} value Any JSON value. @return {string} Its key-order-independent encoding. */
function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value === null || typeof value !== "object") return JSON.stringify(value) ?? "null";

  const entries = Object.entries(value)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, entry]) => `${JSON.stringify(key)}:${canonicalJson(entry)}`);

  return `{${entries.join(",")}}`;
}

#!/usr/bin/env node
// Builds the Ascend Mountain athlete asset from public-domain (CC0) Quaternius characters.
//
//   node scripts/build-ascend-athlete.mjs
//
// Sources: Quaternius "Ultimate Modular Men Pack" (CC0 1.0), served as GLB by poly.pizza. All
// characters in the pack share one 62-joint rig, so a head, top, bottom and shoes from different
// characters assemble onto one skeleton. The script downloads the exact files below, bakes each
// chosen part into the rig's rest pose in model space (metres, +Y up), and writes
//   AscendApp/Features/AscendMountain/Resources/ascend-athlete.json  (skeleton + part layout)
//   AscendApp/Features/AscendMountain/Resources/ascend-athlete.bin   (vertex and index buffers)
// which `MountainAthleteAsset` reads. Re-running it reproduces the committed files byte for byte.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SOURCES = {
  casual2: 'https://static.poly.pizza/90a9e2d4-053f-42f1-99a2-8f5e1180ea7f.glb',
  beach: 'https://static.poly.pizza/f771a536-1c18-4a47-bb56-ceea4b603455.glb',
  hoodie: 'https://static.poly.pizza/bcd66ec5-5e81-4901-a222-47abc875fe2a.glb',
};

// The V1 athlete: fitted tank, shorts, trainers. Each primitive's source material is mapped to a
// colour slot the app tints, so the look is data rather than baked colour.
const PARTS = [
  { name: 'head', source: 'casual2', mesh: 'Casual2_Head', slots: { Skin: 'skin', Skin_Darker: 'skinShade', Hair: 'hair', Eyebrows: 'hair', Eye: 'eyes' } },
  { name: 'top', source: 'beach', mesh: 'Beach_Body', slots: { Skin: 'skin', LightBrown: 'top' } },
  { name: 'bottom', source: 'hoodie', mesh: 'Casual_Legs', slots: { Skin: 'skin', LightBlue: 'bottom' } },
  { name: 'shoes', source: 'casual2', mesh: 'Casual2_Feet', slots: { White: 'shoe', Red_Dark: 'shoeAccent' } },
];
const BASE = 'casual2';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(root, 'AscendApp/Features/AscendMountain/Resources');

// ---------- small matrix kit (column-major 4x4, like glTF) ----------
const identity = () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
function multiply(a, b) {
  const out = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) for (let k = 0; k < 4; k++) out[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return out;
}
function compose(t = [0, 0, 0], q = [0, 0, 0, 1], s = [1, 1, 1]) {
  const [x, y, z, w] = q;
  const m = [
    1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
    2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
    2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
    t[0], t[1], t[2], 1,
  ];
  for (let c = 0; c < 3; c++) for (let r = 0; r < 3; r++) m[c * 4 + r] *= s[c];
  return m;
}
function invert(m) {
  const inv = new Array(16);
  const [a00, a01, a02, a03, a10, a11, a12, a13, a20, a21, a22, a23, a30, a31, a32, a33] = m;
  const b00 = a00 * a11 - a01 * a10, b01 = a00 * a12 - a02 * a10, b02 = a00 * a13 - a03 * a10, b03 = a01 * a12 - a02 * a11;
  const b04 = a01 * a13 - a03 * a11, b05 = a02 * a13 - a03 * a12, b06 = a20 * a31 - a21 * a30, b07 = a20 * a32 - a22 * a30;
  const b08 = a20 * a33 - a23 * a30, b09 = a21 * a32 - a22 * a31, b10 = a21 * a33 - a23 * a31, b11 = a22 * a33 - a23 * a32;
  const det = 1 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06);
  inv[0] = (a11 * b11 - a12 * b10 + a13 * b09) * det; inv[1] = (a02 * b10 - a01 * b11 - a03 * b09) * det;
  inv[2] = (a31 * b05 - a32 * b04 + a33 * b03) * det; inv[3] = (a22 * b04 - a21 * b05 - a23 * b03) * det;
  inv[4] = (a12 * b08 - a10 * b11 - a13 * b07) * det; inv[5] = (a00 * b11 - a02 * b08 + a03 * b07) * det;
  inv[6] = (a32 * b02 - a30 * b05 - a33 * b01) * det; inv[7] = (a20 * b05 - a22 * b02 + a23 * b01) * det;
  inv[8] = (a10 * b10 - a11 * b08 + a13 * b06) * det; inv[9] = (a01 * b08 - a00 * b10 - a03 * b06) * det;
  inv[10] = (a30 * b04 - a31 * b02 + a33 * b00) * det; inv[11] = (a21 * b02 - a20 * b04 - a23 * b00) * det;
  inv[12] = (a11 * b07 - a10 * b09 - a12 * b06) * det; inv[13] = (a00 * b09 - a01 * b07 + a02 * b06) * det;
  inv[14] = (a31 * b01 - a30 * b03 - a32 * b00) * det; inv[15] = (a20 * b03 - a21 * b01 + a22 * b00) * det;
  return inv;
}
const apply = (m, v, w = 1) => [0, 1, 2].map(r => m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] * w);
function decompose(m) {
  const sx = Math.hypot(m[0], m[1], m[2]), sy = Math.hypot(m[4], m[5], m[6]), sz = Math.hypot(m[8], m[9], m[10]);
  const r = [m[0] / sx, m[1] / sx, m[2] / sx, m[4] / sy, m[5] / sy, m[6] / sy, m[8] / sz, m[9] / sz, m[10] / sz];
  const trace = r[0] + r[4] + r[8]; let q;
  if (trace > 0) { const s = Math.sqrt(trace + 1) * 2; q = [(r[5] - r[7]) / s, (r[6] - r[2]) / s, (r[1] - r[3]) / s, 0.25 * s]; }
  else if (r[0] > r[4] && r[0] > r[8]) { const s = Math.sqrt(1 + r[0] - r[4] - r[8]) * 2; q = [0.25 * s, (r[3] + r[1]) / s, (r[6] + r[2]) / s, (r[5] - r[7]) / s]; }
  else if (r[4] > r[8]) { const s = Math.sqrt(1 + r[4] - r[0] - r[8]) * 2; q = [(r[3] + r[1]) / s, 0.25 * s, (r[7] + r[5]) / s, (r[6] - r[2]) / s]; }
  else { const s = Math.sqrt(1 + r[8] - r[0] - r[4]) * 2; q = [(r[6] + r[2]) / s, (r[7] + r[5]) / s, 0.25 * s, (r[1] - r[3]) / s]; }
  return { t: [m[12], m[13], m[14]], r: q, s: [sx, sy, sz] };
}

// ---------- glTF reading ----------
async function loadGLB(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`download failed ${response.status}: ${url}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  const jsonLength = buffer.readUInt32LE(12);
  const json = JSON.parse(buffer.subarray(20, 20 + jsonLength).toString());
  const binStart = 20 + jsonLength + 8;
  return { json, bin: buffer.subarray(binStart, binStart + buffer.readUInt32LE(20 + jsonLength)) };
}
function readAccessor({ json, bin }, index) {
  const accessor = json.accessors[index]; const view = json.bufferViews[accessor.bufferView];
  const components = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 }[accessor.type];
  const reader = { 5126: ['readFloatLE', 4], 5125: ['readUInt32LE', 4], 5123: ['readUInt16LE', 2], 5121: ['readUInt8', 1] }[accessor.componentType];
  const stride = view.byteStride || components * reader[1];
  const base = (view.byteOffset || 0) + (accessor.byteOffset || 0); const out = [];
  for (let i = 0; i < accessor.count; i++) {
    const item = []; for (let c = 0; c < components; c++) item.push(bin[reader[0]](base + i * stride + c * reader[1]));
    out.push(item);
  }
  return out;
}
function worldMatrices(json) {
  const world = new Array(json.nodes.length);
  const visit = (index, parent) => {
    const node = json.nodes[index];
    const local = node.matrix || compose(node.translation, node.rotation, node.scale);
    world[index] = multiply(parent, local);
    for (const child of node.children || []) visit(child, world[index]);
  };
  for (const index of json.scenes[json.scene || 0].nodes) visit(index, identity());
  return world;
}

// ---------- build ----------
const glbs = {};
for (const [key, url] of Object.entries(SOURCES)) glbs[key] = await loadGLB(url);

// The rig's armature carries a 100x scale that its meshes undo; the app poses joints in metres,
// so every joint frame is re-expressed at unit scale. Vertices are baked in model space, so the
// rest pose is unchanged.
const unitScale = m => {
  const out = m.slice();
  for (let c = 0; c < 3; c++) { const l = Math.hypot(m[c * 4], m[c * 4 + 1], m[c * 4 + 2]); for (let r = 0; r < 3; r++) out[c * 4 + r] = m[c * 4 + r] / l; }
  return out;
};
const base = glbs[BASE]; const baseWorld = worldMatrices(base.json).map(unitScale);
const skin = base.json.skins[0]; const jointNodes = skin.joints;
const jointIndex = new Map(jointNodes.map((node, i) => [node, i]));
const parentOf = {}; base.json.nodes.forEach((n, i) => (n.children || []).forEach(c => (parentOf[c] = i)));
const joints = jointNodes.map((node, i) => {
  const parentNode = parentOf[node]; const parent = jointIndex.has(parentNode) ? jointIndex.get(parentNode) : -1;
  const local = parent < 0 ? baseWorld[node] : multiply(invert(baseWorld[jointNodes[parent]]), baseWorld[node]);
  const rest = decompose(local);
  return { name: base.json.nodes[node].name, parent, translation: rest.t, rotation: rest.r, scale: rest.s, inverseBind: invert(baseWorld[node]) };
});

const floats = []; const indices = []; const parts = []; let minY = Infinity, maxY = -Infinity;
for (const part of PARTS) {
  const glb = glbs[part.source]; const world = worldMatrices(glb.json);
  const nodeIndex = glb.json.nodes.findIndex(n => n.name === part.mesh);
  if (nodeIndex < 0) throw new Error(`no mesh node ${part.mesh}`);
  const node = glb.json.nodes[nodeIndex]; const partSkin = glb.json.skins[node.skin];
  const inverseBinds = readAccessor(glb, partSkin.inverseBindMatrices);
  const jointMatrices = partSkin.joints.map((j, i) => multiply(world[j], inverseBinds[i]));
  const partJointToBase = partSkin.joints.map(j => {
    const name = glb.json.nodes[j].name; const index = joints.findIndex(joint => joint.name === name);
    if (index < 0) throw new Error(`joint ${name} missing from base rig`); return index;
  });
  for (const primitive of glb.json.meshes[node.mesh].primitives) {
    const materialName = glb.json.materials[primitive.material].name;
    const slot = part.slots[materialName];
    if (!slot) throw new Error(`${part.mesh}: unmapped material ${materialName}`);
    const positions = readAccessor(glb, primitive.attributes.POSITION);
    const normals = readAccessor(glb, primitive.attributes.NORMAL);
    const jointSets = readAccessor(glb, primitive.attributes.JOINTS_0);
    const weightSets = readAccessor(glb, primitive.attributes.WEIGHTS_0);
    const primitiveIndices = readAccessor(glb, primitive.indices).map(i => i[0]);
    const vertexStart = floats.length / 14;
    for (let v = 0; v < positions.length; v++) {
      const total = weightSets[v].reduce((a, b) => a + b, 0) || 1;
      let p = [0, 0, 0], n = [0, 0, 0];
      for (let k = 0; k < 4; k++) {
        const w = weightSets[v][k] / total; if (w === 0) continue;
        const m = jointMatrices[jointSets[v][k]];
        const pp = apply(m, positions[v], 1), nn = apply(m, normals[v], 0);
        for (let c = 0; c < 3; c++) { p[c] += pp[c] * w; n[c] += nn[c] * w; }
      }
      const nl = Math.hypot(...n) || 1; n = n.map(x => x / nl);
      minY = Math.min(minY, p[1]); maxY = Math.max(maxY, p[1]);
      const js = jointSets[v].map(j => partJointToBase[j]); const ws = weightSets[v].map(w => w / total);
      floats.push(...p, ...n, ...js, ...ws);
    }
    const indexStart = indices.length;
    for (const i of primitiveIndices) indices.push(vertexStart + i);
    parts.push({ name: `${part.name}.${materialName}`, slot, vertexStart, vertexCount: positions.length, indexStart, indexCount: primitiveIndices.length });
  }
}

// Stand the athlete on y = 0.
const vertexCount = floats.length / 14;
for (let v = 0; v < vertexCount; v++) floats[v * 14 + 1] -= minY;
joints.forEach(joint => { if (joint.parent < 0) joint.translation[1] -= minY; joint.inverseBind = multiply(joint.inverseBind, compose([0, minY, 0])); });

const round = x => Math.round(x * 1e6) / 1e6;
const header = {
  format: 'ascend-athlete-v1',
  license: 'CC0 1.0 - Quaternius, Ultimate Modular Men Pack',
  sources: SOURCES,
  height: round(maxY - minY),
  vertexLayout: 'positions f32x3, normals f32x3, joints f32x4, weights f32x4 (interleaved, 14 floats); indices u32',
  vertexCount, indexCount: indices.length,
  joints: joints.map(j => ({ name: j.name, parent: j.parent, translation: j.translation.map(round), rotation: j.rotation.map(round), scale: j.scale.map(round), inverseBind: j.inverseBind.map(round) })),
  parts,
};
const bin = Buffer.alloc(floats.length * 4 + indices.length * 4);
floats.forEach((f, i) => bin.writeFloatLE(f, i * 4));
indices.forEach((x, i) => bin.writeUInt32LE(x, floats.length * 4 + i * 4));
fs.writeFileSync(path.join(outDir, 'ascend-athlete.json'), JSON.stringify(header, null, 1) + '\n');
fs.writeFileSync(path.join(outDir, 'ascend-athlete.bin'), bin);
console.log(`athlete: ${vertexCount} vertices, ${indices.length / 3} triangles, ${parts.length} parts, height ${header.height.toFixed(3)} m, ${(bin.length / 1024).toFixed(0)} KB`);

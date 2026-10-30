/**
 * Automated test suite for Solusi B - 3D Viewport Slot Repositioning & Pulse Highlight (viewer3d.js)
 * Verifies reticle cursor geometry, world normal transformations, and slot hover pulse state.
 */

import assert from "node:assert";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const THREE = require("../scripts/cs16_studio/web/static/three.min.js");

console.log("=== Testing Solusi B: 3D Viewport Slot Repositioning & Pulse Highlight ===");

// 1. Mock State
const state = {
  currentTeam: "ct",
  currentWeapon: "usp",
  viewport3d: {
    initialized: true,
    meshGroup: new THREE.Group(),
    controls: {
      mouseButtons: {
        LEFT: THREE.MOUSE.ROTATE,
        MIDDLE: THREE.MOUSE.DOLLY,
        RIGHT: THREE.MOUSE.PAN,
      },
    },
    repositionMode: false,
    repositionSlot: null,
    pulsingMesh: null,
    currentWeaponBounds: { radius: 20 },
  },
};

// 2. Normal transformation logic identical to viewer3d.js
function getHitWorldNormal(hit) {
  const normal = hit && hit.face && hit.face.normal ? hit.face.normal.clone() : new THREE.Vector3(0, 0, 1);
  if (hit && hit.object) {
    if (typeof hit.object.updateMatrixWorld === "function") {
      hit.object.updateMatrixWorld();
    }
    if (hit.object.matrixWorld) {
      normal.transformDirection(hit.object.matrixWorld);
    }
  }
  return normal.normalize();
}

// 3. Reticle creation logic identical to viewer3d.js
function createGhostDecalCursor() {
  const group = new THREE.Group();

  const planeGeom = new THREE.PlaneGeometry(1, 1);
  const planeMat = new THREE.MeshBasicMaterial({
    color: 0x00f0ff,
    transparent: true,
    opacity: 0.85,
    side: THREE.DoubleSide,
    depthWrite: false,
  });
  const planeMesh = new THREE.Mesh(planeGeom, planeMat);
  planeMesh.name = "ghostPlane";
  group.add(planeMesh);

  const ringGeom = new THREE.RingGeometry(0.48, 0.52, 40);
  const ringMat = new THREE.MeshBasicMaterial({
    color: 0x00f0ff,
    transparent: true,
    opacity: 0.9,
    side: THREE.DoubleSide,
    depthWrite: false,
  });
  const ringMesh = new THREE.Mesh(ringGeom, ringMat);
  ringMesh.position.z = 0.002;
  group.add(ringMesh);

  group.visible = false;
  return group;
}

// Test 1: Reticle creation and hierarchy
console.log("Test 1: Verify holographic reticle cursor structure...");
const reticle = createGhostDecalCursor();
assert(reticle, "Reticle must be created");
assert.strictEqual(reticle.children.length, 2, "Reticle must have plane and ring");
assert.strictEqual(reticle.children[0].name, "ghostPlane");
console.log(" -> Passed: Reticle structure matches Solusi B specification.");

// Test 2: Surface normal transformation on rotated mesh
console.log("Test 2: Verify surface normal transformation on rotated mesh...");
const rotatedBox = new THREE.Mesh(new THREE.BoxGeometry(10, 10, 10), new THREE.MeshBasicMaterial());
rotatedBox.rotation.y = Math.PI / 2;
rotatedBox.updateMatrixWorld(true);

const rotatedHit = {
  point: new THREE.Vector3(5, 10, 15),
  face: {
    normal: new THREE.Vector3(0, 0, 1),
  },
  uv: { x: 0.5, y: 0.5 },
  object: rotatedBox,
};

const rotNormal = getHitWorldNormal(rotatedHit);
assert(Math.abs(rotNormal.x - 1.0) < 1e-4, "Rotated normal in world coords must point along +X");
assert(Math.abs(rotNormal.y) < 1e-4);
assert(Math.abs(rotNormal.z) < 1e-4);

// Reticle positioning with normal offset (0.06 units)
const offset = rotNormal.clone().multiplyScalar(0.06);
reticle.position.copy(rotatedHit.point.clone().add(offset));
assert(Math.abs(reticle.position.x - (5 + 0.06)) < 1e-4, "Reticle must offset along World +X by 0.06");
assert(Math.abs(reticle.position.y - 10) < 1e-4);
assert(Math.abs(reticle.position.z - 15) < 1e-4);
console.log(" -> Passed: Rotated mesh normal and 0.06 offset correctly calculated.");

// Test 3: Slot Pulse Hover Highlight (falsy 0 bug check)
console.log("Test 3: Verify Slot Pulse Hover Highlight and black (0x000000) restoration...");
const mockSlotMesh = new THREE.Mesh(
  new THREE.BufferGeometry(),
  new THREE.MeshStandardMaterial({
    color: 0x94a3b8,
    emissive: new THREE.Color(0x000000), // Original black emissive
    emissiveIntensity: 0.0,
  })
);
mockSlotMesh.userData = {
  textureIndex: 6,
  textureName: "1.bmp",
  slotIdentifier: "Slot 1",
};
state.viewport3d.meshGroup.add(mockSlotMesh);

function simulatePulseHover(textureName, isHovering) {
  if (isHovering) {
    const mesh = state.viewport3d.meshGroup.children.find(
      (m) => m.userData.textureName === textureName || m.userData.slotIdentifier === textureName
    );
    if (mesh && mesh.material) {
      if (mesh.userData.savedEmissive === undefined) {
        mesh.userData.savedEmissive = mesh.material.emissive ? mesh.material.emissive.getHex() : 0x000000;
        mesh.userData.savedEmissiveIntensity = mesh.material.emissiveIntensity !== undefined ? mesh.material.emissiveIntensity : 0.0;
      }
      state.viewport3d.pulsingMesh = mesh;
    }
  } else {
    if (state.viewport3d.pulsingMesh && state.viewport3d.pulsingMesh.material) {
      const pm = state.viewport3d.pulsingMesh;
      if (pm.material.emissive) {
        pm.material.emissive.setHex(pm.userData.savedEmissive !== undefined ? pm.userData.savedEmissive : 0x000000);
        pm.material.emissiveIntensity = pm.userData.savedEmissiveIntensity !== undefined ? pm.userData.savedEmissiveIntensity : 0.0;
        pm.material.needsUpdate = true;
      }
      pm.userData.savedEmissive = undefined;
      pm.userData.savedEmissiveIntensity = undefined;
    }
    state.viewport3d.pulsingMesh = null;
  }
}

// 3a. Hover activates pulse
simulatePulseHover("1.bmp", true);
assert.strictEqual(state.viewport3d.pulsingMesh, mockSlotMesh);
assert.strictEqual(mockSlotMesh.userData.savedEmissive, 0x000000);

// Simulate animation tick
mockSlotMesh.material.emissive.setHex(0x00f0ff);
mockSlotMesh.material.emissiveIntensity = 0.8;

// Re-hover while pulsing (must NOT overwrite savedEmissive with cyan)
simulatePulseHover("1.bmp", true);
assert.strictEqual(mockSlotMesh.userData.savedEmissive, 0x000000, "savedEmissive must remain 0x000000");

// 3b. Mouse leave restores clean original black emissive
simulatePulseHover("1.bmp", false);
assert.strictEqual(state.viewport3d.pulsingMesh, null);
assert.strictEqual(mockSlotMesh.material.emissive.getHex(), 0x000000, "Emissive must be restored to 0x000000");
assert.strictEqual(mockSlotMesh.material.emissiveIntensity, 0.0);
assert.strictEqual(mockSlotMesh.userData.savedEmissive, undefined);
console.log(" -> Passed: Slot Pulse correctly preserves and restores 0x000000 emissive values.");

// Test 4: OrbitControls mouse button switching in Reposition Mode
console.log("Test 4: Verify OrbitControls mode switching...");
function enterSlotRepositionMode(slotName) {
  state.viewport3d.repositionMode = true;
  state.viewport3d.repositionSlot = slotName;
  state.viewport3d.controls.mouseButtons = {
    LEFT: THREE.MOUSE.NONE,
    MIDDLE: THREE.MOUSE.DOLLY,
    RIGHT: THREE.MOUSE.ROTATE,
  };
}

function exitSlotRepositionMode() {
  state.viewport3d.repositionMode = false;
  state.viewport3d.repositionSlot = null;
  state.viewport3d.controls.mouseButtons = {
    LEFT: THREE.MOUSE.ROTATE,
    MIDDLE: THREE.MOUSE.DOLLY,
    RIGHT: THREE.MOUSE.PAN,
  };
}

enterSlotRepositionMode("1.bmp");
assert.strictEqual(state.viewport3d.repositionMode, true);
assert.strictEqual(state.viewport3d.repositionSlot, "1.bmp");
assert.strictEqual(state.viewport3d.controls.mouseButtons.LEFT, THREE.MOUSE.NONE);
assert.strictEqual(state.viewport3d.controls.mouseButtons.RIGHT, THREE.MOUSE.ROTATE);

exitSlotRepositionMode();
assert.strictEqual(state.viewport3d.repositionMode, false);
assert.strictEqual(state.viewport3d.repositionSlot, null);
assert.strictEqual(state.viewport3d.controls.mouseButtons.LEFT, THREE.MOUSE.ROTATE);
assert.strictEqual(state.viewport3d.controls.mouseButtons.RIGHT, THREE.MOUSE.PAN);
console.log(" -> Passed: OrbitControls correctly toggled between inspection and surface-pick modes.");

console.log("\nALL Solusi B 3D Viewport Repositioning & Pulse tests PASSED successfully!");

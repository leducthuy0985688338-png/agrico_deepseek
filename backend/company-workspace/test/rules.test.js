import { before, after, beforeEach, test } from "node:test";
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  setDoc,
  getDoc,
  getDocs,
  collection,
  serverTimestamp,
  Timestamp,
  updateDoc,
} from "firebase/firestore";
import { ref, uploadBytes, getBytes } from "firebase/storage";
let env;
const projectId = "demo-agrico-workspace";
const member = (uid, role = "fieldWorker") => ({
  userId: uid,
  membershipId: uid,
  farmId: "farm",
  active: true,
  roles: [{ role, scopes: ["allFarm"] }],
  offlineUntil: Timestamp.fromMillis(Date.now() + 86400000),
  deniedPermissions: [],
  adminRevision: 1,
});
before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8088,
      rules: readFileSync(
        new URL(
          "../../../docs/security/agrico-company-workspace.rules",
          import.meta.url,
        ),
        "utf8",
      ),
    },
    storage: {
      host: "127.0.0.1",
      port: 9199,
      rules: readFileSync(
        new URL(
          "../../../docs/security/agrico-company-workspace.storage.rules",
          import.meta.url,
        ),
        "utf8",
      ),
    },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const id of ["admin", "worker", "other"])
      await setDoc(
        doc(db, "agrico_memberships", id),
        member(id, id === "admin" ? "systemAdmin" : "fieldWorker"),
      );
    await setDoc(doc(db, "agrico_access_admins", "admin"), {
      active: true,
      farmId: "farm",
    });
  });
});
const db = (uid) => env.authenticatedContext(uid).firestore();
const path = "agrico_workspace/farm/users/worker/commands/op";
const command = () => ({
  schemaVersion: 1,
  action: "form.create",
  entityId: "f",
  expectedRevision: 0,
  payload: {},
  status: "pending",
  createdAt: serverTimestamp(),
});
test("own command create allowed but mutation and other user denied", async () => {
  await assertSucceeds(setDoc(doc(db("worker"), path), command()));
  await assertFails(updateDoc(doc(db("worker"), path), { status: "accepted" }));
  await assertFails(getDoc(doc(db("other"), path)));
});
test("initial nonexistent command read works for idempotent transaction", async () => {
  await assertSucceeds(getDoc(doc(db("worker"), path)));
});
test("unknown actions and forged server fields denied", async () => {
  await assertFails(
    setDoc(doc(db("worker"), path), { ...command(), action: "cash.post" }),
  );
  await assertFails(
    setDoc(doc(db("worker"), path), { ...command(), result: { ok: true } }),
  );
});
test("private records inbox and audit are server-only", async () => {
  for (const p of [
    "records/task~f",
    "users/worker/inbox/task~f",
    "events/task~f~1",
  ]) {
    await assertFails(
      setDoc(doc(db("admin"), `agrico_workspace/farm/${p}`), { hello: 1 }),
    );
    await assertFails(getDoc(doc(db("worker"), `agrico_workspace/farm/${p}`)));
  }
});
test("accepted results are server-only even before policy revision changes", async () => {
  await env.withSecurityRulesDisabled(async (c) =>
    setDoc(doc(c.firestore(), path), {
      ...command(),
      status: "accepted",
      resultPolicyRevision: 1,
      result: { private: "content" },
    }),
  );
  await assertFails(getDoc(doc(db("worker"), path)));
  await assertFails(
    getDocs(
      collection(db("worker"), "agrico_workspace/farm/users/worker/commands"),
    ),
  );
  await env.withSecurityRulesDisabled(async (c) =>
    updateDoc(doc(c.firestore(), "agrico_memberships/worker"), {
      adminRevision: 2,
    }),
  );
  await assertFails(getDoc(doc(db("worker"), path)));
});
test("expired inactive or cross-farm membership cannot submit", async () => {
  for (const changes of [
    { active: false },
    { farmId: "else" },
    { offlineUntil: Timestamp.fromMillis(0) },
    { deniedPermissions: ["cloud.sync"] },
  ]) {
    await env.withSecurityRulesDisabled(async (c) =>
      setDoc(doc(c.firestore(), "agrico_memberships/worker"), {
        ...member("worker"),
        ...changes,
      }),
    );
    await assertFails(setDoc(doc(db("worker"), path), command()));
  }
});
test("file immutable upload own path and grants enforce current policy", async () => {
  const digest = "a".repeat(64),
    path = `company-workspace/farm/files/worker/${digest}`;
  const storage = env.authenticatedContext("worker").storage();
  const bytes = new Uint8Array([1, 2]);
  await assertSucceeds(
    uploadBytes(ref(storage, path), bytes, {
      customMetadata: { sha256: digest },
    }),
  );
  await assertFails(
    uploadBytes(ref(storage, path), bytes, {
      customMetadata: { sha256: digest },
    }),
  );
  const other = env.authenticatedContext("other").storage();
  await assertFails(getBytes(ref(other, path)));
  await env.withSecurityRulesDisabled(async (c) =>
    setDoc(
      doc(
        c.firestore(),
        `agrico_workspace/farm/users/other/file_grants/${digest}`,
      ),
      { path, revision: 1, until: Timestamp.fromMillis(Date.now() + 60000) },
    ),
  );
  await assertSucceeds(getBytes(ref(other, path)));
  await env.withSecurityRulesDisabled(async (c) =>
    updateDoc(doc(c.firestore(), "agrico_memberships/other"), {
      adminRevision: 2,
    }),
  );
  await assertFails(getBytes(ref(other, path)));
});
test("full sensitive snapshots are root admin only", async () => {
  const digest = "b".repeat(64);
  const path = `company-workspace/farm/snapshots/admin/${digest}`;
  await assertSucceeds(
    uploadBytes(
      ref(env.authenticatedContext("admin").storage(), path),
      new Uint8Array([1]),
      { customMetadata: { sha256: digest } },
    ),
  );
  await assertFails(
    getBytes(ref(env.authenticatedContext("worker").storage(), path)),
  );
});

test("processing or rejected receipts containing private result fields also fail closed", async () => {
  for (const status of ["pending","processing","rejected","accepted"]) {
    await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(),path), {...command(),status,result:{secret:"private"}}));
    await assertFails(getDoc(doc(db("worker"),path)));
  }
});

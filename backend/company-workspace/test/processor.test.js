import { before, after, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
process.env.GCLOUD_PROJECT = "demo-agrico-workspace";
process.env.GOOGLE_CLOUD_PROJECT = "demo-agrico-workspace";
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8088";
process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-agrico-workspace",
  storageBucket: "demo-agrico-workspace.appspot.com",
});
const { processCommand, processAssistant } = await import("../src/index.js");
const db = getFirestore();
let env;
const member = (uid) => ({
  userId: uid,
  membershipId: uid,
  farmId: "farm",
  active: true,
  roles: [{ role: "systemAdmin", scopes: ["allFarm"] }],
  offlineUntil: Timestamp.fromMillis(Date.now() + 86400000),
  departmentIds: ["D"],
  teamIds: [],
  projectIds: [],
  adminRevision: 1,
  displayName: uid,
});
before(
  async () =>
    (env = await initializeTestEnvironment({
      projectId: "demo-agrico-workspace",
      firestore: { host: "127.0.0.1", port: 8088 },
    })),
);
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  for (const uid of ["admin", "worker", "reviewer"])
    await db.doc(`agrico_memberships/${uid}`).set(member(uid));
  await db
    .doc("agrico_access_admins/admin")
    .set({ farmId: "farm", active: true });
});
async function event(
  op,
  action,
  id,
  revision = 0,
  payload = {},
  uid = "admin",
) {
  const ref = db.doc(`agrico_workspace/farm/users/${uid}/commands/${op}`);
  await ref.set({
    schemaVersion: 1,
    action,
    entityId: id,
    expectedRevision: revision,
    payload,
    status: "pending",
  });
  return {
    params: { farm: "farm", uid, op },
    data: { ref, data: () => ({ action }) },
  };
}
async function submit(...args) {
  const e = await event(...args);
  await processCommand(e);
  return (await e.data.ref.get()).data();
}
const task = {
  title: "Kiểm tra",
  details: "Nội dung",
  due: "2026-12-01",
  assignee: "worker",
};
test("duplicate trigger creates one code record and immutable audit", async () => {
  const e = await event("create", "task.create", "t", 0, task);
  await Promise.all([processCommand(e), processCommand(e)]);
  const c = (await e.data.ref.get()).data();
  assert.equal(c.status, "accepted");
  assert.equal(
    (await db.doc("agrico_workspace/farm/records/task~t").get()).data()
      .revision,
    1,
  );
  assert.equal(
    (
      await db.collection("agrico_workspace/farm/sequences").get()
    ).docs[0].data().value,
    1,
  );
  assert.equal(
    (await db.collection("agrico_workspace/farm/command_audit").get()).size,
    1,
  );
});
test("competing task revisions accept only one action", async () => {
  await submit("c", "task.create", "t", 0, task);
  await submit("accept", "task.accept", "t", 1, {}, "worker");
  await submit("start", "task.start", "t", 2, {}, "worker");
  const a = await event(
      "a",
      "task.progress",
      "t",
      3,
      { progress: 30 },
      "worker",
    ),
    b = await event("b", "task.progress", "t", 3, { progress: 60 }, "worker");
  await Promise.all([processCommand(a), processCommand(b)]);
  assert.deepEqual(
    [
      (await a.data.ref.get()).data().status,
      (await b.data.ref.get()).data().status,
    ].sort(),
    ["accepted", "rejected"],
  );
});
test("inbox filters current revoked domain access", async () => {
  await submit("f", "form.create", "f", 0, {
    templateId: "advance",
    fields: { amount: "100", currency: "VND", reason: "Đi công tác" },
  });
  await submit("r", "route.save", "r", 0, {
    templateId: "advance",
    department: "D",
    steps: ["reviewer"],
  });
  await submit("s", "form.submit", "f", 1, { routeId: "r" });
  const before = await submit("read", "inbox.list", "inbox", 0, {}, "reviewer");
  assert.equal(before.result.records.length, 1);
  await db
    .doc("agrico_memberships/reviewer")
    .update({ deniedPermissions: ["finance.approve"], adminRevision: 2 });
  const after = await submit("read2", "inbox.list", "inbox", 0, {}, "reviewer");
  assert.equal(after.result.records.length, 0);
});
test("concurrent chat messages both commit with distinct atomic server sequence", async () => {
  await submit("room", "room.create", "room", 0, {
    title: "Nhóm",
    members: ["worker"],
  });
  const a = await event("a", "message.create", "a", 1, {
      roomId: "room",
      text: "a",
    }),
    b = await event(
      "b",
      "message.create",
      "b",
      1,
      { roomId: "room", text: "b" },
      "worker",
    );
  await Promise.all([processCommand(a), processCommand(b)]);
  assert.equal(
    (await db.collection("agrico_workspace/farm/records").get()).size,
    3,
  );
  const r = await submit("read", "message.list", "room", 0, {}, "worker");
  assert.equal(r.result.records.length, 2);
  assert.deepEqual(
    r.result.records.map((v) => v.content.sequence),
    [2, 3],
  );
  assert.equal(r.result.room.revision, 3);
});
test("two final settlement approvals cannot overallocate one advance", async () => {
  await submit("f", "form.create", "f", 0, {
    templateId: "advance",
    fields: { amount: "1000", currency: "VND", reason: "x" },
  });
  await submit("r", "route.save", "r", 0, {
    templateId: "advance",
    department: "D",
    steps: ["reviewer"],
  });
  await submit("s", "form.submit", "f", 1, { routeId: "r" });
  const approved = await submit(
    "approve",
    "form.approve",
    "f",
    2,
    {},
    "reviewer",
  );
  assert.equal(approved.status, "accepted");
  const code = approved.result.record.code;
  await submit("sr", "route.save", "sr", 0, {
    templateId: "advanceSettlement",
    department: "D",
    steps: ["reviewer"],
  });
  for (const id of ["one", "two"]) {
    await submit(`c_${id}`, "form.create", id, 0, {
      templateId: "advanceSettlement",
      fields: {
        reference: code,
        received: "600",
        spent: "300",
        currency: "VND",
        reason: "x",
      },
    });
    await submit(`s_${id}`, "form.submit", id, 1, { routeId: "sr" });
  }
  const events = await Promise.all(
    ["one", "two"].map((id) =>
      event(`a_${id}`, "form.approve", id, 2, {}, "reviewer"),
    ),
  );
  await Promise.all(events.map(processCommand));
  assert.deepEqual(
    (await Promise.all(events.map((e) => e.data.ref.get())))
      .map((d) => d.data().status)
      .sort(),
    ["accepted", "rejected"],
  );
  assert.equal(
    (await db.doc("agrico_workspace/farm/advance_usage/f").get()).data().value,
    "6000000",
  );
});
test("assistant uses mocked provider, authorized context, no tools and rechecks policy", async () => {
  process.env.AGRICO_AI_API_KEY = "test-only";
  const fetchOriginal = globalThis.fetch;
  let body;
  globalThis.fetch = async (url, options) => {
    if (String(url) !== "https://api.deepseek.com/chat/completions")
      return fetchOriginal(url, options);
    body = JSON.parse(options.body);
    return {
      ok: true,
      json: async () => ({
        choices: [{ message: { content: "Không có hồ sơ được phép xem." } }],
      }),
    };
  };
  try {
    const e = await event("ask", "ai.ask", "ask", 0, {
      question: "Tình hình công việc?",
      language: "vi",
    });
    await processAssistant(e);
    const result = (await e.data.ref.get()).data();
    assert.equal(result.status, "accepted");
    assert.equal(body.tools, undefined);
    assert.equal(result.result.sourceCount, 0);
    assert(!JSON.stringify(result).includes("test-only"));
  } finally {
    globalThis.fetch = fetchOriginal;
  }
});
test("old inbox projection cannot expose a form after reviewer replacement", async () => {
  await submit("create", "form.create", "f", 0, {
    templateId: "advance",
    fields: { amount: "100", currency: "VND", reason: "x" },
  });
  await submit("route", "route.save", "route", 0, {
    templateId: "advance",
    department: "D",
    steps: ["reviewer"],
  });
  await submit("send", "form.submit", "f", 1, { routeId: "route" });
  await submit(
    "changes",
    "form.changes",
    "f",
    2,
    { reason: "Bổ sung" },
    "reviewer",
  );
  await submit("newroute", "route.save", "route", 1, {
    templateId: "advance",
    department: "D",
    steps: ["worker"],
  });
  await submit("resend", "form.submit", "f", 3, { routeId: "route" });
  const old = await submit("oldread", "inbox.list", "read", 0, {}, "reviewer");
  assert.equal(old.result.records.length, 0);
  const next = await submit("newread", "inbox.list", "read", 0, {}, "worker");
  assert.equal(next.result.records.length, 1);
});
test("source-linked chat rechecks current form participants", async () => {
  await submit("create", "form.create", "f", 0, {
    templateId: "advance",
    fields: { amount: "100", currency: "VND", reason: "x" },
  });
  await submit("route", "route.save", "route", 0, {
    templateId: "advance",
    department: "D",
    steps: ["reviewer"],
  });
  await submit("send", "form.submit", "f", 1, { routeId: "route" });
  await submit("chat", "room.create", "room", 0, {
    title: "Hồ sơ",
    members: ["reviewer"],
    sourceKind: "form",
    sourceId: "f",
  });
  await submit(
    "changes",
    "form.changes",
    "f",
    2,
    { reason: "Bổ sung" },
    "reviewer",
  );
  await submit("newroute", "route.save", "route", 1, {
    templateId: "advance",
    department: "D",
    steps: ["worker"],
  });
  await submit("resend", "form.submit", "f", 3, { routeId: "route" });
  const read = await submit("read", "message.list", "room", 0, {}, "reviewer");
  assert.equal(read.status, "rejected");
  assert.equal(read.error, "denied");
});
test("snapshot SHA and farm checked before compare-and-swap publish", async () => {
  const { getStorage } = await import("firebase-admin/storage");
  const { hash } = await import("../src/domain.js");
  async function file(tables) {
    const payload = JSON.stringify({
      databases: { "agrico.db": { tables }, "agrico_costs.db": { tables: {} } },
      assets: {},
    });
    const bytes = Buffer.from(
      JSON.stringify({
        format: "agrico-local-sqlite",
        version: 3,
        sha256: hash(payload),
        payload,
      }),
    );
    const sha256 = hash(bytes),
      path = `company-workspace/farm/snapshots/admin/${sha256}`;
    await getStorage().bucket().file(path).save(bytes);
    return {
      path,
      sha256,
      size: bytes.length,
      reason: "Publish reviewed snapshot",
    };
  }
  const bad = await file({
    finance_documents_v2: [{ organization_id: "else" }],
  });
  const cross = await submit("cross", "snapshot.publish", "snapshot", 0, bad);
  assert.equal(cross.status, "rejected");
  assert.equal(cross.error, "crossFarm");
  const a = await file({ example: [] }),
    b = await file({ another: [] });
  const events = await Promise.all([
    event("a", "snapshot.publish", "snapshot", 0, a),
    event("b", "snapshot.publish", "snapshot", 0, b),
  ]);
  await Promise.all(events.map(processCommand));
  assert.deepEqual(
    (await Promise.all(events.map((e) => e.data.ref.get())))
      .map((d) => d.data().status)
      .sort(),
    ["accepted", "rejected"],
  );
  assert.equal(
    (await db.collection("agrico_workspace/farm/snapshots").get()).size,
    1,
  );
});

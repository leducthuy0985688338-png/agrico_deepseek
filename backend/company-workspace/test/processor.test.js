import { before, after, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  doc, getDocFromServer, getDocFromCache, setDoc, serverTimestamp,
  disableNetwork, enableNetwork,
} from "firebase/firestore";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
process.env.GCLOUD_PROJECT = "demo-agrico-workspace";
process.env.GOOGLE_CLOUD_PROJECT = "demo-agrico-workspace";
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8088";
process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-agrico-workspace",
  storageBucket: "demo-agrico-workspace.appspot.com",
});
const { processCommand, processAssistant, readCommandResult, deliverCommandResult } = await import("../src/index.js");
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
async function receive(op, uid = 'worker') {
  const c = (await db.doc('agrico_workspace/farm/users/'+uid+'/commands/'+op).get()).data();
  return readCommandResult('farm', uid, op, {action:c.action,entityId:c.entityId,expectedRevision:c.expectedRevision,payload:c.payload});
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

// Counts SDK calls and returned snapshots, NOT Firebase billable operations.
async function measuredCommand(label, e, phase = "process") {
  let delivered;
  const counters = { label, transactionAttempts: 0, documentGetCalls: 0,
    documentSnapshots: 0, missingDocuments: 0, queryGetCalls: 0,
    queryDocuments: 0, setCalls: 0, updateCalls: 0, deleteCalls: 0,
    committedWrites: 0 };
  const original = db.runTransaction;
  db.runTransaction = function (body, ...options) {
    let attemptWrites = 0;
    return original.call(this, async (tx) => {
      counters.transactionAttempts++;
      attemptWrites = 0;
      const proxy = new Proxy(tx, { get(target, key) {
        if (key === "get") return async (...args) => {
          const result = await target.get(...args);
          if (Array.isArray(result.docs)) {
            counters.queryGetCalls++; counters.queryDocuments += result.size;
          } else {
            counters.documentGetCalls++;
            if (result.exists) counters.documentSnapshots++;
            else counters.missingDocuments++;
          }
          return result;
        };
        if (["set", "update", "delete"].includes(key)) return (...args) => {
          counters[key + "Calls"]++; attemptWrites++;
          return target[key](...args);
        };
        const value = target[key];
        return typeof value === "function" ? value.bind(target) : value;
      }});
      return body(proxy);
    }, ...options).then((result) => {
      counters.committedWrites += attemptWrites;
      return result;
    });
  };
  try {
    if (phase === "process") await processCommand(e);
    else delivered = await receive(e.params.op, e.params.uid);
  }
  finally {
    db.runTransaction = original;
    console.log("SYNC_EMULATOR_MEASURE " + JSON.stringify(counters));
  }
  // This inspection is one Admin SDK document read, outside transaction counts.
  const stored = (await e.data.ref.get()).data();
  if (phase === "process") {
    await measuredCommand(label + "-delivery", e, "delivery");
  } else {
    const {resultDelivery, resultSubjectHash, resultGuards, ...legacyShape} = stored;
    console.log("SYNC_RECEIPT_PAYLOAD " + JSON.stringify({label,
      legacyShapeJsonBytes:Buffer.byteLength(JSON.stringify(legacyShape)),
      guardedStoredJsonBytes:Buffer.byteLength(JSON.stringify(stored)),
      deliveredJsonBytes:Buffer.byteLength(JSON.stringify(delivered))}));
  }
  return stored;
}

test("sync controls measure full unchanged changed and replay on real Firestore", async () => {
  const create = await event("cost-room", "room.create", "cost-room", 0,
    {title:"Nhóm Nguyễn ລາວ", members:["worker"]});
  await measuredCommand("create-room", create);
  await measuredCommand("replay-same-command", create);
  assert.equal((await db.collection("agrico_workspace/farm/records").get()).size, 1);
  const full = await measuredCommand("inbox-full", await event("cost-inbox1", "inbox.list", "inbox", 0, {}, "worker"));
  const same = await measuredCommand("inbox-unchanged", await event("cost-inbox2", "inbox.list", "inbox", 0, {token:full.result.token}, "worker"));
  assert.equal(same.result.unchanged, true);
  const chat = await measuredCommand("messages-full", await event("cost-chat1", "message.list", "cost-room", 0, {}, "worker"));
  const sameChat = await measuredCommand("messages-unchanged", await event("cost-chat2", "message.list", "cost-room", 0, {token:chat.result.token}, "worker"));
  assert.equal(sameChat.result.unchanged, true);
  const message = await event("cost-message", "message.create", "cost-message", 1, {roomId:"cost-room", text:"Nội dung ລາວ"}, "worker");
  await measuredCommand("create-message", message);
  await measuredCommand("retry-message-response-lost", message);
  const changed = await measuredCommand("inbox-changed", await event("cost-inbox3", "inbox.list", "inbox", 0, {token:full.result.token}, "worker"));
  assert.equal(changed.result.unchanged, undefined);
  const changedChat = await measuredCommand("messages-changed", await event("cost-chat3", "message.list", "cost-room", 0, {token:chat.result.token}, "worker"));
  assert.equal(changedChat.result.records.length, 1);
  assert.equal((await db.collection("agrico_workspace/farm/records").where("kind", "==", "message").get()).size, 1);
  // Test-only Admin mutation models removing a participant. No product API exists yet.
  await db.doc("agrico_workspace/farm/records/room~cost-room").update({participants:["admin"], revision:3});
  const denied = await measuredCommand("messages-after-room-removal", await event("cost-chat4", "message.list", "cost-room", 0, {token:changedChat.result.token}, "worker"));
  assert.equal(denied.status, "rejected");
  assert.equal(denied.error, "denied");
  const hidden = await measuredCommand("inbox-after-room-removal", await event("cost-inbox4", "inbox.list", "inbox", 0, {token:changed.result.token}, "worker"));
  assert.equal(hidden.result.records.length, 0);
});

test("offline client queues one command and replay creates no duplicate", async () => {
  const client = env.authenticatedContext("worker").firestore();
  const path = "agrico_workspace/farm/users/worker/commands/offline-create";
  const ref = doc(client, path);
  await disableNetwork(client);
  let acknowledged = false;
  const pending = setDoc(ref, {schemaVersion:1, action:"room.create", entityId:"offline-room",
    expectedRevision:0, payload:{title:"Offline",members:[]}, status:"pending", createdAt:serverTimestamp()})
    .then(() => { acknowledged = true; });
  const cached = await getDocFromCache(ref);
  assert.equal(cached.metadata.hasPendingWrites, true);
  assert.equal(acknowledged, false);
  assert.equal((await db.doc(path).get()).exists, false);
  await enableNetwork(client);
  await pending;
  const e = {params:{farm:"farm",uid:"worker",op:"offline-create"}, data:{ref:db.doc(path),data:()=>({action:"room.create"})}};
  await measuredCommand("offline-command-reconnect", e);
  await measuredCommand("offline-command-replay", e);
  assert.equal((await db.doc("agrico_workspace/farm/records/room~offline-room").get()).data().revision, 1);
  assert.equal((await db.collection("agrico_workspace/farm/command_audit").get()).size, 1);
});

test("accepted private receipt must not remain readable after room removal", async () => {
  await submit("private-room", "room.create", "private-room", 0, {title:"Private",members:["worker"]});
  await submit("private-msg", "message.create", "private-msg", 1, {roomId:"private-room",text:"Private receipt text"});
  await submit("private-read", "message.list", "private-room", 0, {}, "worker");
  const client = env.authenticatedContext("worker").firestore();
  const receipt = doc(client,"agrico_workspace/farm/users/worker/commands/private-read");
  // The positive check now uses the authenticated delivery path. The security
  // assertion below is retained exactly; direct accepted reads are stricter.
  assert.equal((await receive("private-read")).result.records.length, 1);
  await assert.rejects(() => getDocFromServer(receipt), {code:"permission-denied"});
  await db.doc("agrico_workspace/farm/records/room~private-room").update({participants:["admin"],revision:3});
  await assert.rejects(() => getDocFromServer(receipt), {code:"permission-denied"});
  await assert.rejects(() => receive("private-read"), {code:"denied"});
});

test("receipt delivery rejects logout other account and modified replay", async () => {
  await submit("session-room", "room.create", "session-room", 0, {title:"Session",members:["worker"]});
  await submit("session-read", "message.list", "session-room", 0, {}, "worker");
  const c = (await db.doc("agrico_workspace/farm/users/worker/commands/session-read").get()).data();
  const data = {farm:"farm", operation:"session-read", command:{action:c.action,entityId:c.entityId,expectedRevision:0,payload:{}}};
  assert.equal((await deliverCommandResult({auth:{uid:"worker"},data})).status,"accepted");
  await assert.rejects(() => deliverCommandResult({data}), {code:"unauthenticated"});
  await assert.rejects(() => deliverCommandResult({auth:{uid:"reviewer"},data}), {code:"permission-denied"});
  await assert.rejects(() => deliverCommandResult({auth:{uid:"worker"},data:{...data,command:{...data.command,payload:{token:"forged"}}}}), {code:"invalid-argument"});
  await db.doc("agrico_memberships/worker").update({deniedPermissions:["chat.view"]});
  await assert.rejects(() => receive("session-read"), {code:"denied"});
});
test("source revocation invalidates old room inbox and AI result without adminRevision bump", async () => {
  await submit("source-create", "form.create", "source", 0, {templateId:"advance",fields:{amount:"100",currency:"VND",reason:"private"}});
  await submit("source-route", "route.save", "source-route", 0, {templateId:"advance",department:"D",steps:["reviewer"]});
  await submit("source-submit", "form.submit", "source", 1, {routeId:"source-route"});
  await submit("source-room", "room.create", "source-room", 0, {title:"Source",members:["reviewer"],sourceKind:"form",sourceId:"source"});
  await submit("source-read", "message.list", "source-room", 0, {}, "reviewer");
  await submit("source-inbox", "inbox.list", "inbox", 0, {}, "reviewer");
  assert.equal((await receive("source-read","reviewer")).status,"accepted");
  const original = globalThis.fetch;
  process.env.AGRICO_AI_API_KEY = "test-only";
  globalThis.fetch = async () => ({ok:true,json:async()=>({choices:[{message:{content:"Private source summary"}}]})});
  try { await processAssistant(await event("source-ai","ai.ask","source-ai",0,{question:"Summarize",language:"en"},"reviewer")); }
  finally { globalThis.fetch = original; }
  assert.equal((await receive("source-ai","reviewer")).result.answer,"Private source summary");
  // Use the real workflow to replace a reviewer; membership/adminRevision stays unchanged.
  await submit("source-changes","form.changes","source",2,{reason:"Revise"},"reviewer");
  await submit("source-newroute","route.save","source-route",1,{templateId:"advance",department:"D",steps:["worker"]});
  await submit("source-resubmit","form.submit","source",3,{routeId:"source-route"});
  for (const op of ["source-read","source-inbox","source-ai"]) {
    await assert.rejects(() => receive(op,"reviewer"), {code:"denied"});
    await assert.rejects(() => getDocFromServer(doc(env.authenticatedContext("reviewer").firestore(),"agrico_workspace/farm/users/reviewer/commands/"+op)), {code:"permission-denied"});
  }
});
test("stale accepted write returns technical acknowledgement and legacy private reads fail closed", async () => {
  const e = await event("safe-ack","room.create","safe-room",0,{title:"Old private title",members:["worker"]});
  await processCommand(e);
  await db.doc("agrico_workspace/farm/records/room~safe-room").update({participants:["worker"],revision:2});
  const ack = await receive("safe-ack","admin");
  assert.deepEqual(ack,{status:"accepted",result:{},resultUnavailable:true});
  await processCommand(e);
  assert.equal((await db.collection("agrico_workspace/farm/command_audit").get()).size,1);
  const ref = db.doc("agrico_workspace/farm/users/worker/commands/legacy");
  await ref.set({action:"message.list",entityId:"safe-room",expectedRevision:0,payload:{},status:"accepted",result:{records:[{secret:"legacy"}]},resultPolicyRevision:1});
  await assert.rejects(() => receive("legacy"), {code:"denied"});
  await assert.rejects(() => getDocFromServer(doc(env.authenticatedContext("worker").firestore(),ref.path)), {code:"permission-denied"});
});

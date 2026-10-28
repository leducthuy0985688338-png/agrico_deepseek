import { test } from "node:test";
import assert from "node:assert/strict";
import {
  execute,
  active,
  has,
  visible,
  validateFields,
  validateTemplate,
} from "../src/domain.js";
import { templates } from "../src/templates.js";
const now = "2026-10-27T06:00:00.000Z";
const user = (uid, role = "systemAdmin", scopes = ["allFarm"]) => ({
  userId: uid,
  membershipId: uid,
  farmId: "farm",
  active: true,
  roles: [{ role, scopes }],
  offlineUntil: "2026-11-27T00:00:00Z",
  departmentIds: ["D"],
  teamIds: ["T"],
  projectIds: ["P"],
  extraPermissions: [],
  deniedPermissions: [],
  displayName: uid,
});
class Repo {
  constructor() {
    this.data = new Map();
    this.people = new Map(
      ["admin", "worker", "reviewer", "other"].map((id) => [id, user(id)]),
    );
    this.saved = [];
    this.routesData = new Map();
    this.templatesData = new Map();
    this.counter = 0;
    this.used = new Map();
  }
  record(k, id) {
    return this.data.get(`${k}~${id}`) ?? null;
  }
  member(uid) {
    return this.people.get(uid);
  }
  members() {
    return [...this.people.values()];
  }
  admin(uid) {
    return uid === "admin";
  }
  template(id) {
    return this.templatesData.get(id);
  }
  templates() {
    return [...this.templatesData.values()];
  }
  routes() {
    return [...this.routesData.values()];
  }
  route(id) {
    return this.routesData.get(id);
  }
  saveRoute(r) {
    this.routesData.set(r.id, r);
  }
  saveTemplate(t) {
    this.templatesData.set(t.id, t);
  }
  code(prefix) {
    return `${prefix}-202610-${++this.counter}`;
  }
  save(r) {
    this.data.set(`${r.kind}~${r.id}`, structuredClone(r));
    this.saved.push(structuredClone(r));
  }
  inbox(uid) {
    return [...this.data.values()].filter(
      (r) => r.kind !== "message" && r.participants.includes(uid),
    );
  }
  generation() {
    return 1;
  }
  history() {
    return this.saved;
  }
  messages(id) {
    return [...this.data.values()].filter(
      (r) => r.kind === "message" && r.content.roomId === id,
    );
  }
  verifyFile() {
    return true;
  }
  formByCode(code) {
    return [...this.data.values()].find((r) => r.code === code);
  }
  advanceUsed(id) {
    return this.used.get(id) ?? "0";
  }
  reserveAdvance(id, value) {
    this.used.set(id, value);
  }
}
const command = (action, id = "record", revision = 0, payload = {}) => ({
  action,
  entityId: id,
  expectedRevision: revision,
  payload,
  farm: "farm",
  uid: "admin",
});
const run = (r, a, id = "record", rev = 0, p = {}, uid = "admin") =>
  execute(r, { ...command(a, id, rev, p), uid }, r.people.get(uid), now);
async function createTask(r) {
  return (
    await run(r, "task.create", "task", 0, {
      title: "Giao việc",
      details: "Kiểm tra thực tế",
      due: "2026-11-01",
      assignee: "worker",
    })
  ).record;
}
async function form(
  r,
  id = "form",
  templateId = "advance",
  fields = { amount: "1000", currency: "VND", reason: "Công tác" },
) {
  return (await run(r, "form.create", id, 0, { templateId, fields })).record;
}
async function route(r, templateId = "advance") {
  await run(r, "route.save", "route", 0, {
    templateId,
    department: "D",
    steps: ["reviewer"],
  });
}
async function approved(r) {
  await form(r);
  await route(r);
  await run(r, "form.submit", "form", 1, { routeId: "route" });
  return (await run(r, "form.approve", "form", 2, {}, "reviewer")).record;
}
test("all 22 built-in templates have trilingual typed fields and distinct automatic prefixes", () => {
  assert.equal(templates.length, 22);
  assert.equal(new Set(templates.map((t) => t.prefix)).size, 22);
  for (const t of templates) {
    assert.equal(t.names.length, 3);
    for (const f of t.fields) assert.equal(f.label.length, 3);
  }
});
test("active membership checks identity farm and lease", () => {
  const m = user("x");
  assert(active(m, "farm", now));
  for (const changes of [
    { active: false },
    { membershipId: "y" },
    { farmId: "else" },
    { offlineUntil: now },
  ])
    assert(!active({ ...m, ...changes }, "farm", now));
});
test("denies override role grants", () => {
  assert(
    !has({ ...user("x"), deniedPermissions: ["task.assign"] }, "task.assign"),
  );
});
test("creates assigned task with server code snapshot identities and zero progress", async () => {
  const r = new Repo();
  const t = await createTask(r);
  assert.equal(t.state, "assigned");
  assert.equal(t.content.assigneeName, "worker");
  assert.equal(t.content.progress, 0);
  assert(t.code.startsWith("GV-202610"));
});
test("department manager cannot assign outside department", async () => {
  const r = new Repo();
  r.people.set("admin", user("admin", "departmentManager", ["department"]));
  r.people.get("worker").departmentIds = ["else"];
  await assert.rejects(createTask(r), /denied/);
});
test("wrong actor cannot accept and stale revision cannot change a task", async () => {
  const r = new Repo();
  await createTask(r);
  await assert.rejects(run(r, "task.accept", "task", 1, {}, "other"), /denied/);
  await assert.rejects(
    run(r, "task.accept", "task", 0, {}, "worker"),
    /conflict/,
  );
});
test("task accepts starts advances submits and verifier can rework then verify", async () => {
  const r = new Repo();
  await createTask(r);
  await run(r, "task.accept", "task", 1, {}, "worker");
  await run(r, "task.start", "task", 2, {}, "worker");
  await run(r, "task.progress", "task", 3, { progress: 50 }, "worker");
  await assert.rejects(
    run(r, "task.progress", "task", 4, { progress: 30 }, "worker"),
    /invalid/,
  );
  await run(r, "task.submit", "task", 4, {}, "worker");
  await run(r, "task.rework", "task", 5, { reason: "Bổ sung" });
  await run(r, "task.start", "task", 6, {}, "worker");
  await run(r, "task.submit", "task", 7, {}, "worker");
  const t = await run(r, "task.verify", "task", 8);
  assert.equal(t.record.state, "verified");
  assert(r.saved.every((v) => !v.cash && !v.payroll));
});
test("required money dates currency reject invalid input", () => {
  const t = templates[0];
  for (const fields of [
    { amount: "-1", currency: "VND", reason: "x" },
    { amount: "1", currency: "USD", reason: "x" },
    { amount: "1", currency: "VND", reason: "" },
  ])
    assert.throws(() => validateFields(t, fields));
  assert.throws(() =>
    validateFields(
      templates.find((t) => t.id === "sickLeave"),
      { start: "2026-02-30", end: "2026-03-01", reason: "x" },
    ),
  );
});
test("forms keep exact template snapshot across later custom edits", async () => {
  const r = new Repo();
  const t = {
    id: "custom_test",
    prefix: "ZZ",
    names: ["Mẫu", "Form", "ແບບ"],
    permission: "office.edit",
    fields: [
      {
        key: "memo",
        label: ["Nội dung", "Details", "ເນື້ອໃນ"],
        type: "text",
        required: true,
      },
    ],
  };
  await run(r, "template.save", t.id, 0, t);
  await form(r, "f", t.id, { memo: "Nguyên bản" });
  await run(r, "template.save", t.id, 1, {
    ...t,
    names: ["Mới", "New", "ໃໝ່"],
  });
  assert.equal(r.record("form", "f").content.template.version, 1);
  assert.equal(r.record("form", "f").content.template.names[0], "Mẫu");
});
test("custom templates forbid built-in replacement duplicate fields and executable schema", () => {
  for (const changes of [
    { id: "advance" },
    {
      fields: [
        { key: "x", label: ["a", "b", "c"], type: "formula", required: true },
      ],
    },
  ])
    assert.throws(() =>
      validateTemplate({
        id: "custom_x",
        prefix: "XX",
        names: ["a", "b", "c"],
        permission: "office.edit",
        fields: [
          { key: "x", label: ["a", "b", "c"], type: "text", required: true },
        ],
        ...changes,
      }),
    );
});
test("only root authority admin may configure routes", async () => {
  const r = new Repo();
  await assert.rejects(
    run(
      r,
      "route.save",
      "route",
      0,
      { templateId: "advance", department: "D", steps: ["reviewer"] },
      "worker",
    ),
    /denied/,
  );
});
test("route denies reviewers without domain permission and duplicates", async () => {
  const r = new Repo();
  r.people.get("reviewer").deniedPermissions = ["finance.approve"];
  await assert.rejects(route(r), /invalidRecipient/);
  await assert.rejects(
    run(r, "route.save", "route", 0, {
      templateId: "advance",
      department: "D",
      steps: ["other", "other"],
    }),
    /invalidRoute/,
  );
});
test("sender cannot select a route that includes themselves", async () => {
  const r = new Repo();
  await form(r);
  await run(r, "route.save", "route", 0, {
    templateId: "advance",
    department: "D",
    steps: ["admin"],
  });
  await assert.rejects(
    run(r, "form.submit", "form", 1, { routeId: "route" }),
    /invalidRecipient/,
  );
});
test("two-level approval requires current reviewer and makes no cash postings", async () => {
  const r = new Repo();
  await form(r);
  await run(r, "route.save", "route", 0, {
    templateId: "advance",
    department: "D",
    steps: ["reviewer", "other"],
  });
  await run(r, "form.submit", "form", 1, { routeId: "route" });
  await assert.rejects(
    run(r, "form.approve", "form", 2, {}, "other"),
    /denied/,
  );
  await run(r, "form.approve", "form", 2, {}, "reviewer");
  const a = await run(r, "form.approve", "form", 3, {}, "other");
  assert.equal(a.record.state, "approved");
  assert.equal(r.saved.length, 4);
});
test("changes retain evidence and allow sender edit and resubmit", async () => {
  const r = new Repo();
  await form(r);
  await route(r);
  await run(r, "form.submit", "form", 1, { routeId: "route" });
  await run(r, "form.changes", "form", 2, { reason: "Bổ sung" }, "reviewer");
  await run(r, "form.edit", "form", 3, {
    fields: { amount: "200", currency: "LAK", reason: "Sửa" },
  });
  await run(r, "form.submit", "form", 4, { routeId: "route" });
  assert.equal(r.record("form", "form").state, "submitted");
});
test("current scope revocation hides form and history", async () => {
  const r = new Repo();
  await approved(r);
  r.people.get("reviewer").deniedPermissions = ["finance.approve"];
  assert(!visible(r.people.get("reviewer"), r.record("form", "form")));
  await assert.rejects(
    run(r, "record.history", "form", 0, { kind: "form" }, "reviewer"),
    /denied/,
  );
});
test("advance settlement rejects cross currency and overallocated requests", async () => {
  const r = new Repo();
  const source = await approved(r);
  await run(r, "route.save", "settle_route", 0, {
    templateId: "advanceSettlement",
    department: "D",
    steps: ["reviewer"],
  });
  const create = async (id, received, currency = "VND") => {
    await form(r, id, "advanceSettlement", {
      reference: source.code,
      received,
      spent: "20",
      currency,
      reason: "Đối chiếu",
    });
    await run(r, "form.submit", id, 1, { routeId: "settle_route" });
  };
  await create("s", "600");
  await run(r, "form.approve", "s", 2, {}, "reviewer");
  await create("t", "600");
  await assert.rejects(
    run(r, "form.approve", "t", 2, {}, "reviewer"),
    /advanceAlreadySettled/,
  );
  await create("u", "1", "LAK");
  await assert.rejects(
    run(r, "form.approve", "u", 2, {}, "reviewer"),
    /invalidAdvance/,
  );
  assert.equal(r.used.get(source.id), "6000000");
});
test("chat participants cannot include inactive users or widen source access", async () => {
  const r = new Repo();
  await createTask(r);
  await assert.rejects(
    run(r, "room.create", "room", 0, {
      title: "Trao đổi",
      members: ["other"],
      sourceId: "task",
      sourceKind: "task",
    }),
    /denied/,
  );
  r.people.get("worker").active = false;
  await assert.rejects(
    run(r, "room.create", "room", 0, { title: "Chat", members: ["worker"] }),
    /invalidRecipient/,
  );
});
test("chat appends using current server sequence even when client room revision is older", async () => {
  const r = new Repo();
  await run(r, "room.create", "room", 0, {
    title: "Nhóm",
    members: ["worker"],
  });
  const msg = await run(r, "message.create", "m1", 1, {
    roomId: "room",
    text: "Xin chào",
  });
  assert.equal(msg.record.content.sequence, 2);
  const second = await run(
    r,
    "message.create",
    "m2",
    1,
    { roomId: "room", text: "Thứ hai" },
    "worker",
  );
  assert.equal(second.record.content.sequence, 3);
  assert.equal(r.record("room", "room").revision, 3);
});
test("unrelated users cannot read rooms or attachments", async () => {
  const r = new Repo();
  await run(r, "room.create", "room", 0, {
    title: "Nhóm",
    members: ["worker"],
  });
  await assert.rejects(
    run(r, "message.list", "room", 0, {}, "other"),
    /denied/,
  );
  await assert.rejects(
    run(
      r,
      "attachment.authorize",
      "room",
      0,
      { kind: "room", path: "some" },
      "worker",
    ),
    /denied/,
  );
});
test("snapshot publish requires full sensitive authority and optimistic revision", async () => {
  const r = new Repo();
  r.snapshot = () => ({ revision: 3, sha256: "old" });
  r.verifySnapshot = () => {};
  let saved;
  r.saveSnapshot = (head) => (saved = head);
  await assert.rejects(
    run(r, "snapshot.publish", "snapshot", 2, {
      path: "path",
      sha256: "new",
      size: 1,
      reason: "Conflict chosen",
    }),
    /conflict/,
  );
  r.people.get("admin").deniedPermissions = ["payroll.view"];
  await assert.rejects(run(r, "snapshot.head", "snapshot"), /denied/);
  r.people.get("admin").deniedPermissions = [];
  await run(r, "snapshot.publish", "snapshot", 3, {
    path: "path",
    sha256: "new",
    size: 1,
    reason: "Conflict chosen",
  });
  assert.equal(saved.revision, 4);
});

 test("unchanged inbox revalidates records and membership changes invalidate token", async () => {
  const repo = new Repo();
  let reads = 0;
  const inbox = repo.inbox.bind(repo);
  repo.inbox = (...args) => { reads++; return inbox(...args); };
  const first = await run(repo, "inbox.list", "inbox", 0, {});
  const next = await run(repo, "inbox.list", "inbox", 0, {token: first.token});
  assert.equal(next.unchanged, true);
  assert.equal(reads, 2);
  assert.equal(next.records, undefined);
  repo.people.get("admin").departmentIds = ["changed"];
  const changed = await run(repo, "inbox.list", "inbox", 0, {token: first.token});
  assert.notEqual(changed.token, first.token);
  assert.equal(reads, 3);
 });

test("measure unchanged inbox bytes with authoritative visibility checks", async () => {
  const repo = new Repo();
  for (let i = 0; i < 100; i++) repo.data.set('room~'+i, {
    id: 'room'+i, kind: 'room', farmId: 'farm', participants: ['admin'],
    revision: 1, content: {title: 'Unicode Nguyễn ລາວ '.repeat(25)}
  });
  let reads = 0;
  const original = repo.inbox.bind(repo);
  repo.inbox = (...args) => { reads++; return original(...args); };
  const first = await run(repo, 'inbox.list', 'inbox');
  const next = await run(repo, 'inbox.list', 'inbox', 0, {token: first.token});
  const fullBytes = Buffer.byteLength(JSON.stringify(first));
  const unchangedBytes = Buffer.byteLength(JSON.stringify(next));
  console.log(JSON.stringify({fullBytes, unchangedBytes, recordQueriesForTwoPolls: reads}));
  assert.equal(reads, 2);
  assert.ok(unchangedBytes < fullBytes / 100);
});
test("message token skips messages but still enforces room access", async () => {
  const repo = new Repo();
  repo.data.set('room~room1', {id:'room1', kind:'room', farmId:'farm', participants:['admin'], revision:1, content:{title:'Room'}});
  let reads = 0;
  repo.messages = () => { reads++; return []; };
  const first = await run(repo, 'message.list', 'room1');
  assert.equal((await run(repo, 'message.list', 'room1', 0, {token:first.token})).unchanged, true);
  assert.equal(reads, 1);
  repo.data.get('room~room1').revision++;
  assert.equal((await run(repo, 'message.list', 'room1', 0, {token:first.token})).unchanged, undefined);
  assert.equal(reads, 2);
  repo.data.get('room~room1').participants = ['other'];
  await assert.rejects(() => run(repo, 'message.list', 'room1', 0, {token:first.token}));
});

test("inbox token detects visibility changes even without a notice update", async () => {
  const repo = new Repo();
  repo.data.set('room~room1', {id:'room1', kind:'room', farmId:'farm', participants:['admin'], revision:1, content:{title:'Room'}});
  const first = await run(repo, 'inbox.list', 'inbox');
  repo.data.get('room~room1').participants = ['other'];
  const next = await run(repo, 'inbox.list', 'inbox', 0, {token:first.token});
  assert.notEqual(next.token, first.token);
  assert.deepEqual(next.records, []);
});

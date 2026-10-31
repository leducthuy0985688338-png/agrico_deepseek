import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { templates, approvalPermissions } from "./templates.js";
const policy = JSON.parse(
  readFileSync(new URL("./role-policy.json", import.meta.url)),
);
export class Rejected extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}
export const fail = (code) => {
  throw new Rejected(code);
};
export const clean = (v, max = 500) =>
  typeof v === "string" && v.trim() && v.length <= max
    ? v.trim()
    : fail("invalid");
export const ident = (v) =>
  typeof v === "string" && /^[A-Za-z0-9_-]{1,120}$/.test(v)
    ? v
    : fail("invalid");
export const hash = (v) => createHash("sha256").update(v).digest("hex");
export function active(m, farm, now) {
  return (
    !!m &&
    m.active === true &&
    m.farmId === farm &&
    m.userId === m.membershipId &&
    Date.parse(m.offlineUntil) > Date.parse(now)
  );
}
export function has(m, p) {
  return (
    !m.deniedPermissions?.includes(p) &&
    (m.extraPermissions?.includes(p) ||
      m.roles?.some((r) => policy[r.role]?.includes(p)))
  );
}
function scopes(m, p) {
  return new Set([
    ...(m.extraPermissions?.includes(p) ? (m.extraPermissionScopes ?? []) : []),
    ...(m.roles ?? [])
      .filter((r) => policy[r.role]?.includes(p))
      .flatMap((r) => r.scopes ?? []),
  ]);
}
export function manages(m, p, target) {
  if (!has(m, p)) return false;
  const s = scopes(m, p);
  return (
    s.has("allFarm") ||
    [
      ["department", "departmentIds"],
      ["team", "teamIds"],
      ["project", "projectIds"],
    ].some(
      ([scope, key]) =>
        s.has(scope) &&
        (m[key] ?? []).some((v) => (target[key] ?? []).includes(v)),
    )
  );
}
// Read-only scope introspection for authority endpoints. Existing Workspace
// authorization continues to use the same scope calculation unchanged.
export function permissionScopes(m,p){return has(m,p)?scopes(m,p):new Set();}
const access = (m) =>
  Object.fromEntries(
    ["departmentIds", "teamIds", "projectIds"].map((k) => [k, m[k] ?? []]),
  );
const requirePermission = (m, p) => {
  if (!has(m, p)) fail("denied");
};
const money = (v) =>
  typeof v === "string" && /^(0|[1-9]\d{0,14})(\.\d{1,4})?$/.test(v)
    ? BigInt(v.split(".")[0]) * 10000n +
      BigInt((v.split(".")[1] ?? "").padEnd(4, "0"))
    : fail("invalidAmount");
export function validateTemplate(t) {
  ident(t.id);
  if (
    !t.id.startsWith("custom_") ||
    !/^[A-Z]{2,6}$/.test(t.prefix) ||
    ["GV", "CHAT"].includes(t.prefix)
  )
    fail("invalidTemplate");
  if (
    !Array.isArray(t.names) ||
    t.names.length !== 3 ||
    !approvalPermissions.includes(t.permission)
  )
    fail("invalidTemplate");
  t.names.forEach((n) => clean(n, 100));
  if (!Array.isArray(t.fields) || t.fields.length < 1 || t.fields.length > 20)
    fail("invalidTemplate");
  const keys = new Set();
  for (const f of t.fields) {
    ident(f.key);
    if (
      ["__proto__", "constructor", "prototype"].includes(f.key) ||
      keys.has(f.key) ||
      !["text", "multiline", "date", "money", "currency", "number"].includes(
        f.type,
      ) ||
      typeof f.required !== "boolean" ||
      f.label?.length !== 3
    )
      fail("invalidTemplate");
    f.label.forEach((l) => clean(l, 100));
    keys.add(f.key);
  }
  return {
    id: t.id,
    prefix: t.prefix,
    names: t.names,
    permission: t.permission,
    fields: t.fields,
  };
}
export function validateFields(t, fields) {
  if (
    !fields ||
    typeof fields !== "object" ||
    Array.isArray(fields) ||
    Object.keys(fields).some((k) => !t.fields.some((f) => f.key === k))
  )
    fail("invalidFields");
  const result = {};
  for (const f of t.fields) {
    const v = fields[f.key] ?? "";
    if (typeof v !== "string" || v.length > 4000 || (f.required && !v.trim()))
      fail("invalidFields");
    if (v) {
      if (f.type === "money") {
        const n = money(v);
        if (f.key === "amount" && n <= 0n) fail("invalidAmount");
      }
      if (f.type === "currency" && !["VND", "LAK"].includes(v))
        fail("invalidCurrency");
      if (
        f.type === "number" &&
        (!/^\d{1,8}(\.\d{1,4})?$/.test(v) || Number(v) <= 0)
      )
        fail("invalidFields");
      if (
        f.type === "date" &&
        (!/^\d{4}-\d{2}-\d{2}$/.test(v) ||
          !Number.isFinite(Date.parse(v)) ||
          new Date(v).toISOString().slice(0, 10) !== v)
      )
        fail("invalidDate");
    }
    result[f.key] = v.trim();
  }
  if (result.start && result.end && result.start > result.end)
    fail("invalidDate");
  return result;
}
export function visible(m, r) {
  if (
    !r ||
    r.farmId !== m.farmId ||
    !r.participants.includes(m.userId) ||
    !has(m, "chat.view")
  )
    return false;
  if (r.kind === "task")
    return (
      manages(m, "task.view", r.access) ||
      (has(m, "task.view") &&
        (r.creator === m.userId || r.content.assignee === m.userId) &&
        [...scopes(m, "task.view")].some((s) =>
          ["own", "assignedTasks"].includes(s),
        ))
    );
  if (r.kind === "form" && r.creator !== m.userId)
    return manages(m, r.content.template.permission, r.access);
  if (r.kind === "room" && r.content.source) {
    return visible(m, r.content.source);
  }
  return true;
}
async function read(repo, m, kind, id) {
  if (!["task", "form", "room", "message"].includes(kind)) fail("invalid");
  const r = await repo.record(kind, ident(id));
  if (!visible(m, r)) fail("denied");
  return r;
}
export async function execute(repo, command, m, now) {
  if (!active(m, command.farm, now) || m.userId !== command.uid) fail("denied");
  requirePermission(m, "cloud.sync");
  const {
    action,
    payload: p = {},
    entityId: id,
    expectedRevision: rev,
  } = command;
  ident(id);
  if (!Number.isInteger(rev) || rev < 0) fail("invalid");
  const member = async (uid) => {
    const u = await repo.member(ident(uid));
    if (!active(u, m.farmId, now)) fail("invalidRecipient");
    return u;
  };
  const admin = async () => {
    requirePermission(m, "account.manage");
    requirePermission(m, "role.manage");
    if (!(await repo.admin(m.userId))) fail("denied");
  };
  const getTemplate = async (key) =>
    templates.find((t) => t.id === key) ??
    (await repo.template(ident(key))) ??
    fail("invalidTemplate");
  const attachments = async (files) => {
    if (!Array.isArray(files ?? []) || (files ?? []).length > 5)
      fail("invalidAttachment");
    for (const file of files ?? []) {
      if (
        typeof file.path !== "string" ||
        !file.path.startsWith(
          `company-workspace/${m.farmId}/files/${m.userId}/`,
        ) ||
        !/[a-f0-9]{64}$/.test(file.path) ||
        typeof file.name !== "string" ||
        file.name.length > 160
      )
        fail("invalidAttachment");
      await repo.verifyFile(file);
    }
    return files ?? [];
  };
  if (action === "directory.list") {
    requirePermission(m, "chat.view");
    return {
      members: (await repo.members())
        .filter((u) => active(u, m.farmId, now))
        .map((u) => ({
          uid: u.userId,
          name: u.displayName ?? u.userId,
          ...access(u),
        })),
    };
  }
  if (action === "template.list") {
    requirePermission(m, "chat.view");
    return { templates: [...templates, ...(await repo.templates())] };
  }
  if (action === "template.save") {
    await admin();
    const t = validateTemplate(p);
    const old = await repo.template(t.id);
    if (rev !== (old?.version ?? 0)) fail("conflict");
    if (
      (await repo.templates()).some(
        (v) => v.id !== t.id && v.prefix === t.prefix,
      ) ||
      templates.some((v) => v.prefix === t.prefix)
    )
      fail("duplicate");
    await repo.saveTemplate({
      ...t,
      version: rev + 1,
      actor: m.userId,
      at: now,
    });
    return { version: rev + 1 };
  }
  if (action === "route.list") {
    requirePermission(m, "chat.view");
    return { routes: await repo.routes() };
  }
  if (action === "route.save") {
    await admin();
    const t = await getTemplate(p.templateId);
    const department = clean(p.department, 120);
    if (
      !Array.isArray(p.steps) ||
      p.steps.length < 1 ||
      p.steps.length > 4 ||
      new Set(p.steps).size !== p.steps.length
    )
      fail("invalidRoute");
    const steps = [];
    for (const uid of p.steps) {
      const u = await member(uid);
      if (
        !has(u, t.permission) ||
        (!scopes(u, t.permission).has("allFarm") &&
          !(u.departmentIds ?? []).includes(department))
      )
        fail("invalidRecipient");
      steps.push({ uid, name: u.displayName ?? uid });
    }
    const old = await repo.route(id);
    if (rev !== (old?.revision ?? 0)) fail("conflict");
    await repo.saveRoute({
      id,
      templateId: t.id,
      department,
      steps,
      revision: rev + 1,
      actor: m.userId,
      at: now,
    });
    return { revision: rev + 1 };
  }
  if (action === "inbox.list") {
    requirePermission(m, "chat.view");
    const generation = await repo.generation(m.userId);
    const records = [];
    let bytes = 0;
    for (const r of (await repo.inbox(m.userId)).filter((r) => visible(m, r))) {
      const size = Buffer.byteLength(JSON.stringify(r));
      if (bytes + size > 600000) break;
      records.push(r);
      bytes += size;
    }
    // A notice alone cannot prove visibility: a linked source can revoke
    // access without changing this user's room notice. Revalidate originals.
    const token = createHash("sha256").update(JSON.stringify([m, generation, records])).digest("hex");
    if (p.token === token) return { unchanged: true, token, generation };
    return { records, generation, token };
  }
  if (action === "record.history") {
    const r = await read(repo, m, p.kind, id);
    return { events: await repo.history(r.kind, r.id) };
  }
  if (action === "message.list") {
    const r = await read(repo, m, "room", id);
    const token = createHash("sha256").update(JSON.stringify([m, r])).digest("hex");
    if (p.token === token) return { unchanged: true, token };
    return { records: await repo.messages(r.id), room: r, token };
  }
  if (action === "attachment.authorize") {
    const r = await read(repo, m, p.kind, id);
    if (r.kind === "message") await read(repo, m, "room", r.content.roomId);
    if (!(r.content.files ?? []).some((f) => f.path === p.path)) fail("denied");
    await repo.fileGrant(m, p.path, now);
    return { path: p.path };
  }
  if (action.startsWith("snapshot.")) {
    if (
      !(await repo.admin(m.userId)) ||
      ![
        "cloud.restore",
        "local_backup.export",
        "employee.sensitive.view",
        "payroll.view",
        "finance.view",
      ].every((v) => has(m, v) && scopes(m, v).has("allFarm"))
    )
      fail("denied");
    const head = await repo.snapshot();
    if (action === "snapshot.head") return { head };
    if (action !== "snapshot.publish") fail("invalidAction");
    if (rev !== (head?.revision ?? 0)) fail("conflict");
    await repo.verifySnapshot(p, m);
    const next = {
      path: p.path,
      sha256: p.sha256,
      size: p.size,
      revision: rev + 1,
      actor: m.userId,
      at: now,
      reason: clean(p.reason, 500),
    };
    await repo.saveSnapshot(next);
    return { head: next };
  }
  let r, old;
  if (["task.create", "form.create", "room.create"].includes(action)) {
    if (rev !== 0 || (await repo.record(action.split(".")[0], id)))
      fail("conflict");
    r = {
      id,
      kind: action.split(".")[0],
      farmId: m.farmId,
      creator: m.userId,
      creatorName: m.displayName ?? m.userId,
      participants: [m.userId],
      access: access(m),
      content: {},
      state: "draft",
      revision: 0,
      createdAt: now,
    };
  } else if (action === "message.create") {
    requirePermission(m, "chat.send");
    const room = await read(repo, m, "room", ident(p.roomId));
    if (await repo.record("message", id)) fail("conflict");
    // Immutable messages append under the transaction lock; an older client
    // room version must not reject a legitimate simultaneous message.
    const content = typeof p.text === "string" ? p.text.trim() : "";
    if (content.length > 4000 || (!content && !p.files?.length))
      fail("invalid");
    const files = await attachments(p.files);
    const message = {
      id,
      kind: "message",
      farmId: m.farmId,
      creator: m.userId,
      creatorName: m.displayName ?? m.userId,
      participants: room.participants,
      access: room.access,
      state: "sent",
      revision: 1,
      createdAt: now,
      updatedAt: now,
      content: {
        roomId: room.id,
        text: content,
        files,
        sequence: room.revision + 1,
      },
    };
    await repo.save(
      { ...room, revision: room.revision + 1, updatedAt: now },
      m,
      action,
      now,
    );
    await repo.save(message, m, action, now);
    return { record: message, room: { ...room, revision: room.revision + 1 } };
  } else {
    const kind = action.split(".")[0];
    if (!["task", "form"].includes(kind)) fail("invalidAction");
    old = await read(repo, m, kind, id);
    if (old.revision !== rev) fail("conflict");
    r = structuredClone(old);
  }
  if (r.kind === "task") {
    if (action === "task.create") {
      requirePermission(m, "task.create");
      requirePermission(m, "task.assign");
      const u = await member(p.assignee);
      if (
        !manages(m, "task.assign", u) ||
        !has(u, "task.view") ||
        !has(u, "task.complete")
      )
        fail("denied");
      const due = clean(p.due, 10);
      if (
        !/^\d{4}-\d{2}-\d{2}$/.test(due) ||
        !Number.isFinite(Date.parse(due)) ||
        new Date(due).toISOString().slice(0, 10) !== due
      )
        fail("invalidDate");
      r.content = {
        title: clean(p.title, 200),
        details: clean(p.details, 4000),
        assignee: u.userId,
        assigneeName: u.displayName ?? u.userId,
        due,
        progress: 0,
      };
      r.access = access(u);
      r.participants = [...new Set([m.userId, u.userId])];
      r.state = "assigned";
      r.code = await repo.code("GV", now);
    } else {
      const own = m.userId === r.content.assignee;
      const verifier =
        m.userId === r.creator && manages(m, "task.verify", r.access);
      if (
        ["task.accept", "task.start", "task.progress", "task.submit"].includes(
          action,
        )
      ) {
        requirePermission(m, "task.complete");
        if (!own) fail("denied");
        if (action === "task.accept" && r.state === "assigned")
          r.state = "accepted";
        else if (
          action === "task.start" &&
          ["accepted", "rework"].includes(r.state)
        )
          r.state = "inProgress";
        else if (action === "task.progress" && r.state === "inProgress") {
          if (
            !Number.isInteger(p.progress) ||
            p.progress < r.content.progress ||
            p.progress > 100
          )
            fail("invalid");
          r.content.progress = p.progress;
        } else if (action === "task.submit" && r.state === "inProgress") {
          r.state = "submitted";
          r.content.progress = 100;
        } else fail("invalidState");
      } else if (action === "task.verify" || action === "task.rework") {
        if (!verifier || r.state !== "submitted") fail("denied");
        r.state = action === "task.verify" ? "verified" : "rework";
        if (r.state === "rework") {
          r.content.progress = 0;
          clean(p.reason, 500);
        }
      } else if (action === "task.cancel") {
        if (
          m.userId !== r.creator ||
          !manages(m, "task.assign", r.access) ||
          ["verified", "cancelled"].includes(r.state)
        )
          fail("denied");
        clean(p.reason, 500);
        r.state = "cancelled";
      } else fail("invalidAction");
    }
  } else if (r.kind === "form") {
    const owner = r.creator === m.userId;
    if (action === "form.create" || action === "form.edit") {
      requirePermission(m, "office.request");
      if (!owner || !["draft", "needsChanges"].includes(r.state))
        fail("denied");
      const t =
        action === "form.create"
          ? await getTemplate(p.templateId)
          : r.content.template;
      r.content = {
        ...r.content,
        template: t,
        fields: validateFields(t, p.fields),
        files: await attachments(p.files),
      };
      if (!r.code) r.code = await repo.code(t.prefix, now);
    } else if (action === "form.submit") {
      requirePermission(m, "office.request");
      if (!owner || !["draft", "needsChanges"].includes(r.state))
        fail("invalidState");
      const route = await repo.route(ident(p.routeId));
      if (
        !route ||
        route.templateId !== r.content.template.id ||
        !(m.departmentIds ?? []).includes(route.department)
      )
        fail("invalidRoute");
      for (const step of route.steps) {
        const u = await member(step.uid);
        if (
          u.userId === m.userId ||
          !manages(u, r.content.template.permission, m)
        )
          fail("invalidRecipient");
      }
      r.content.route = route;
      r.content.step = 0;
      r.participants = [m.userId, ...route.steps.map((s) => s.uid)];
      r.state = "submitted";
      r.access = access(m);
    } else if (action === "form.withdraw") {
      requirePermission(m, "office.request");
      if (
        !owner ||
        !["draft", "needsChanges", "submitted", "received"].includes(r.state)
      )
        fail("denied");
      clean(p.reason, 500);
      r.state = "withdrawn";
    } else {
      if (owner || !manages(m, r.content.template.permission, r.access))
        fail("denied");
      const steps = r.content.route?.steps ?? [];
      const current = steps[r.content.step];
      if (action === "form.complete") {
        if (r.state !== "approved" || !steps.some((s) => s.uid === m.userId))
          fail("invalidState");
        r.state = "completed";
      } else {
        if (
          current?.uid !== m.userId ||
          !["submitted", "received"].includes(r.state)
        )
          fail("denied");
        if (action === "form.receive") {
          r.state = "received";
        } else if (action === "form.approve") {
          r.content.step++;
          if (r.content.step === steps.length) {
            if (r.content.template.id === "advanceSettlement") {
              const f = r.content.fields;
              const source = await repo.formByCode(f.reference);
              if (
                !source ||
                source.creator !== r.creator ||
                source.content.template.id !== "advance" ||
                !["approved", "completed"].includes(source.state) ||
                source.content.fields.currency !== f.currency
              )
                fail("invalidAdvance");
              const received = money(f.received);
              if (received <= 0n) fail("invalidAmount");
              const used = BigInt(await repo.advanceUsed(source.id));
              if (used + received > money(source.content.fields.amount))
                fail("advanceAlreadySettled");
              await repo.reserveAdvance(
                source.id,
                (used + received).toString(),
              );
            }
            r.state = "approved";
          } else r.state = "submitted";
        } else if (action === "form.changes" || action === "form.reject") {
          clean(p.reason, 500);
          r.state = action === "form.changes" ? "needsChanges" : "rejected";
        } else fail("invalidAction");
      }
    }
  } else if (r.kind === "room") {
    requirePermission(m, "chat.send");
    const title = clean(p.title, 120);
    if (!Array.isArray(p.members) || p.members.length > 19) fail("invalid");
    let source = null;
    if (p.sourceId) {
      if (!["task", "form"].includes(p.sourceKind)) fail("invalid");
      source = await read(repo, m, p.sourceKind, p.sourceId);
    }
    const participants = [...new Set([m.userId, ...p.members.map(ident)])];
    for (const uid of participants) {
      const u = await member(uid);
      if (
        !has(u, "chat.view") ||
        (source && !source.participants.includes(uid))
      )
        fail("denied");
    }
    r.participants = participants;
    r.content = { title, source };
    r.state = "open";
  }
  r.revision++;
  r.updatedAt = now;
  r.lastEvent = {
    action,
    actor: m.userId,
    name: m.displayName ?? m.userId,
    at: now,
    reason: typeof p.reason === "string" ? p.reason.slice(0, 500) : "",
  };
  await repo.save(r, m, action, now);
  return { record: r };
}

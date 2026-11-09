import { HttpsError } from "firebase-functions/v2/https";
import { hash, ident, active, has, fail, Rejected } from "./domain.js";

export function fingerprint(value) {
  const sort = v => Array.isArray(v) ? v.map(sort) : v && typeof v === "object"
    ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sort(v[k])])) : v;
  return hash(JSON.stringify(sort(JSON.parse(JSON.stringify(value)))));
}
export const commandBody = c => Object.fromEntries(
  ["action", "entityId", "expectedRevision", "payload"].map(k => [k, c[k]]),
);

// Track authoritative data, not projections/counters. Guards contain hashes,
// never additional copies of private document bodies. Own membership is checked
// separately, including every field rather than only adminRevision.
export function trackReceiptReads(transaction, farm, uid) {
  const guards = new Map(), values = new Map();
  const relevant = path => path !== `agrico_memberships/${uid}` && (
    /^agrico_(memberships|access_admins)\/[^/]+$/.test(path) ||
    path.startsWith(`agrico_workspace/${farm}/`) &&
      /\/(records|templates|routes|control)\/[^/]+$/.test(path));
  const capture = (ref, value) => {
    if (!relevant(ref.path)) return;
    values.set(ref.path, value);
    guards.set(ref.path, {path:ref.path, hash:fingerprint(value)});
  };
  const tx = new Proxy(transaction, {get(target, key) {
    if (key === "get") return async (...args) => {
      const result = await target.get(...args);
      if (Array.isArray(result.docs)) {
        for (const doc of result.docs) capture(doc.ref, doc.data());
      } else capture(result.ref, result.exists ? result.data() : null);
      return result;
    };
    if (key === "set") return (ref, value, ...options) => {
      capture(ref, value);
      return target.set(ref, value, ...options);
    };
    if (key === "update") return (ref, value, ...options) => {
      if (relevant(ref.path)) capture(ref, {...values.get(ref.path), ...value});
      return target.update(ref, value, ...options);
    };
    const value = target[key];
    return typeof value === "function" ? value.bind(target) : value;
  }});
  return {tx, guards};
}
export async function guardsMatch(tx, db, guards) {
  if (!Array.isArray(guards)) return false; // Fail closed for legacy receipts.
  for (const guard of guards) {
    const doc = await tx.get(db.doc(guard.path));
    if (fingerprint(doc.exists ? doc.data() : null) !== guard.hash) return false;
  }
  return true;
}
const safeAck = action => /^(task|form)\./.test(action) ||
  ["room.create", "message.create"].includes(action);

export async function readReceipt(db, Repository, farm, uid, op, expected) {
  ident(farm); ident(uid); ident(op);
  return db.runTransaction(async tx => {
    const repo = new Repository(tx, farm), m = await repo.member(uid);
    if (!active(m, farm, new Date().toISOString()) ||
        !has(m, "cloud.sync") || !has(m, "chat.view")) fail("denied");
    const c = (await tx.get(db.doc(`agrico_workspace/${farm}/users/${uid}/commands/${op}`))).data();
    if (!c) fail("denied");
    if (!expected || fingerprint(commandBody(c)) !== fingerprint(commandBody(expected))) fail("conflict");
    const technical = {status:c.status};
    if (c.status === "rejected") return {...technical, error:c.error};
    if (c.status !== "accepted") return technical;
    const current = c.resultDelivery === 2 && c.resultSubjectHash === fingerprint(m) &&
      await guardsMatch(tx, db, c.resultGuards);
    if (!active(m, farm, new Date().toISOString())) fail("denied");
    if (!current) {
      // A committed outbox write stays committed. Never replay business logic
      // or return stale records just to acknowledge an uncertain operation.
      if (safeAck(c.action)) return {...technical, result:{}, resultUnavailable:true};
      fail("denied");
    }
    return {...technical, result:c.result, ...(c.inboxGeneration == null ? {} :
      {inboxGeneration:c.inboxGeneration})};
  });
}
export function createResultDelivery(db, Repository) {
  return async request => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Session required");
    try {
      return await readReceipt(db, Repository, request.data?.farm, request.auth.uid,
        request.data?.operation, request.data?.command);
    } catch (e) {
      if (e instanceof Rejected) throw new HttpsError(
        e.code === "conflict" ? "invalid-argument" : "permission-denied", e.code);
      throw e;
    }
  };
}

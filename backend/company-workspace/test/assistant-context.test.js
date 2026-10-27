import { test } from "node:test";
import assert from "node:assert/strict";
import { summarizeCash } from "../src/assistant_context.js";
test("snapshot totals preserve exact decimals separate VND LAK and period/farm", () => {
  const base = {
    organization_id: "farm",
    occurred_at: "2026-10-01",
    currency: "VND",
    amount_scale: 2,
  };
  const totals = summarizeCash(
    [
      { ...base, kind: "THU", amount_minor: 10 },
      { ...base, kind: "CHI", amount_minor: 30 },
      { ...base, kind: "THU", amount_minor: 999, organization_id: "else" },
      { ...base, kind: "THU", amount_minor: 999, occurred_at: "2026-11-01" },
      { ...base, kind: "THU", amount_minor: 12345, currency: "LAK" },
    ],
    "farm",
    "2026-10",
  );
  assert.deepEqual(totals, {
    VND: { receipts: "0.1", payments: "0.3", net: "-0.2" },
    LAK: { receipts: "123.45", payments: "0", net: "123.45" },
  });
});
test("invalid scales and amounts cannot silently round financial context", () => {
  for (const amount of [
    { amount_scale: 9, amount_minor: 1 },
    { amount_scale: 0, amount_minor: 9007199254740992 },
  ])
    assert.throws(() =>
      summarizeCash(
        [
          {
            organization_id: "farm",
            occurred_at: "2026-10-01",
            currency: "VND",
            kind: "THU",
            ...amount,
          },
        ],
        "farm",
        "2026-10",
      ),
    );
});

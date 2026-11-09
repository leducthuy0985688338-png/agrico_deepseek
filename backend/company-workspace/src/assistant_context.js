import { fail } from "./domain.js";
// The published snapshot is the source; this is not a live cash balance.
export function summarizeCash(rows, farm, period) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(period)) fail("invalid");
  const decimal = (value) => {
    const negative = value < 0n;
    const digits = (negative ? -value : value).toString().padStart(7, "0");
    const out = (digits.slice(0, -6) + "." + digits.slice(-6))
      .replace(/0+$/, "")
      .replace(/\.$/, "");
    return (negative ? "-" : "") + out;
  };
  const totals = {};
  for (const currency of ["VND", "LAK"]) {
    let receipt = 0n,
      payment = 0n;
    for (const row of rows) {
      if (
        row.organization_id !== farm ||
        row.currency !== currency ||
        !String(row.occurred_at).startsWith(period)
      )
        continue;
      const scale = row.amount_scale ?? 0;
      if (
        !Number.isInteger(scale) ||
        scale < 0 ||
        scale > 6 ||
        !Number.isSafeInteger(row.amount_minor) ||
        row.amount_minor <= 0
      )
        fail("invalidSnapshot");
      const amount = BigInt(row.amount_minor) * 10n ** BigInt(6 - scale);
      if (row.kind === "THU") receipt += amount;
      if (row.kind === "CHI") payment += amount;
    }
    totals[currency] = {
      receipts: decimal(receipt),
      payments: decimal(payment),
      net: decimal(receipt - payment),
    };
  }
  return totals;
}

// Run at repository root. Uses local Dart only; no credentials or deployment.
import { readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { templates } from "../src/templates.js";
const dart = process.platform === "win32" ? "dart.bat" : "dart";
const result = spawnSync(
  dart,
  ["backend/company-workspace/tools/export-policy.dart"],
  { encoding: "utf8", shell: process.platform === "win32" },
);
if (result.status !== 0)
  throw Error(result.stderr || "Dart policy export failed.");
writeFileSync(
  "backend/company-workspace/src/role-policy.json",
  JSON.stringify(JSON.parse(result.stdout), null, 2) + "\n",
);
const target =
  "lib/features/company_workspace/domain/administrative_templates.dart";
const old = readFileSync(target, "utf8");
const start = old.indexOf("r'''"),
  end = old.indexOf("'''", start + 4);
if (start < 0 || end < 0) throw Error("Review Dart template markers.");
writeFileSync(
  target,
  old.slice(0, start + 4) + JSON.stringify(templates, null, 2) + old.slice(end),
);
console.log(
  "Policy and templates exported. Review Firestore/Storage grants when permissions change.",
);

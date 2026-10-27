import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
const backend = resolve(dirname(fileURLToPath(import.meta.url)), ".."),
  root = resolve(backend, "../.."),
  temporary = mkdtempSync(join(tmpdir(), "agrico-tests-"));
try {
  const original = readFileSync(
    join(root, "tools/access_rules/access-rules.test.cjs"),
    "utf8",
  );
  const target =
    "require('node:path').resolve(__dirname,'../../docs/security/agrico-memberships.rules')";
  if (!original.includes(target))
    throw Error("Review changed existing rules fixture.");
  const old = join(temporary, "existing.cjs");
  writeFileSync(
    old,
    original
      .replaceAll("demo-agrico-access", "demo-agrico-workspace")
      .replace(
        target,
        JSON.stringify(
          join(root, "docs/security/agrico-company-workspace.rules"),
        ),
      ),
  );
  const quote = (v) => '"' + v.replaceAll('"', '\\"') + '"';
  const command = [
    process.execPath,
    "--test",
    "--test-concurrency=1",
    join(backend, "test/rules.test.js"),
    join(backend, "test/processor.test.js"),
    old,
  ]
    .map(quote)
    .join(" ");
  const result = spawnSync(
    process.execPath,
    [
      join(backend, "node_modules/firebase-tools/lib/bin/firebase.js"),
      "--config",
      "firebase.workspace-test.json",
      "emulators:exec",
      "--project",
      "demo-agrico-workspace",
      "--only",
      "firestore,storage",
      command,
    ],
    {
      cwd: root,
      stdio: "inherit",
      env: {
        ...process.env,
        CI: "true",
        GCLOUD_PROJECT: "demo-agrico-workspace",
        GOOGLE_CLOUD_PROJECT: "demo-agrico-workspace",
        NODE_PATH: join(backend, "node_modules"),
      },
    },
  );
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  rmSync(temporary, { recursive: true, force: true });
}

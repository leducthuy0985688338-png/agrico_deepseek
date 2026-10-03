# Local access Rules tests

These tests use `demo-agrico-access`, never the production `agrico-erp` project.
No Firebase login, deployment, service account or GitHub Actions is required.

Requirements: Node.js supported by the pinned Firebase CLI, npm, Java 17+ (21 recommended).
From the repository root in Windows PowerShell:

```powershell
cd tools/access_rules
npm ci --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
npm test
if ($LASTEXITCODE -ne 0) { throw 'Rules tests failed' }
```

The CLI downloads the Firestore emulator on the first run. Tests clear only the local demo emulator database and stop the emulator at completion. Do not change the project to a real Firebase project. The config `firebase.access-test.json` is used only for emulator tests and is not a deployment config.

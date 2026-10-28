[CmdletBinding()]
param([switch]$Deploy,[switch]$IncludeAI)
$ErrorActionPreference='Stop'
$repoPath=Split-Path $PSScriptRoot -Parent
Push-Location $repoPath
try {
    $cli=Join-Path $repoPath 'backend/company-workspace/node_modules/firebase-tools/lib/bin/firebase.js'
    if (-not (Test-Path $cli)) { throw 'Run npm ci --prefix backend/company-workspace with Node 22 first.' }
    $only='firestore:rules,firestore:indexes,storage,functions:company-workspace:companyWorkspaceCommand,functions:company-workspace:companyWorkspaceResult'
    if ($IncludeAI) { $only+=',functions:company-workspace:companyWorkspaceAssistant' }
    Write-Host "Project: agrico-erp | Targets: $only"
    if (-not $Deploy) {
        Write-Host 'Plan only. Compare live rules and indexes before replacing them.'
        Write-Host 'AI requires AGRICO_AI_API_KEY in Secret Manager, entered interactively via Firebase CLI.'
        Write-Host 'No deployment performed. After review use -Deploy and optionally -IncludeAI.'
        return
    }
    & node $cli deploy --project agrico-erp --config firebase.company-workspace.json --only $only
    if ($LASTEXITCODE -ne 0) { throw 'Deployment failed; inspect targets individually.' }
    Write-Host 'Deployment command completed. Verify with two separate accounts before general use.'
} finally { Pop-Location }

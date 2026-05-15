param(
  [string]$Username = "dxhfqhsd5c",
  [string]$Email = "",
  [string]$Password = "",
  [string]$Database = "flames-up",
  [switch]$Local
)

$ErrorActionPreference = "Stop"

function Escape-SqlText([string]$Value) {
  return $Value.Replace("'", "''")
}

if (-not $Password) {
  $secure = Read-Host "New Governance admin password" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

if (-not $Password -or $Password.Length -lt 8) {
  throw "Use an admin password with at least 8 characters."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$backendDir = Join-Path $repoRoot "backend-cf"
$npx = "C:\Program Files\nodejs\npx.cmd"
if (-not (Test-Path $npx)) {
  $npx = "npx"
}

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Password + "flames-up-salt")
  $hashBytes = $sha.ComputeHash($bytes)
  $passwordHash = ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
} finally {
  $sha.Dispose()
}

$usernameSql = Escape-SqlText $Username.ToLowerInvariant().TrimStart("@")
$where = "LOWER(username) = '$usernameSql'"
if ($Email.Trim()) {
  $emailSql = Escape-SqlText $Email.ToLowerInvariant().Trim()
  $where = "($where OR LOWER(email) = '$emailSql')"
}

$selectSql = "SELECT id, email, username, full_name, is_admin FROM users WHERE $where LIMIT 5;"
$updateSql = "UPDATE users SET is_admin = 1, password_hash = '$passwordHash', status = COALESCE(NULLIF(status, ''), 'active'), updated_at = datetime('now') WHERE $where;"
$verifySql = "SELECT id, email, username, full_name, is_admin FROM users WHERE $where LIMIT 5;"

$remoteArgs = @()
if (-not $Local) {
  $remoteArgs += "--remote"
}

Push-Location $backendDir
try {
  Write-Host "Checking matching Flames-Up account..." -ForegroundColor Cyan
  & $npx wrangler d1 execute $Database @remoteArgs --command $selectSql
  if ($LASTEXITCODE -ne 0) { throw "Wrangler could not query D1. Run wrangler login first, then retry." }

  Write-Host "Granting Governance admin access and setting password..." -ForegroundColor Cyan
  & $npx wrangler d1 execute $Database @remoteArgs --command $updateSql
  if ($LASTEXITCODE -ne 0) { throw "Wrangler could not update D1." }

  Write-Host "Verifying admin account..." -ForegroundColor Cyan
  & $npx wrangler d1 execute $Database @remoteArgs --command $verifySql
  if ($LASTEXITCODE -ne 0) { throw "Wrangler could not verify D1 update." }

  Write-Host ""
  Write-Host "Done. Login to Governance Mobile with this account and the password you just entered." -ForegroundColor Green
} finally {
  Pop-Location
}

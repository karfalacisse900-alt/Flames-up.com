param([Parameter(Mandatory=$true)][string]$Package, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Package))
function Copy-BrandEntry([string]$entryName, [string]$relativeTarget) {
  $entry = $zip.GetEntry('captro-brand-package/' + $entryName)
  if ($null -eq $entry) { throw "Missing supplied asset: $entryName" }
  $target = [IO.Path]::GetFullPath((Join-Path $root $relativeTarget))
  if (!$target.StartsWith($root + [IO.Path]::DirectorySeparatorChar)) { throw 'Unsafe asset target' }
  $stream = $entry.Open()
  try {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $expected = [Convert]::ToHexString($hasher.ComputeHash($stream)) } finally { $hasher.Dispose() }
  } finally { $stream.Dispose() }
  if ($ValidateOnly) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash -ne $expected) { throw "Supplied asset differs: $relativeTarget" }
    return
  }
  # This Windows workspace permits writes through WSL but blocks new binary files
  # from PowerShell. Extract to a unique temporary file, then copy exact bytes.
  $temporary = Join-Path ([IO.Path]::GetTempPath()) ('captro-brand-' + [guid]::NewGuid().ToString() + '.asset')
  [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $temporary, $false)
  try {
    $linuxTarget = '/mnt/' + $target.Substring(0,1).ToLower() + $target.Substring(2).Replace('\','/')
    $linuxSource = '/mnt/' + $temporary.Substring(0,1).ToLower() + $temporary.Substring(2).Replace('\','/')
    wsl mkdir -p ([IO.Path]::GetDirectoryName($linuxTarget).Replace('\','/'))
    wsl cp -- $linuxSource $linuxTarget
    if ($LASTEXITCODE -ne 0) { throw "Asset copy failed: $relativeTarget" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash -ne $expected) { throw "Supplied asset differs: $relativeTarget" }
  } finally { Remove-Item -LiteralPath $temporary }
}
try {
  $catalog = 'ios_native/MIRA/AppTarget/Assets.xcassets'
  Copy-BrandEntry 'AppIcon.appiconset/AppIcon-1024.png' "$catalog/AppIcon.appiconset/AppIcon-1024.png"
  Copy-BrandEntry 'AppIcon.appiconset/Contents.json' "$catalog/AppIcon.appiconset/Contents.json"
  Copy-BrandEntry 'png/captro-lockup-black-2400.png' "$catalog/CaptroLaunchLogo.imageset/captro-lockup-black.png"
  Copy-BrandEntry 'png/captro-lockup-white-2400.png' "$catalog/CaptroBrandWhite.imageset/captro-lockup-white.png"
  foreach ($webRoot in @('captro-site', 'admin-web/public')) {
    foreach ($asset in @('favicon.ico','favicon.svg','captro-icon-180.png','captro-icon-192.png','captro-icon-512.png')) {
      Copy-BrandEntry "web/$asset" "$webRoot/$asset"
    }
    foreach ($asset in @('captro-lockup-black.svg','captro-lockup-white.svg','captro-symbol-black.svg','captro-symbol-white.svg')) {
      Copy-BrandEntry "svg/$asset" "$webRoot/brand/$asset"
    }
  }
  foreach ($asset in @('README.md','CODEX-HANDOFF.md','validation.json','licenses/Poppins-OFL.txt','licenses/ATTRIBUTION.md')) {
    Copy-BrandEntry $asset "design/captro-official-brand/$asset"
  }
  $master = $zip.GetEntry('captro-brand-package/app-icons/captro-app-icon-dark-1024.png').Open()
  try {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $masterHash = [Convert]::ToHexString($sha.ComputeHash($master)) } finally { $sha.Dispose() }
  } finally { $master.Dispose() }
  $installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root "$catalog/AppIcon.appiconset/AppIcon-1024.png")).Hash
  if ($masterHash -ne $installedHash) { throw 'App icon differs from supplied dark master' }
  Write-Output "All mapped supplied assets byte-verified; AppIcon SHA256: $installedHash"
} finally { $zip.Dispose() }

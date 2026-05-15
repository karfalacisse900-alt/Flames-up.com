$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"

if (!(Test-Path $sdk)) {
  throw "Android SDK not found at $sdk. Open Android Studio > SDK Manager first."
}

$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:Path = "$env:USERPROFILE\.cargo\bin;$sdk\platform-tools;$env:Path"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
$env:GRADLE_USER_HOME = "C:\flames_gradle_user_home"

if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "cargo is not on PATH. Install Rust first."
}

if (!(cargo ndk --version 2>$null)) {
  throw "cargo-ndk is not installed. Run: cargo install cargo-ndk"
}

if (!(Test-Path (Join-Path $sdk "ndk"))) {
  throw "Android NDK is missing. Install NDK (Side by side) in Android Studio SDK Manager."
}

Set-Location $root
New-Item -ItemType Directory -Path "C:\flames_gradle_project_cache" -Force | Out-Null
New-Item -ItemType Directory -Path $env:GRADLE_USER_HOME -Force | Out-Null
.\gradlew.bat assembleDebug --project-cache-dir C:\flames_gradle_project_cache

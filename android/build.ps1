# Builds the Team2 APK without Gradle.
#   powershell -ExecutionPolicy Bypass -File build.ps1
#
# The APK is a shell. It holds no app code - it opens https://team2.carloo.in,
# so pushing to GitHub updates every phone. You only rebuild this when the shell
# itself changes (permissions, splash, icon), not when the app changes.
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$sdk  = "$env:LOCALAPPDATA\Android\Sdk"
$out  = "$root\build"
$keystore = "$root\team2-release.keystore"
$passFile = "$root\.keystore-pass"

if (-not (Test-Path $sdk)) { throw "Android SDK not found at $sdk - install it from Android Studio." }

# Newest build-tools and newest platform jar, rather than pinned versions that
# go stale every time Android Studio updates.
$bt = (Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$jar = (Get-ChildItem "$sdk\platforms" -Directory | Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "android.jar" } | Where-Object { Test-Path $_ } | Select-Object -First 1)
if (-not $bt)  { throw "No build-tools under $sdk\build-tools" }
if (-not $jar) { throw "No platform android.jar under $sdk\platforms" }

$jbr = "C:\Program Files\Android\Android Studio\jbr"
if (-not (Test-Path "$jbr\bin\javac.exe")) { throw "Android Studio JBR not found at $jbr" }
# d8 and apksigner are .bat wrappers that need a JDK on PATH.
$env:JAVA_HOME = $jbr
$env:PATH = "$jbr\bin;$env:PATH"

Write-Host "build-tools : $(Split-Path $bt -Leaf)"
Write-Host "platform    : $(Split-Path (Split-Path $jar -Parent) -Leaf)"

# The signing key. Android refuses to install an update signed by a different
# key, so THIS FILE IS THE ONLY WAY TO EVER UPDATE AN INSTALLED TEAM2 APP.
# It is deliberately not in git. Back it up somewhere off this laptop.
if ($env:TEAM2_KS_PASS) {
  $pass = $env:TEAM2_KS_PASS
} elseif (Test-Path $passFile) {
  $pass = (Get-Content $passFile -Raw).Trim()
} else {
  $secure = Read-Host "Choose a password for the new signing key" -AsSecureString
  $pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
  if ($pass.Length -lt 6) { throw "Use at least 6 characters." }
}
# Always keep it next to the key. Without this, a later build with no
# TEAM2_KS_PASS set would prompt for a new password and then fail to sign with
# the existing key.
if (-not (Test-Path $passFile)) {
  Set-Content -Path $passFile -Value $pass -Encoding ascii -NoNewline
  Write-Host "Signing password saved to $passFile (git-ignored)."
}

Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$out\classes","$out\dex","$out\gen" | Out-Null

Write-Host "1/6 compiling resources"
& "$bt\aapt2.exe" compile --dir "$root\res" -o "$out\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile failed" }

Write-Host "2/6 linking resources"
& "$bt\aapt2.exe" link -o "$out\base.apk" -I $jar `
  --manifest "$root\AndroidManifest.xml" --java "$out\gen" --auto-add-overlay "$out\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

Write-Host "3/6 compiling java"
$srcs = @(Get-ChildItem -Recurse "$root\src" -Filter *.java | Select-Object -ExpandProperty FullName)
$gen  = @(Get-ChildItem -Recurse "$out\gen" -Filter *.java -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
& "$jbr\bin\javac.exe" -nowarn -source 11 -target 11 -classpath $jar -d "$out\classes" ($srcs + $gen)
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

Write-Host "4/6 dexing"
$classFiles = @(Get-ChildItem -Recurse "$out\classes" -Filter *.class | Select-Object -ExpandProperty FullName)
& "$bt\d8.bat" --release --min-api 24 --lib $jar --output "$out\dex" $classFiles
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }

Write-Host "5/6 packaging"
Copy-Item "$out\base.apk" "$out\unsigned.apk" -Force
Push-Location "$out\dex"
& "$jbr\bin\jar.exe" uf "$out\unsigned.apk" classes.dex
Pop-Location
& "$bt\zipalign.exe" -f 4 "$out\unsigned.apk" "$out\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

Write-Host "6/6 signing"
if (-not (Test-Path $keystore)) {
  & "$jbr\bin\keytool.exe" -genkeypair -v -keystore $keystore -alias team2 `
    -keyalg RSA -keysize 2048 -validity 10950 `
    -storepass $pass -keypass $pass `
    -dname "CN=Team2, O=Carloo Tex, L=Tirupur, C=IN"
  if ($LASTEXITCODE -ne 0) { throw "keytool failed" }
  Write-Host ""
  Write-Host "A new signing key was created: $keystore" -ForegroundColor Yellow
  Write-Host "Back this file up off the laptop. Lose it and no installed copy of" -ForegroundColor Yellow
  Write-Host "Team2 can ever be updated again - everyone would have to uninstall." -ForegroundColor Yellow
  Write-Host ""
}
& "$bt\apksigner.bat" sign --ks $keystore --ks-pass "pass:$pass" --key-pass "pass:$pass" `
  --out "$root\Team2.apk" "$out\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }
& "$bt\apksigner.bat" verify --print-certs "$root\Team2.apk"

$size = [math]::Round((Get-Item "$root\Team2.apk").Length / 1KB)
Write-Host ""
Write-Host "Built $root\Team2.apk ($size KB)" -ForegroundColor Green

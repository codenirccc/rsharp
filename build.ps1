Param([switch]$Clean)

$ErrorActionPreference = 'Stop'
if ($env:RSC_ROOT) {
    $Root = $env:RSC_ROOT.TrimEnd('\', '/')
} else {
    $Root = $PSScriptRoot
}
if ($env:RSC_CLEAN -eq '1') { $Clean = $true }
$Bash = 'C:\msys64\usr\bin\bash.exe'

if (-not (Test-Path -LiteralPath $Bash)) {
    throw "missing toolchain: $Bash"
}

if ($Clean) {
    foreach ($dir in 'frontend\target', 'cdc\target') {
        $p = Join-Path $Root $dir
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
    $rscb = Join-Path $Root 'backend\rscb.exe'
    if (Test-Path -LiteralPath $rscb) { Remove-Item -LiteralPath $rscb -Force }
}

Write-Host '==> front end (rust)'
Push-Location -LiteralPath (Join-Path $Root 'frontend')
try {
    cargo build --release
    if ($LASTEXITCODE -ne 0) { throw 'cargo build failed' }
} finally {
    Pop-Location
}

Write-Host '==> back end (ocaml)'
$backend = (Join-Path $Root 'backend') -replace '\\', '/'
$msys = '/c/' + $backend.Substring(3)
& $Bash -c "export PATH=/ucrt64/bin:/mingw64/bin:/usr/bin; bash '$msys/build.sh'"
if ($LASTEXITCODE -ne 0) { throw 'ocaml build failed' }

Write-Host '==> cdc (rust)'
Push-Location -LiteralPath (Join-Path $Root 'cdc')
try {
    cargo build --release
    if ($LASTEXITCODE -ne 0) { throw 'cdc build failed' }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host 'all three are up. try:'
Write-Host '  rsc.cmd examples\hello.rsx'
Write-Host '  rsc.cmd examples\fib.rsx build\fib.exe'
Write-Host '  rsc.cmd -t macos examples\hello.rsx build\hello'
Write-Host '  cdc\target\release\cdc.exe new demo'

$ErrorActionPreference = 'Stop'

$Argv = @()
if ($env:BASICR_ARGV) {
    if (Test-Path -LiteralPath $env:BASICR_ARGV) {
        $Argv = @(Get-Content -LiteralPath $env:BASICR_ARGV)
    }
} else {
    $Argv = @($args)
}

$Command = 'install'
$Prefix = ''
$NoBuild = $false
$NoCheck = $false
$SkipPath = $false
$Quiet = $false

$i = 0
while ($i -lt $Argv.Count) {
    $a = [string]$Argv[$i]
    if ($a -eq '--prefix' -or $a -eq '-p') {
        $i++
        if ($i -ge $Argv.Count) {
            Write-Host 'basicr: --prefix needs a directory'
            exit 2
        }
        $Prefix = [string]$Argv[$i]
    } elseif ($a.StartsWith('--prefix=')) {
        $Prefix = $a.Substring(9)
    } elseif ($a -eq '--no-build') {
        $NoBuild = $true
    } elseif ($a -eq '--no-check') {
        $NoCheck = $true
    } elseif ($a -eq '--skip-path') {
        $SkipPath = $true
    } elseif ($a -eq '--quiet' -or $a -eq '-q') {
        $Quiet = $true
    } elseif ($a -eq '--help' -or $a -eq '-h') {
        $Command = 'help'
    } elseif ($a.StartsWith('-')) {
        Write-Host "basicr: unknown flag '$a'"
        exit 2
    } else {
        $Command = $a
    }
    $i++
}

function Say([string]$Text) {
    if (-not $Quiet) { Write-Host "basicr: $Text" }
}

function Fail([string]$Text) {
    Write-Host "basicr: $Text" -ForegroundColor Red
    exit 1
}

function Usage {
    Write-Host 'basicr - install the R# toolchain'
    Write-Host ''
    Write-Host '  basicr [install] [--prefix <dir>] [--no-build] [--no-check] [--skip-path] [--quiet]'
    Write-Host '  basicr check     [--prefix <dir>] [--quiet]'
    Write-Host '  basicr uninstall [--prefix <dir>] [--quiet]'
    Write-Host '  basicr env       [--prefix <dir>]'
    exit 0
}

function Resolve-Root {
    if ($env:RSC_ROOT) {
        return $env:RSC_ROOT.TrimEnd('\', '/')
    }
    if ($PSScriptRoot) {
        return (Split-Path -Parent $PSScriptRoot)
    }
    if ($env:BASICR_SCRIPT) {
        return (Split-Path -Parent (Split-Path -Parent $env:BASICR_SCRIPT))
    }
    Fail 'cannot find the source root; set RSC_ROOT'
}

function Resolve-Prefix {
    if ($Prefix) {
        return [System.IO.Path]::GetFullPath($Prefix)
    }
    if ($env:RSC_PREFIX) {
        return [System.IO.Path]::GetFullPath($env:RSC_PREFIX)
    }
    return (Join-Path $env:LOCALAPPDATA 'rsharp')
}

$Root = Resolve-Root
$script:Pfx = ''
$script:Toolchain = ''
$script:BinDir = ''

function Set-Layout {
    $script:Pfx = Resolve-Prefix
    $script:Toolchain = Join-Path $script:Pfx 'toolchain'
    $script:BinDir = Join-Path $script:Pfx 'bin'
}

function Invoke-Build {
    $script = Join-Path $Root 'build.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        Fail "no build.ps1 under $Root"
    }
    Say "building the toolchain in $Root"
    $env:RSC_ROOT = $Root
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $text = "Invoke-Expression (Get-Content -Raw -LiteralPath '$($script -replace "'", "''")')"
    & $ps -NoProfile -ExecutionPolicy Bypass -Command $text
    if ($LASTEXITCODE -ne 0) {
        Fail 'the build failed'
    }
}

function Get-Binaries {
    $list = @()
    $front = Join-Path $Root 'frontend\target\release\rsc.exe'
    $back = Join-Path $Root 'backend\rscb.exe'
    if (-not (Test-Path -LiteralPath $front) -or -not (Test-Path -LiteralPath $back)) {
        if ($NoBuild) {
            Fail 'the toolchain is not built; drop --no-build or run build.ps1'
        }
        Invoke-Build
    }
    if (-not (Test-Path -LiteralPath $front)) { Fail "missing $front" }
    if (-not (Test-Path -LiteralPath $back)) { Fail "missing $back" }
    $list += @{ Name = 'rsc.exe'; Path = $front }
    $list += @{ Name = 'rscb.exe'; Path = $back }
    $cdc = Join-Path $Root 'cdc\target\release\cdc.exe'
    if (Test-Path -LiteralPath $cdc) { $list += @{ Name = 'cdc.exe'; Path = $cdc } }
    $mini = Join-Path $Root 'mini\mini.exe'
    if (Test-Path -LiteralPath $mini) { $list += @{ Name = 'mini.exe'; Path = $mini } }
    return $list
}

function Install-Files($List) {
    New-Item -ItemType Directory -Force -Path $script:Toolchain | Out-Null
    New-Item -ItemType Directory -Force -Path $script:BinDir | Out-Null
    foreach ($item in $List) {
        Copy-Item -LiteralPath $item.Path -Destination (Join-Path $script:Toolchain $item.Name) -Force
    }
    $license = Join-Path $Root 'LICENSE'
    if (Test-Path -LiteralPath $license) {
        Copy-Item -LiteralPath $license -Destination (Join-Path $script:Pfx 'LICENSE') -Force
    }
}

function Write-Shims {
    $rsc = @'
@echo off
setlocal
set "TC=%~dp0..\toolchain"
set "FRONT=%TC%\rsc.exe"
set "BACK=%TC%\rscb.exe"

set "TGT=windows"
if /i "%~1"=="-t" (
    set "TGT=%~2"
    shift
    shift
)

if "%~1"=="" (
    echo usage: rsc [-t windows^|macos] ^<file.rsx^> [out]
    exit /b 2
)

set "IN=%~f1"
for %%F in ("%IN%") do (
    set "DIR=%%~dpF"
    set "STEM=%%~nF"
)

if "%TGT%"=="macos" (set "EXT=") else (set "EXT=.exe")
if "%~2"=="" (set "OUT=%DIR%%STEM%%EXT%") else (set "OUT=%~f2")
set "IR=%DIR%%STEM%.rsi"

for %%D in ("%OUT%") do if not exist "%%~dpD" mkdir "%%~dpD" >nul 2>&1

"%FRONT%" "%IN%" -o "%IR%"
if errorlevel 1 exit /b 1

"%BACK%" "%IR%" -o "%OUT%" -s "%IN%" -t "%TGT%"
if errorlevel 1 exit /b 1

del "%IR%" >nul 2>&1
echo built %OUT%
'@
    Set-Content -LiteralPath (Join-Path $script:BinDir 'rsc.cmd') -Value $rsc -Encoding ASCII

    foreach ($name in 'rscb', 'cdc', 'mini') {
        $exe = Join-Path $script:Toolchain ($name + '.exe')
        if (Test-Path -LiteralPath $exe) {
            $shim = "@echo off`r`n`"%~dp0..\toolchain\$name.exe`" %*`r`nexit /b %ERRORLEVEL%`r`n"
            Set-Content -LiteralPath (Join-Path $script:BinDir ($name + '.cmd')) -Value $shim -Encoding ASCII -NoNewline
        }
    }

    $envcmd = "@echo off`r`nset `"PATH=%~dp0bin;%PATH%`"`r`n"
    Set-Content -LiteralPath (Join-Path $script:Pfx 'env.cmd') -Value $envcmd -Encoding ASCII -NoNewline
}

function Add-ToPath {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $user) { $user = '' }
    $parts = @($user -split ';' | Where-Object { $_ -ne '' })
    if ($parts -contains $script:BinDir) {
        Say "PATH already has $script:BinDir"
    } else {
        $next = (@($script:BinDir) + $parts) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $next, 'User')
        Say "PATH updated with $script:BinDir"
    }
    $env:Path = $script:BinDir + ';' + $env:Path
}

function Remove-FromPath {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $user) { return }
    $parts = @($user -split ';' | Where-Object { $_ -ne '' -and $_ -ne $script:BinDir })
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

function Test-Install {
    $rsc = Join-Path $script:BinDir 'rsc.cmd'
    if (-not (Test-Path -LiteralPath $rsc)) {
        Fail "no rsc.cmd under $script:BinDir; run basicr install"
    }
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('basicr-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    try {
        $src = Join-Path $dir 'hello.rsx'
        Set-Content -LiteralPath $src -Encoding ASCII -Value @(
            'extern fn puts(s: ptr<u8>) -> i32;',
            '',
            'fn main() -> i32 {',
            '    puts("hello from R#");',
            '    return 0;',
            '}'
        )
        $exe = Join-Path $dir 'hello.exe'
        $build = & $rsc $src $exe 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ($build -join "`n")
            Fail 'the compiler did not build hello.rsx'
        }
        $out = & $exe
        if ($LASTEXITCODE -ne 0) {
            Fail 'hello.exe did not exit clean'
        }
        if (($out -join "`n").Trim() -ne 'hello from R#') {
            Fail "hello.exe printed '$($out -join "`n")'"
        }
        Say 'check ok: hello from R#'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install {
    Set-Layout
    Say "prefix $script:Pfx"
    $list = Get-Binaries
    Install-Files $list
    Write-Shims
    if (-not $SkipPath) {
        Add-ToPath
    }
    $names = ($list | ForEach-Object { $_.Name -replace '\.exe$', '' }) -join ', '
    Say "installed $names"
    if (-not $NoCheck) {
        Test-Install
    }
    if (-not $SkipPath) {
        Say 'open a new shell to pick up PATH, or run env.cmd now'
    }
}

function Check {
    Set-Layout
    Say "prefix $script:Pfx"
    Test-Install
}

function Uninstall {
    Set-Layout
    $home_ = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    $pfx = $script:Pfx.TrimEnd('\')
    if ($pfx -eq '' -or $pfx -eq '/' -or $pfx -eq $home_) {
        Fail "refusing to touch '$($script:Pfx)'"
    }
    Say "prefix $script:Pfx"
    Remove-FromPath
    if (Test-Path -LiteralPath $script:Pfx) {
        Remove-Item -LiteralPath $script:Pfx -Recurse -Force
    }
    Say 'removed'
}

switch ($Command.ToLowerInvariant()) {
    'install' { Install }
    'check' { Check }
    'uninstall' { Uninstall }
    'env' {
        Set-Layout
        Write-Host "`$env:Path = '$($script:BinDir);' + `$env:Path"
    }
    'help' { Usage }
    '-h' { Usage }
    '--help' { Usage }
    default { Usage }
}

exit 0

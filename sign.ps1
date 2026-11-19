Param(
    [string[]]$Files = @(),
    [string]$List = '',
    [string]$Store = '',
    [switch]$Trust
)

$ErrorActionPreference = 'Stop'

try { Set-Location -LiteralPath $env:SystemRoot } catch { }

$Subject = 'CN=rsharp, O=rsharp, C=US'
$PfxPassword = 'rsharp'
$CerName = 'rsharp-selfsigned.cer'

function Say([string]$Text) {
    Write-Host "sign: $Text"
}

function Fail([string]$Text) {
    Write-Host "sign: $Text" -ForegroundColor Red
    exit 1
}

if ($Store) {
    $Dir = [System.IO.Path]::GetFullPath($Store)
} elseif ($PSScriptRoot) {
    $Dir = Join-Path $PSScriptRoot '.signing'
} else {
    $Dir = Join-Path $env:LOCALAPPDATA 'rsharp\signing'
}
[System.IO.Directory]::CreateDirectory($Dir) | Out-Null

$pfx = Join-Path $Dir 'rsharp-selfsigned.pfx'
$cer = Join-Path $Dir $CerName
$thumbFile = Join-Path $Dir 'thumbprint.txt'

$secure = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText

function Find-Usable {
    if (-not (Test-Path -LiteralPath $thumbFile)) { return $null }
    $thumb = (Get-Content -LiteralPath $thumbFile -Raw).Trim()
    if (-not $thumb) { return $null }
    $path = "Cert:\CurrentUser\My\$thumb"
    if (Test-Path -LiteralPath $path) { return (Get-Item -LiteralPath $path) }
    return $null
}

$Cert = Find-Usable

if (-not $Cert -and [System.IO.File]::Exists($pfx)) {
    $Cert = Import-PfxCertificate -FilePath $pfx -CertStoreLocation 'Cert:\CurrentUser\My' -Password $secure
    if ($Cert) { Set-Content -LiteralPath $thumbFile -Value $Cert.Thumbprint -Encoding ASCII }
}

if (-not $Cert) {
    $Cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $Subject `
        -KeyAlgorithm RSA `
        -KeyLength 3072 `
        -HashAlgorithm SHA256 `
        -KeyExportPolicy Exportable `
        -KeyUsage DigitalSignature `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -NotAfter (Get-Date).AddYears(10) `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')
    Export-PfxCertificate -Cert $Cert -FilePath $pfx -Password $secure | Out-Null
    Export-Certificate -Cert $Cert -FilePath $cer -Type CERT | Out-Null
    Set-Content -LiteralPath $thumbFile -Value $Cert.Thumbprint -Encoding ASCII
    Say "created $Subject"
}

if (-not [System.IO.File]::Exists($cer)) {
    Export-Certificate -Cert $Cert -FilePath $cer -Type CERT | Out-Null
}

Say "thumbprint $($Cert.Thumbprint)"

if ($Trust) {
    foreach ($name in 'Root', 'TrustedPublisher') {
        $spath = "Cert:\CurrentUser\$name"
        $have = Get-ChildItem -LiteralPath $spath | Where-Object { $_.Thumbprint -eq $Cert.Thumbprint }
        if ($have) {
            Say "already trusted in $name"
        } else {
            Import-Certificate -FilePath $cer -CertStoreLocation $spath | Out-Null
            Say "trusted in $name"
        }
    }
}

$signed = 0
$failed = 0
$targets = @()
$base = $Dir
if ($List) {
    $listPath = [System.IO.Path]::GetFullPath($List)
    if (-not [System.IO.File]::Exists($listPath)) {
        Fail "missing list $listPath"
    }
    $base = [System.IO.Path]::GetDirectoryName($listPath)
    foreach ($line in [System.IO.File]::ReadAllLines($listPath)) {
        $t = $line.Trim()
        if ($t -and -not $t.StartsWith('#')) { $targets += $t }
    }
}
foreach ($f in $Files) {
    if ($f) { $targets += $f }
}

foreach ($f in $targets) {
    if (-not [System.IO.Path]::IsPathRooted($f)) { $f = Join-Path $base $f }
    $full = [System.IO.Path]::GetFullPath($f)
    if (-not [System.IO.File]::Exists($full)) {
        Say "missing $full"
        $failed++
        continue
    }
    $name = [System.IO.Path]::GetFileName($full)
    $bytes = [System.IO.File]::ReadAllBytes($full)
    if ($bytes.Length -lt 2 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        Say "skip $name (not a PE image)"
        continue
    }
    $sig = Set-AuthenticodeSignature -LiteralPath $full -Certificate $Cert -HashAlgorithm SHA256
    if ($sig.Status -eq 'Valid' -or $sig.Status -eq 'UnknownError' -or $sig.Status -eq 'NotTrusted') {
        Say "signed $name [$($sig.Status)]"
        $signed++
    } else {
        Say "failed $name [$($sig.Status)] $($sig.StatusMessage)"
        $failed++
    }
}

Say "$signed signed, $failed failed"
Say "certificate $cer"
if ($failed -gt 0) { exit 1 }
exit 0

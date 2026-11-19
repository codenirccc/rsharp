param(
    [string]$Root = "",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
if ($Root -eq "") {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $Root = (Resolve-Path (Join-Path $here "..\..")).Path
}
$root = (Resolve-Path -LiteralPath $Root).Path
if ($Out -eq "") {
    $Out = Join-Path $root "..\plaguevm-site\public\basicRresp"
}
$Out = [System.IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$ver = "1.0.0"

$pkgs = @(
    @{ n = "rt";     f = "modules/http/rt.rsx";       d = "-" },
    @{ n = "math";   f = "modules/math.rsx";          d = "-" },
    @{ n = "linalg"; f = "modules/linalg.rsx";        d = "-" },
    @{ n = "rand";   f = "modules/rand.rsx";          d = "-" },
    @{ n = "vec";    f = "modules/game/vec.rsx";      d = "math" },
    @{ n = "easing"; f = "modules/game/easing.rsx";   d = "math" },
    @{ n = "noise";  f = "modules/game/noise.rsx";    d = "-" },
    @{ n = "color";  f = "modules/gui/core/color.rsx"; d = "-" },
    @{ n = "sha256"; f = "modules/http/sha256.rsx";   d = "-" },
    @{ n = "sha512"; f = "modules/http/sha512.rsx";   d = "rt" },
    @{ n = "sha1";   f = "modules/http/sha1.rsx";     d = "rt" },
    @{ n = "hmac";   f = "modules/http/hmac.rsx";     d = "rt,sha256" },
    @{ n = "der";    f = "modules/http/der.rsx";      d = "rt" },
    @{ n = "bignum"; f = "modules/http/bignum.rsx";   d = "-" },
    @{ n = "aes_gcm"; f = "modules/http/aes_gcm.rsx"; d = "rt" }
)

$ascii = [System.Text.Encoding]::ASCII
$lines = New-Object System.Collections.Generic.List[string]
$leaves = @{}

foreach ($p in $pkgs) {
    $src = Join-Path $root $p.f
    if (-not (Test-Path -LiteralPath $src)) {
        throw "missing source for $($p.n): $($p.f)"
    }
    $bytes = [System.IO.File]::ReadAllBytes($src)
    $leaf = Split-Path -Leaf $p.f
    if ($leaves.ContainsKey($leaf)) {
        throw "duplicate leaf name $leaf in $($p.n) and $($leaves[$leaf])"
    }
    $leaves[$leaf] = $p.n
    $rel = "lib/{0}" -f $leaf

    $ms = New-Object System.IO.MemoryStream
    $hdr = $ascii.GetBytes("rspkg 1`n")
    $ms.Write($hdr, 0, $hdr.Length)
    $ent = $ascii.GetBytes(("file {0} {1}`n" -f $rel, $bytes.Length))
    $ms.Write($ent, 0, $ent.Length)
    $ms.Write($bytes, 0, $bytes.Length)
    $nl = $ascii.GetBytes("`n")
    $ms.Write($nl, 0, $nl.Length)
    $blob = $ms.ToArray()
    $ms.Dispose()

    $file = "{0}-{1}.rsp" -f $p.n, $ver
    $dst = Join-Path $Out $file
    [System.IO.File]::WriteAllBytes($dst, $blob)
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash.ToLower()

    $inc = $leaf
    $lines.Add(("{0} {1} {2} {3} {4} {5} {6}" -f $p.n, $ver, $blob.Length, $sha, $file, $p.d, $inc))
    Write-Host ("  {0,-8} {1,7} bytes  {2}" -f $p.n, $blob.Length, $sha.Substring(0, 12))
}

$index = Join-Path $Out "index.txt"
[System.IO.File]::WriteAllText($index, ($lines -join "`n") + "`n", $ascii)
Write-Host ("wrote {0} packages to {1}" -f $pkgs.Count, $Out)

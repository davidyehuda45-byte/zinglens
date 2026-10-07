# ZigLens release packaging (Spec Sec.71-73).
# Builds 6 single-binary targets + archives + SHA256SUMS.
# Usage: .\scripts\release.ps1 -Version 0.5.0
param([string]$Version = "0.5.0")
$ErrorActionPreference = "Stop"
$targets = @(
  @{ t = "x86_64-windows"; ext = ".exe"; arc = "zip" },
  @{ t = "aarch64-windows"; ext = ".exe"; arc = "zip" },
  @{ t = "x86_64-linux"; ext = ""; arc = "tar.gz" },
  @{ t = "aarch64-linux"; ext = ""; arc = "tar.gz" },
  @{ t = "x86_64-macos"; ext = ""; arc = "tar.gz" },
  @{ t = "aarch64-macos"; ext = ""; arc = "tar.gz" }
)
New-Item -ItemType Directory -Force dist | Out-Null
foreach ($x in $targets) {
  $out = "dist/ziglens-$($x.t)"
  New-Item -ItemType Directory -Force $out | Out-Null
  $ztarget = "-Dtarget=$($x.t)"
  zig build "-Doptimize=ReleaseSafe" "$ztarget" --prefix "$out"
  $bin = "$out/bin/ziglens$($x.ext)"
  if ($x.arc -eq "zip") {
    Compress-Archive -Path "$bin" -DestinationPath "dist/ziglens-$($x.t).zip" -Force
  } else {
    tar -czf "dist/ziglens-$($x.t).tar.gz" -C "$out/bin" "ziglens$($x.ext)"
  }
}
Push-Location dist
Get-FileHash ziglens-* -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower())  $($_.Path | Split-Path -Leaf)" } | Set-Content SHA256SUMS
Pop-Location
Write-Output "Release artifacts in dist/ (version $Version)"

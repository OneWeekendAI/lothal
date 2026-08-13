<#
.SYNOPSIS
  Packages the Windows Store export of Lothal into an .msix for Partner Center.

.DESCRIPTION
  Runs on Windows only — MakeAppx.exe ships with the Windows SDK and has no macOS equivalent,
  which is why this is a PowerShell script in a repo whose other release scripts are bash. In
  practice it runs in the windows-build workflow; running it on a local Windows machine works
  and is how the first one should be produced, since a rejected upload teaches you more with a
  local package in front of you than with a CI artifact.

  WHAT THIS DOES NOT DO IS SIGN. A Store-distributed MSIX is signed by Microsoft at ingestion
  with their own certificate, and that is the entire reason Lothal is going through the Store
  as MSIX rather than as a standalone .exe: it is how a project with no code-signing
  certificate ships a Windows build that does not trip SmartScreen. An unsigned .msix cannot be
  double-clicked to install locally — that is expected, not a fault. To test the package on
  your own machine, sign it with a self-signed certificate and trust that certificate first;
  see the note at the bottom of this file.

.PARAMETER StageOnly
  Build the staging tree and manifest, then stop without calling MakeAppx. For inspecting what
  would be packaged.
#>

[CmdletBinding()]
param(
    [string]$IdentityName        = $env:MSIX_IDENTITY_NAME,
    [string]$IdentityPublisher   = $env:MSIX_IDENTITY_PUBLISHER,
    [string]$PublisherDisplayName = $env:MSIX_PUBLISHER_DISPLAY_NAME,
    [string]$Version             = $env:MSIX_VERSION,
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'

$repo    = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$msixDir = $PSScriptRoot
$export  = Join-Path $repo 'build\store'
$stage   = Join-Path $repo 'build\msix\stage'
$outMsix = Join-Path $repo 'build\msix\Lothal.msix'

# ---- Identity ------------------------------------------------------------------------------
# Missing identity is failed loudly and early rather than defaulted. A package built with a
# placeholder identity uploads, is rejected minutes later by ingestion, and the error names the
# field without saying what it expected — an expensive way to discover an unset variable.
foreach ($p in @(
    @{ n = 'IdentityName';         v = $IdentityName;         e = 'MSIX_IDENTITY_NAME' },
    @{ n = 'IdentityPublisher';    v = $IdentityPublisher;    e = 'MSIX_IDENTITY_PUBLISHER' },
    @{ n = 'PublisherDisplayName'; v = $PublisherDisplayName; e = 'MSIX_PUBLISHER_DISPLAY_NAME' }
)) {
    if ([string]::IsNullOrWhiteSpace($p.v)) {
        throw "$($p.n) not set. Pass -$($p.n) or set $($p.e). All three come verbatim from the Product Identity page in Partner Center."
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    # The version the app reports about itself is the one users see in the About box, so a
    # package version invented independently of it would make bug reports ambiguous.
    $versionGd = Get-Content (Join-Path $repo 'src\app\version.gd') -Raw
    if ($versionGd -notmatch 'const\s+CURRENT\s*:=\s*"([^"]+)"') {
        throw 'Could not read CURRENT from src/app/version.gd, and no -Version was given.'
    }
    $Version = $Matches[1]
}

# MSIX demands exactly four parts and requires the last one to be 0 — Microsoft reserves the
# revision field for the Store's own repackaging. "0.2.0" from version.gd therefore becomes
# "0.2.0.0". A three-part version is rejected by MakeAppx with a schema error that does not
# mention the count.
$parts = @($Version -split '\.')
while ($parts.Count -lt 3) { $parts += '0' }
if ($parts.Count -ge 4 -and $parts[3] -ne '0') {
    throw "Package version revision must be 0 (the Store owns that field); got $Version"
}
$packageVersion = '{0}.{1}.{2}.0' -f $parts[0], $parts[1], $parts[2]

# ---- Inputs --------------------------------------------------------------------------------
# The .pck and the .dll are checked by name rather than trusting the export's exit code. A Godot
# export that cannot find the GDExtension library still exits 0 and still writes an .exe; the
# result launches and dies with no physics and no activation, and packaging that into an MSIX
# turns a build mistake into a Store submission.
foreach ($f in @('Lothal.exe', 'Lothal.pck', 'lothal_core.dll')) {
    $path = Join-Path $export $f
    if (-not (Test-Path $path)) {
        throw "Missing $f in $export. Run the 'Windows Store' export preset first."
    }
}

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Copy-Item (Join-Path $export '*') $stage -Recurse
Copy-Item (Join-Path $msixDir 'assets') $stage -Recurse

# ---- Manifest ------------------------------------------------------------------------------
$manifest = Get-Content (Join-Path $msixDir 'AppxManifest.xml.in') -Raw
$manifest = $manifest.Replace('@IDENTITY_NAME@',          $IdentityName)
$manifest = $manifest.Replace('@IDENTITY_PUBLISHER@',     $IdentityPublisher)
$manifest = $manifest.Replace('@PUBLISHER_DISPLAY_NAME@', $PublisherDisplayName)
$manifest = $manifest.Replace('@PACKAGE_VERSION@',        $packageVersion)

if ($manifest -match '@[A-Z_]+@') {
    throw "Unsubstituted placeholder left in manifest: $($Matches[0])"
}

# Parse it before handing it to MakeAppx. Its complaint about malformed XML is a COM HRESULT
# with no line number, whereas this reports the position — which matters because the manifest is
# heavily commented and XML comments cannot contain a double hyphen, so an innocuous-looking
# horizontal rule in a comment block is enough to make the whole file invalid.
try {
    [xml]$manifest | Out-Null
} catch {
    throw "Manifest is not well-formed XML: $($_.Exception.Message)"
}

# UTF-8 without a BOM. MakeAppx reads a BOM'd manifest as malformed XML.
[System.IO.File]::WriteAllText(
    (Join-Path $stage 'AppxManifest.xml'),
    $manifest,
    (New-Object System.Text.UTF8Encoding $false))

Write-Host "==> staged $stage (version $packageVersion)"
if ($StageOnly) { return }

# ---- Pack ----------------------------------------------------------------------------------
# Resolved to a plain string, not left as whatever object each lookup happens to return.
# Get-Command yields a CommandInfo (path in .Source) and Get-ChildItem yields a FileInfo (path in
# .FullName); reading one property off both gives $null on the branch that does not have it, and
# `& $null` fails with a message about pipeline elements that says nothing about makeappx. The
# PATH branch is also the one that never runs on the GitHub runner, so the difference only shows
# up in CI.
$makeappx = (Get-Command makeappx.exe -ErrorAction SilentlyContinue).Source
if (-not $makeappx) {
    # The SDK is not on PATH by default; the newest installed version is the right one to use.
    $makeappx = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter 'makeappx.exe' `
        -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\x64\*' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $makeappx) {
    throw 'makeappx.exe not found on PATH or under the Windows Kits directory. Install the Windows 10/11 SDK (App Certification Kit component).'
}
Write-Host "==> makeappx: $makeappx"

New-Item -ItemType Directory -Path (Split-Path $outMsix) -Force | Out-Null
if (Test-Path $outMsix) { Remove-Item $outMsix -Force }

& $makeappx pack /d $stage /p $outMsix /o
if ($LASTEXITCODE -ne 0) { throw "makeappx failed with exit code $LASTEXITCODE" }

Write-Host "built: $outMsix"
Get-Item $outMsix | Format-List Name, Length, LastWriteTime

# ---------------------------------------------------------------------------------------------
# TESTING THIS PACKAGE LOCALLY
#
#   New-SelfSignedCertificate -Type Custom -Subject "<the exact CN= from Partner Center>" `
#       -KeyUsage DigitalSignature -CertStoreLocation "Cert:\CurrentUser\My" `
#       -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
#
# Sign with signtool, import the certificate into Trusted People, then install. The subject must
# match Identity/@Publisher exactly or Windows refuses the install — the same byte-for-byte rule
# that governs ingestion. Do NOT upload a self-signed package to Partner Center; upload the
# unsigned one this script produces.
# ---------------------------------------------------------------------------------------------

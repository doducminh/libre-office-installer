#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Setup LibreOffice cho Windows Server + IIS de convert Word -> PDF
.DESCRIPTION
    - Cai dat LibreOffice tu file .exe cung thu muc
    - Tao thu muc profile va cap quyen
    - Cap nhat web.config tren IIS (them loadUserProfile = True)
    - Kiem tra ket qua cai dat
.NOTES
    Chay voi quyen Administrator
    Usage: .\Setup-LibreOffice.ps1
    Usage: .\Setup-LibreOffice.ps1 -SiteName "MyWebsite" -AppPoolName "MyAppPool"
#>

param(
    [string]$SiteName      = "Default Web Site",
    [string]$AppPoolName   = "DefaultAppPool",
    [string]$ProfileDir    = "C:\LibreOfficeProfiles",
    [string]$InstallDir    = "C:\Program Files\LibreOffice"
)

# ─── Colors / helpers ────────────────────────────────────────────────────────
function Write-Step   { param($msg) Write-Host "`n[STEP] $msg" -ForegroundColor Cyan }
function Write-OK     { param($msg) Write-Host "  [OK] $msg"   -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "  [!!] $msg"   -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host " [ERR] $msg"   -ForegroundColor Red }

function Exit-Script  { param($msg) Write-Fail $msg; Read-Host "`nNhan Enter de thoat"; exit 1 }

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─── Banner ──────────────────────────────────────────────────────────────────
Write-Host @"

╔══════════════════════════════════════════════════════╗
║   LibreOffice + IIS Setup Script                    ║
║   Word -> PDF Converter for .NET 9 API              ║
╚══════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "  Script dir  : $ScriptDir"
Write-Host "  Site        : $SiteName"
Write-Host "  App Pool    : $AppPoolName"
Write-Host "  Profile Dir : $ProfileDir"
Write-Host "  Install Dir : $InstallDir"
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1 – Tim file .exe LibreOffice cung thu muc voi script
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "1/6 - Tim file cai dat LibreOffice (.exe hoac .msi)"

$installerPath = Get-ChildItem -Path $ScriptDir -File |
                 Where-Object { $_.Name -match '^LibreOffice.*\.(exe|msi)$' } |
                 Sort-Object Name -Descending |
                 Select-Object -First 1 -ExpandProperty FullName

if (-not $installerPath) {
    Exit-Script "Khong tim thay file LibreOffice*.exe hoac LibreOffice*.msi trong '$ScriptDir'.`nHay tai ve va dat cung thu muc voi script nay."
}

$installerExt = [System.IO.Path]::GetExtension($installerPath).ToLower()
Write-OK "Tim thay: $installerPath ($installerExt)"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2 – Kiem tra LibreOffice da cai chua, neu chua thi cai
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "2/6 - Cai dat LibreOffice"

$soffice = Join-Path $InstallDir "program\soffice.exe"

if (Test-Path $soffice) {
    Write-Warn "LibreOffice da duoc cai dat tai: $InstallDir"
    Write-Warn "Bo qua buoc cai dat. Xoa thu muc neu muon cai lai."
}
else {
    Write-Host "  Dang cai dat (silent, vui long cho)..." -ForegroundColor White

    if ($installerExt -eq ".msi") {
        $msiLog = Join-Path $env:TEMP "libreoffice_install.log"
        $proc = Start-Process -FilePath "msiexec.exe" `
                              -ArgumentList "/i", "`"$installerPath`"", "/qn", "/norestart", "/l*v", "`"$msiLog`"" `
                              -PassThru -Wait
    }
    else {
        $proc = Start-Process -FilePath $installerPath `
                              -ArgumentList "/S", "/NCRC" `
                              -PassThru -Wait
    }

    if ($proc.ExitCode -notin @(0, 3010)) {
        Exit-Script "Cai dat that bai. Exit code: $($proc.ExitCode)"
    }

    if (-not (Test-Path $soffice)) {
        Exit-Script "Cai dat hoan tat nhung khong tim thay soffice.exe tai '$soffice'.`nKiem tra lai duong dan cai dat: $InstallDir"
    }

    Write-OK "Cai dat thanh cong: $soffice"
}

# Kiem tra version
try {
    $ver = & $soffice --version 2>&1
    Write-OK "Version: $ver"
}
catch {
    Write-Warn "Khong lay duoc version (co the bat dau chay duoc roi)."
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3 – Tao thu muc Profile va cap quyen
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "3/6 - Tao thu muc Profile va cap quyen"

if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    Write-OK "Da tao: $ProfileDir"
}
else {
    Write-OK "Thu muc da ton tai: $ProfileDir"
}

# Cap quyen cho cac account thuong dung voi IIS
$accounts = @(
    "IIS AppPool\$AppPoolName",
    "NETWORK SERVICE",
    "LOCAL SERVICE"
)

foreach ($account in $accounts) {
    try {
        $acl = Get-Acl $ProfileDir
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $account,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $ProfileDir -AclObject $acl
        Write-OK "Cap quyen FullControl cho: $account"
    }
    catch {
        Write-Warn "Khong cap duoc quyen cho '$account': $_"
    }
}

# Cap quyen cho thu muc Temp (LibreOffice can ghi temp files)
$tempLo = Join-Path $env:TEMP "lo_convert"
New-Item -ItemType Directory -Path $tempLo -Force | Out-Null
foreach ($account in $accounts) {
    try {
        $acl = Get-Acl $tempLo
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $account, "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $tempLo -AclObject $acl
    }
    catch { }
}
Write-OK "Da cap quyen thu muc temp: $tempLo"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4 – Them LibreOffice vao PATH (optional nhung tien)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "4/6 - Them LibreOffice vao System PATH"

$loProgram = Join-Path $InstallDir "program"
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

if ($currentPath -notlike "*$loProgram*") {
    [System.Environment]::SetEnvironmentVariable(
        "Path",
        "$currentPath;$loProgram",
        "Machine"
    )
    Write-OK "Da them vao PATH: $loProgram"
}
else {
    Write-OK "Da co trong PATH roi."
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5 – Cap nhat IIS App Pool: loadUserProfile = True
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "5/6 - Cap nhat IIS App Pool '$AppPoolName'"

# Kiem tra IIS / WebAdministration module
$iisAvailable = $false
try {
    Import-Module WebAdministration -ErrorAction Stop
    $iisAvailable = $true
}
catch {
    Write-Warn "Module WebAdministration khong co san. Se cap nhat applicationHost.config thu cong."
}

if ($iisAvailable) {
    $poolPath = "IIS:\AppPools\$AppPoolName"

    if (-not (Test-Path $poolPath)) {
        Write-Warn "App Pool '$AppPoolName' khong ton tai. Cac pool hien co:"
        Get-ChildItem "IIS:\AppPools" | Select-Object -ExpandProperty Name | ForEach-Object { Write-Host "    - $_" }
        Write-Warn "Bo qua buoc nay. Hay chay lai script voi -AppPoolName dung."
    }
    else {
        # Bat loadUserProfile
        Set-ItemProperty $poolPath -Name "processModel.loadUserProfile" -Value $true
        Write-OK "Da bat loadUserProfile = True cho pool '$AppPoolName'"

        # Xem ket qua
        $val = (Get-ItemProperty $poolPath -Name "processModel.loadUserProfile").Value
        Write-OK "Ket qua hien tai: loadUserProfile = $val"
    }
}
else {
    # Fallback: sua applicationHost.config bang XML
    $appHostConfig = "$env:SystemRoot\System32\inetsrv\config\applicationHost.config"

    if (Test-Path $appHostConfig) {
        # Backup truoc
        $backup = "$appHostConfig.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $appHostConfig $backup
        Write-OK "Da backup applicationHost.config -> $backup"

        [xml]$xml = Get-Content $appHostConfig
        $pools = $xml.SelectNodes("//applicationPools/add[@name='$AppPoolName']")

        if ($pools.Count -gt 0) {
            foreach ($pool in $pools) {
                $pm = $pool.SelectSingleNode("processModel")
                if ($pm -eq $null) {
                    $pm = $xml.CreateElement("processModel")
                    $pool.AppendChild($pm) | Out-Null
                }
                $pm.SetAttribute("loadUserProfile", "true")
            }
            $xml.Save($appHostConfig)
            Write-OK "Da cap nhat applicationHost.config"
        }
        else {
            Write-Warn "Khong tim thay App Pool '$AppPoolName' trong applicationHost.config"
        }
    }
    else {
        Write-Warn "Khong tim thay applicationHost.config. Bo qua."
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6 – Kiem tra nhanh (test convert)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "6/6 - Kiem tra convert thu"

$testDocx = Join-Path $env:TEMP "lo_test_$(Get-Date -Format 'HHmmss').docx"
$testOutDir = Join-Path $env:TEMP "lo_test_out"
New-Item -ItemType Directory -Path $testOutDir -Force | Out-Null

# Tao file .docx don gian bang vbscript
$vbs = @"
Dim oWord, oDoc
On Error Resume Next
Set oWord = CreateObject("Word.Application")
oWord.Visible = False
Set oDoc = oWord.Documents.Add
oDoc.Content.Text = "LibreOffice Test Document - OK"
oDoc.SaveAs2 "$($testDocx.Replace('\','\\'))", 16
oDoc.Close
oWord.Quit
"@

$vbsPath = Join-Path $env:TEMP "create_test.vbs"
Set-Content -Path $vbsPath -Value $vbs

# Thu tao docx bang Word (neu co), neu khong thi dung file gia
$wordOk = $false
try {
    & cscript //nologo $vbsPath 2>&1 | Out-Null
    if (Test-Path $testDocx) { $wordOk = $true }
}
catch { }

if (-not $wordOk) {
    # Tao file RTF nho de test
    $testDocx = Join-Path $env:TEMP "lo_test.rtf"
    Set-Content -Path $testDocx -Value "{\rtf1 LibreOffice Test OK}"
}

Write-Host "  Dang convert file test..." -ForegroundColor White

$profileTest = Join-Path $ProfileDir "test_$(Get-Date -Format 'HHmmss')"
New-Item -ItemType Directory -Path $profileTest -Force | Out-Null

try {
    $loArgs = @(
        "-env:UserInstallation=file:///$($profileTest.Replace('\','/').Replace(' ','%20'))",
        "--headless",
        "--norestore",
        "--nofirststartwizard",
        "--convert-to", "pdf",
        "--outdir", $testOutDir,
        $testDocx
    )

    $proc = Start-Process -FilePath $soffice -ArgumentList $loArgs `
                          -PassThru -Wait -NoNewWindow `
                          -RedirectStandardOutput (Join-Path $env:TEMP "lo_stdout.txt") `
                          -RedirectStandardError  (Join-Path $env:TEMP "lo_stderr.txt")

    $pdfName = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetFileName($testDocx), ".pdf")
    $pdfOut  = Join-Path $testOutDir $pdfName

    if (Test-Path $pdfOut) {
        $size = (Get-Item $pdfOut).Length
        Write-OK "Convert thanh cong! PDF: $pdfOut ($size bytes)"
    }
    else {
        $stderr = Get-Content (Join-Path $env:TEMP "lo_stderr.txt") -Raw -ErrorAction SilentlyContinue
        Write-Fail "Khong tim thay file PDF output."
        Write-Warn "STDERR: $stderr"
    }
}
catch {
    Write-Warn "Test convert gap loi: $_"
}
finally {
    Remove-Item $profileTest -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $vbsPath     -Force -ErrorAction SilentlyContinue
}

# ═══════════════════════════════════════════════════════════════════════════════
# TONG KET
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host @"

╔══════════════════════════════════════════════════════╗
║   SETUP HOAN TAT                                    ║
╚══════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

Write-Host "  soffice.exe  : $soffice"
Write-Host "  Profile Dir  : $ProfileDir"
Write-Host "  Them vao appsettings.json cua .NET API:"
Write-Host @"
  {
    "LibreOffice": {
      "ExecutablePath": "$($soffice.Replace('\','\\'))",
      "ProfileBaseDir": "$($ProfileDir.Replace('\','\\'))",
      "TimeoutSeconds": 60
    }
  }
"@ -ForegroundColor Yellow

Read-Host "`nNhan Enter de dong"
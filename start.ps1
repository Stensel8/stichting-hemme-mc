<#
.SYNOPSIS
  Simpel script om een PaperMC Minecraft server te downloaden en te starten.
#>

# =====================================================================
# Stichting Hemme Minecraft Server
# Stensel8, cdemmer04, Hintenhaus04, powercell86 & PrinsMayo

# GameServer-1   specs: i7-1360P   -> 4-core    | 10GB DDR5  | Fedora Server 42 (Hosted by Stensel8)
# =====================================================================

param (
    [string]$JarUrl = "https://fill-data.papermc.io/v1/objects/9f18e2527bd1c06fc843e8cfacea228ab9cff86f0eaeee87bf1afe10c3f426ed/paper-1.21.8-28.jar",
    [string]$JarHash = "9f18e2527bd1c06fc843e8cfacea228ab9cff86f0eaeee87bf1afe10c3f426ed",
    [string]$JarName = "minecraft-server.jar",
    [string]$Ram = "10G",
    [string]$DataDir = ".\server-data"
)

Clear-Host

function Get-MinecraftServer {
    Write-Host "[INFO] Downloaden van PaperMC..." -ForegroundColor Cyan

    if (!(Test-Path -Path $DataDir)) {
        New-Item -ItemType Directory -Path $DataDir | Out-Null
    }

    $JarPath = Join-Path $DataDir $JarName

    if (Test-Path -Path $JarPath) {
        Write-Host "[INFO] Serverbestand bestaat al." -ForegroundColor Yellow
    } else {
        Start-BitsTransfer -Source $JarUrl -Destination $JarPath
    }

    Write-Host "[INFO] Verifiëren van checksum..." -ForegroundColor Cyan
    $ActualHash = (Get-FileHash -Path $JarPath -Algorithm SHA256).Hash

    if ($ActualHash -ne $JarHash) {
        Write-Host "[ERROR] Checksum komt niet overeen! Bestandsintegriteit mislukt." -ForegroundColor Red
        Remove-Item -Path $JarPath
        exit 1
    }

    Write-Host "[OK] Download en verificatie succesvol." -ForegroundColor Green

    # EULA accepteren
    $EulaPath = Join-Path $DataDir "eula.txt"
    if (!(Test-Path -Path $EulaPath)) {
        "eula=true" | Out-File -FilePath $EulaPath -Encoding UTF8
        Write-Host "[INFO] EULA geaccepteerd." -ForegroundColor Green
    }
}

function Start-MinecraftServer {
    Write-Host "[INFO] Starten van Minecraft server..." -ForegroundColor Cyan

    Push-Location -Path $DataDir

    $JavaArgs = @(
        "-Xms$Ram"
        "-Xmx$Ram"
        "-jar"
        $JarName
        "nogui"
    )


    try {
        Start-Process -FilePath "java" -ArgumentList $JavaArgs -NoNewWindow -Wait
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Server gestart (loopt in deze Powershell sessie)." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Server niet gestart! Exit code: $LASTEXITCODE" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[ERROR] Server niet gestart! (Java probleem)." -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
}

# --- Script uitvoeren ---
Get-MinecraftServer
Start-MinecraftServer

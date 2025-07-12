<#
.SYNOPSIS
  Simpel script om een PaperMC Minecraft server te downloaden en te starten.
#>

# =====================================================================
# Stichting Hemme Minecraft Server
# Stensel8, cdemmer04, Hintenhaus04, powercell86 & PrinsMayo
# LoadBalancer-1 SPECS TO BE FILLED IN! NOT CONFIGURED YET!
# GameServer-1   specs: i7-1360P   -> 4-core    | 8GB DDR5  | Fedora Server 42 (Hosted by Stensel8)
# GameServer-2   specs: i7-12700H  -> 4-core    | 80GB DDR4  | Fedora Server 42 (Hosted by Hintenhaus04)
# =====================================================================

param (
    [string]$JarUrl = "https://fill-data.papermc.io/v1/objects/3c088d399dd3b83764653bee7c7c4f30b207fab7b97c4e4227bf96b853b2158a/paper-1.21.7-26.jar",
    [string]$JarHash = "3c088d399dd3b83764653bee7c7c4f30b207fab7b97c4e4227bf96b853b2158a",
    [string]$JarName = "minecraft-server.jar",
    [string]$Ram = "8G",
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

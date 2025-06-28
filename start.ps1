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
    [string]$JarUrl = "https://fill-data.papermc.io/v1/objects/bfca155b4a6b45644bfc1766f4e02a83c736e45fcc060e8788c71d6e7b3d56f6/paper-1.21.6-46.jar",
    [string]$JarHash = "bfca155b4a6b45644bfc1766f4e02a83c736e45fcc060e8788c71d6e7b3d56f6",
    [string]$JarName = "minecraft-server.jar",
    [string]$Ram = "4G",
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
        if ($Error -eq 0) {
            Write-Host "[OK] Server gestart (loopt in deze Powershell sessie)." -ForegroundColor Green
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

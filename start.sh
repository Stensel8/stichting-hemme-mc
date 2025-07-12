#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# Stichting Hemme Minecraft Server
# Stensel8, cdemmer04, Hintenhaus04, powercell86 & PrinsMayo
# LoadBalancer-1 SPECS TO BE FILLED IN! NOT CONFIGURED YET!
# GameServer-1   specs: i7-1360P   -> 4-core    | 8GB DDR5  | Fedora Server 42 (Hosted by Stensel8)
# GameServer-2   specs: i7-12700H  -> 4-core    | 80GB DDR4  | Fedora Server 42 (Hosted by Hintenhaus04)
# =====================================================================

# --------------------- PAKETTEN INSTALLEREN --------------------------
dnf install wget tmux java-21-openjdk -y


# --------------------- CONFIGURATIE ---------------------------------
SERVER_NAAM="stichting-hemme-mc"
DATA_DIR="./server-data"
JAR_URL="https://fill-data.papermc.io/v1/objects/3c088d399dd3b83764653bee7c7c4f30b207fab7b97c4e4227bf96b853b2158a/paper-1.21.7-26.jar"
JAR_HASH="3c088d399dd3b83764653bee7c7c4f30b207fab7b97c4e4227bf96b853b2158a"
JAR_NAAM="hemme-mc.jar"
RAM_TOEWIJZING="8G"
TMUX_SESSIE="hemme-mc"

# --------------------- FUNCTIES -------------------------------------

# Print gekleurd bericht
print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_succes() {
    echo -e "\033[1;32m[✓]\033[0m $1"
}

print_fout() {
    echo -e "\033[1;31m[✗]\033[0m $1"
}

# Download en verifieer het JAR bestand
download_paper() {
    local jar_path="$DATA_DIR/$JAR_NAAM"
    
    if [[ -f "$jar_path" ]]; then
        print_info "$JAR_NAAM is al gedownload. Checksum verifiëren..."
        local checksum
        checksum=$(sha256sum "$jar_path" | awk '{print $1}')
        
        if [[ "$checksum" == "$JAR_HASH" ]]; then
            print_succes "Checksum is geldig. Geen download nodig."
            return
        else
            print_fout "Checksum komt niet overeen! Bestand opnieuw downloaden..."
            rm -f "$jar_path"
        fi
    fi
    
    print_info "PaperMC downloaden..."
    wget -q --show-progress -O "$jar_path" "$JAR_URL"
    
    print_info "Checksum verifiëren..."
    local checksum
    checksum=$(sha256sum "$jar_path" | awk '{print $1}')
    
    if [[ "$checksum" != "$JAR_HASH" ]]; then
        print_fout "Checksum komt niet overeen! Download is mogelijk corrupt."
        rm -f "$jar_path"
        exit 1
    fi
    
    print_succes "Download en verificatie succesvol!"
}

# Configureer tmux voor betere gebruikservaring
configureer_tmux() {
    local tmux_conf="$HOME/.tmux.conf"
    local marker="set -g mouse on"
    
    if [[ -f "$tmux_conf" ]] && grep -qF "$marker" "$tmux_conf"; then
        return
    fi
    
    print_info "Tmux configureren voor muis-ondersteuning..."
    echo -e "\n# Stichting Hemme MC - tmux configuratie\n$marker" >> "$tmux_conf"
    print_succes "Tmux geconfigureerd!"
}

# Maak optimale Java opstart parameters
genereer_java_cmd() {
    # Optimalisaties voor high-performance server met 10GB RAM
    JAVA_CMD=(
        java
        -Xms"$RAM_TOEWIJZING"          # Start met toegewezen begin RAM
        -Xmx"$RAM_TOEWIJZING"          # Maximum RAM
        
        # G1GC optimalisaties voor prestaties
        -XX:+UseG1GC
        -XX:+ParallelRefProcEnabled
        -XX:MaxGCPauseMillis=200
        -XX:+UnlockExperimentalVMOptions
        -XX:+DisableExplicitGC
        -XX:+AlwaysPreTouch
        -XX:G1HeapRegionSize=16M
        -XX:G1ReservePercent=15
        -XX:G1NewSizePercent=30
        -XX:G1MaxNewSizePercent=40
        -XX:G1HeapWastePercent=5
        -XX:G1MixedGCCountTarget=4
        -XX:InitiatingHeapOccupancyPercent=20
        -XX:G1MixedGCLiveThresholdPercent=90
        -XX:G1RSetUpdatingPauseTimePercent=5
        -XX:SurvivorRatio=32
        -XX:+PerfDisableSharedMem
        -XX:MaxTenuringThreshold=1
        
        # Extra optimalisaties
        -XX:+UseStringDeduplication
        -XX:+UseCompressedOops
        -XX:+OptimizeStringConcat
        --add-modules=jdk.incubator.vector
        
        # PaperMC specifiek
        -Dpaper.maxChunkThreads=6 
        -jar "$JAR_NAAM"
        nogui
    )
}

# Start de server in tmux
start_server() {
    # Controleer of tmux beschikbaar is
    if ! command -v tmux &>/dev/null; then
        print_fout "tmux is niet geïnstalleerd!"
        echo "Installeer eerst tmux met:"
        echo "  sudo dnf install tmux"
        exit 1
    fi

    if tmux has-session -t "$TMUX_SESSIE" 2>/dev/null; then
        print_info "Er draait al een server in tmux sessie '$TMUX_SESSIE'"
        read -rp "Wil je naar de bestaande sessie verbinden? (j/n) " antwoord
        
        if [[ "$antwoord" =~ ^[Jj]$ ]]; then
            tmux attach -t "$TMUX_SESSIE"
            exit 0
        else
            print_info "Server blijft draaien in de achtergrond."
            exit 0
        fi
    fi
    
    print_info "Server starten in tmux sessie '$TMUX_SESSIE'..."
    print_info "Working directory: $(pwd)/$DATA_DIR"
    
    # Start tmux in de server directory
    tmux new-session -d -s "$TMUX_SESSIE" -c "$DATA_DIR" "${JAVA_CMD[@]}"
    
    sleep 3
    
    if tmux has-session -t "$TMUX_SESSIE" 2>/dev/null; then
        print_succes "Server is gestart! 🎮"
        echo ""
        echo "----------------------------------------"
        echo "  Verbind met: tmux attach -t $TMUX_SESSIE"
        echo "  Loskoppelen: Ctrl+B gevolgd door D"
        echo "  Status check: tmux ls"
        echo "----------------------------------------"
        echo ""
        print_info "Server draait nu in de achtergrond."
        print_info "Als de server direct stopt, controleer dan de logs met: tmux attach -t $TMUX_SESSIE"
    else
        print_fout "Kon de tmux sessie niet starten."
        print_info "Probeer handmatig: cd $DATA_DIR && java -jar $JAR_NAAM nogui"
        exit 1
    fi
}

# --------------------- Main script -------------------------------

clear
echo "╔════════════════════════════════════════════╗"
echo "║   Stichting Hemme Minecraft Server 2025    ║"
echo "║         Powered by PaperMC 1.21.7          ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Controleer of Java geïnstalleerd is
if ! command -v java &>/dev/null; then
    print_fout "Java is niet geïnstalleerd!"
    echo "Installeer eerst Java 21 of hoger met:"
    echo "  sudo dnf install java-21-openjdk"
    exit 1
fi

# Toon Java versie
JAVA_VERSION=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
print_info "Java versie: $JAVA_VERSION"

# Maak server directory
mkdir -p "$DATA_DIR"

# Download PaperMC (nu dat directory bestaat)
download_paper

# Ga naar server directory voor de rest van de operaties
cd "$DATA_DIR"

# Accepteer EULA automatisch (voor eerste keer)
if [[ ! -f "eula.txt" ]] || ! grep -q "eula=true" "eula.txt" 2>/dev/null; then
    print_info "EULA accepteren..."
    echo "eula=true" > eula.txt
    print_succes "EULA geaccepteerd!"
fi

# Configureer tmux
configureer_tmux

# Genereer Java commando
genereer_java_cmd

# Toon server informatie
echo ""
print_info "Server configuratie:"
echo "  • RAM toewijzing: $RAM_TOEWIJZING"
echo "  • CPU cores: 4"
echo "  • Server type: PaperMC 1.21.7"
echo "  • Data directory: $DATA_DIR"
echo "  • JAR bestand: $JAR_NAAM"
echo "  • EULA status: $(if [[ -f "eula.txt" ]] && grep -q "eula=true" "eula.txt"; then echo "✓ Geaccepteerd"; else echo "✗ Niet gevonden"; fi)"
echo ""

# Controleer of alle bestanden kloppen voordat we starten
if [[ ! -f "$JAR_NAAM" ]]; then
    print_fout "JAR bestand niet gevonden in $(pwd)/$JAR_NAAM"
    exit 1
fi

if [[ ! -f "eula.txt" ]] || ! grep -q "eula=true" "eula.txt"; then
    print_fout "EULA niet correct ingesteld in $(pwd)/eula.txt"
    exit 1
fi

# Start de server
start_server

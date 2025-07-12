#!/usr/bin/env bash
set -euo pipefail

# Stichting Hemme MC Server - Optimized for modern hardware (2021+)
# Target: i7-1360P, Ryzen 6800H+ etc. etc. with +-10GB RAM allocation

# =====================================================================
# Stensel8, cdemmer04, Hintenhaus04, powercell86 & PrinsMayo
#
# GameServer-1   specs: i7-1360P      | 10GB DDR5  | Fedora Server 42 (Hosted by Stensel8)
# =====================================================================

# Config
readonly JAVA_VERSION="21.0.1-tem"
readonly DATA_DIR="./server-data"
readonly JAR_URL="https://api.papermc.io/v2/projects/paper/versions/1.21.7/builds/26/downloads/paper-1.21.7-26.jar"
readonly JAR_HASH="3c088d399dd3b83764653bee7c7c4f30b207fab7b97c4e4227bf96b853b2158a"
readonly JAR_NAME="hemme-mc.jar"
readonly RAM="10G"
readonly SESSION="hemme-mc"

# Colors
info() { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[✓]\033[0m $1"; }
error() { echo -e "\033[31m[✗]\033[0m $1"; }

# Install dependencies
command -v wget tmux java >/dev/null 2>&1 || {
    info "Installing dependencies..."
    dnf install -y wget tmux
}

# Setup Java via SDKMAN
setup_java() {
    if [[ ! -f "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        info "Installing SDKMAN..."
        curl -s "https://get.sdkman.io" | bash
    fi
    
    set +u
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    
    [[ ! -d "$HOME/.sdkman/candidates/java/$JAVA_VERSION" ]] && {
        info "Installing Java $JAVA_VERSION..."
        sdk install java "$JAVA_VERSION"
    }
    
    sdk use java "$JAVA_VERSION"
    export PATH="$HOME/.sdkman/candidates/java/$JAVA_VERSION/bin:$PATH"
    export JAVA_HOME="$HOME/.sdkman/candidates/java/$JAVA_VERSION"
    set -u
    
    success "Java $JAVA_VERSION ready"
}

# Download and verify JAR
download_jar() {
    local jar_path="$DATA_DIR/$JAR_NAME"
    
    [[ -f "$jar_path" ]] && {
        local checksum=$(sha256sum "$jar_path" | cut -d' ' -f1)
        [[ "$checksum" == "$JAR_HASH" ]] && {
            success "JAR verified, skipping download"
            return
        }
        info "Checksum mismatch, re-downloading..."
        rm -f "$jar_path"
    }
    
    info "Downloading PaperMC..."
    wget -q --show-progress -O "$jar_path" "$JAR_URL"
    
    local checksum=$(sha256sum "$jar_path" | cut -d' ' -f1)
    [[ "$checksum" != "$JAR_HASH" ]] && {
        error "Download corrupted!"
        rm -f "$jar_path"
        exit 1
    }
    
    success "Download verified"
}

# Generate optimized Java command for modern hardware
build_java_cmd() {
    local cores=$(nproc)
    local gc_threads=$((cores > 4 ? cores / 2 : 2))
    
    # Detect ZGC support
    if java -XX:+UnlockExperimentalVMOptions -XX:+UseZGC -version &>/dev/null; then
        info "Using ZGC (ultra-low latency GC)"
        JAVA_ARGS=(
            -XX:+UnlockExperimentalVMOptions -XX:+UseZGC
            -XX:+UnlockDiagnosticVMOptions
        )
    else
        info "Using optimized G1GC"
        JAVA_ARGS=(
            -XX:+UseG1GC -XX:+ParallelRefProcEnabled
            -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M
            -XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=50
            -XX:InitiatingHeapOccupancyPercent=15
            -XX:ConcGCThreads="$gc_threads"
        )
    fi
    
    # Core JVM args optimized for modern hardware
    JAVA_CMD=(
        java -server -Xms"$RAM" -Xmx"$RAM"
        "${JAVA_ARGS[@]}"
        -XX:+AlwaysPreTouch -XX:+UseCompressedOops
        -XX:+UseFastUnorderedTimeStamps -XX:+TieredCompilation
        -Djava.net.preferIPv4Stack=true -Djava.awt.headless=true
        -Dpaper.maxChunkThreads="$((cores - 2))"
        -jar "./$JAR_NAME" nogui
    )
}

# Fix permissions for server data directory
fix_permissions() {
    info "Fixing permissions for server data directory..."
    
    # Get current user
    local current_user=$(whoami)
    
    # Change ownership of the entire server-data directory to current user
    if [[ -d "$DATA_DIR" ]]; then
        sudo chown -R "$current_user:$current_user" "$DATA_DIR" 2>/dev/null || {
            # If sudo fails, try without it (might already be correct owner)
            chown -R "$current_user:$current_user" "$DATA_DIR" 2>/dev/null || true
        }
        
        # Set proper permissions:
        # - Directories: 755 (rwxr-xr-x)
        # - Files: 644 (rw-r--r--)
        # - JAR file: 755 (rwxr-xr-x) to ensure it's executable
        find "$DATA_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$DATA_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
        [[ -f "$DATA_DIR/$JAR_NAME" ]] && chmod 755 "$DATA_DIR/$JAR_NAME" 2>/dev/null || true
        
        # Ensure logs directory exists and is writable
        mkdir -p "$DATA_DIR/logs" 2>/dev/null || true
        chmod 755 "$DATA_DIR/logs" 2>/dev/null || true
        
        # Remove any existing lock files that might cause issues
        [[ -f "$DATA_DIR/world/session.lock" ]] && rm -f "$DATA_DIR/world/session.lock" 2>/dev/null || true
        
        success "Permissions fixed for server data directory"
    else
        info "Server data directory doesn't exist yet, permissions will be set after creation"
    fi
}

# Start server in tmux
start_server() {
    tmux has-session -t "$SESSION" 2>/dev/null && {
        info "Server already running in session '$SESSION'"
        read -rp "Connect to existing session? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] && exec tmux attach -t "$SESSION"
        exit 0
    }
    
    info "Starting server in tmux session '$SESSION'..."
    info "Working directory: $(pwd)"
    info "Java command: ${JAVA_CMD[*]}"
    
    # Configure tmux mouse support
    grep -q "set -g mouse on" "$HOME/.tmux.conf" 2>/dev/null || 
        echo "set -g mouse on" >> "$HOME/.tmux.conf"
    
    # Create tmux session in the current directory (should be $DATA_DIR)
    tmux new-session -d -s "$SESSION" -c "$(pwd)" "${JAVA_CMD[@]}"
    sleep 3
    
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        success "Server started!"
        echo "Connect: tmux attach -t $SESSION"
        echo "Detach: Ctrl+B then D"
        echo "List sessions: tmux ls"
    else
        error "Failed to start tmux session"
        info "Checking if tmux server is running..."
        tmux list-sessions 2>/dev/null || echo "No tmux server running"
        exit 1
    fi
}

# Main execution
main() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║    Stichting Hemme MC Server 2025    ║"
    echo "║       PaperMC 1.21.7 • 10GB RAM     ║"
    echo "╚══════════════════════════════════════╝"
    
    setup_java
    
    mkdir -p "$DATA_DIR"
    download_jar
    
    cd "$DATA_DIR"
    
    # Fix permissions before starting server
    fix_permissions
    
    # Accept EULA
    [[ ! -f "eula.txt" || ! $(grep -q "eula=true" "eula.txt" 2>/dev/null) ]] && {
        info "Accepting EULA..."
        echo "eula=true" > eula.txt
    }
    
    # Build Java command in the correct directory
    build_java_cmd
    
    info "Configuration:"
    echo "  • RAM: $RAM"
    echo "  • CPU cores: $(nproc)"
    echo "  • Java: $(java -version 2>&1 | head -n1 | cut -d'"' -f2)"
    echo "  • Data dir: $DATA_DIR"
    echo
    
    fix_permissions
    start_server
}

main "$@"

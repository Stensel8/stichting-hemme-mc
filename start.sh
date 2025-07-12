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
    local force_restart="${1:-false}"
    
    # Kill any existing session more thoroughly
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        info "Existing session '$SESSION' found, stopping gracefully..."
        
        # Try to send stop command first
        tmux send-keys -t "$SESSION" 'stop' Enter 2>/dev/null || true
        sleep 5
        
        # Force kill the session
        tmux kill-session -t "$SESSION" 2>/dev/null || true
        sleep 3
        
        # Ensure session is completely gone
        for i in {1..10}; do
            if ! tmux has-session -t "$SESSION" 2>/dev/null; then
                break
            fi
            sleep 1
        done
    fi
    
    # Ensure tmux server is running
    if ! tmux list-sessions >/dev/null 2>&1; then
        info "Starting tmux server..."
        tmux new-session -d -s temp-session 'echo "tmux server started"; sleep 1' || {
            error "Failed to start tmux server"
            exit 1
        }
        tmux kill-session -t temp-session 2>/dev/null || true
    fi
    
    info "Starting server in tmux session '$SESSION'..."
    info "Working directory: $(pwd)"
    info "Java command: ${JAVA_CMD[*]}"
    
    # Configure tmux mouse support
    grep -q "set -g mouse on" "$HOME/.tmux.conf" 2>/dev/null || 
        echo "set -g mouse on" >> "$HOME/.tmux.conf"
    
    # Source environment properly in tmux session
    local tmux_command=""
    if [[ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        tmux_command="source '$HOME/.sdkman/bin/sdkman-init.sh'; sdk use java '$JAVA_VERSION'; "
    fi
    tmux_command+="cd '$(pwd)'; ${JAVA_CMD[*]}"
    
    # Create tmux session with better error handling
    if ! tmux new-session -d -s "$SESSION" -c "$(pwd)" "$tmux_command"; then
        error "Failed to create tmux session with Java command"
        
        # Try fallback method: create session first, then send commands
        info "Trying fallback startup method..."
        if tmux new-session -d -s "$SESSION" -c "$(pwd)"; then
            sleep 1
            
            # Source SDKMAN if available
            if [[ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
                tmux send-keys -t "$SESSION" "source '$HOME/.sdkman/bin/sdkman-init.sh'" Enter
                sleep 1
                tmux send-keys -t "$SESSION" "sdk use java '$JAVA_VERSION'" Enter
                sleep 1
            fi
            
            # Start the server
            tmux send-keys -t "$SESSION" "${JAVA_CMD[*]}" Enter
        else
            error "Both primary and fallback tmux session creation failed"
            exit 1
        fi
    fi
    
    # Verify session was created and is active
    sleep 5
    local retries=0
    while [[ $retries -lt 10 ]]; do
        if tmux has-session -t "$SESSION" 2>/dev/null; then
            # Check if session has content (not just empty)
            local session_content=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || echo "")
            if [[ -n "$session_content" ]]; then
                success "Server started!"
                echo "Session content preview:"
                echo "$session_content" | tail -3 | sed 's/^/  /'
                echo
                echo "Connect: tmux attach -t $SESSION"
                echo "Detach: Ctrl+B then D"
                echo "List sessions: tmux ls"
                return 0
            fi
        fi
        
        retries=$((retries + 1))
        info "Waiting for session to become active... ($retries/10)"
        sleep 2
    done
    
    error "Failed to start tmux session or session appears empty"
    info "Debugging information:"
    echo "  Tmux sessions:"
    tmux list-sessions 2>/dev/null || echo "    No tmux sessions"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "  Session exists but may be empty or crashed"
        local content=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || echo "No content")
        echo "  Last 10 lines of session:"
        echo "$content" | tail -10 | sed 's/^/    /'
    fi
    exit 1
}

# Main execution
main() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║    Stichting Hemme MC Server 2025    ║"
    echo "║       PaperMC 1.21.7 • 10GB RAM      ║"
    echo "╚══════════════════════════════════════╝"
    
    # Ensure we're in the script's directory
    cd "$(dirname "${BASH_SOURCE[0]}")"
    info "Script directory: $(pwd)"
    
    setup_java
    
    mkdir -p "$DATA_DIR"
    download_jar
    
    # Change to data directory for server execution
    cd "$DATA_DIR"
    info "Server data directory: $(pwd)"
    
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
    echo "  • Working dir: $(pwd)"
    echo "  • Java home: ${JAVA_HOME:-not set}"
    echo "  • Tmux version: $(tmux -V 2>/dev/null || echo 'not found')"
    echo
    
    # Final permission fix and cleanup
    fix_permissions
    
    # Ensure no conflicting processes
    info "Checking for existing Java processes..."
    local existing_java=$(pgrep -f "hemme-mc.jar" || echo "")
    if [[ -n "$existing_java" ]]; then
        info "Found existing Java process(es): $existing_java"
        info "Stopping existing processes..."
        pkill -f "hemme-mc.jar" || true
        sleep 3
    fi
    
    start_server
}

main "$@"

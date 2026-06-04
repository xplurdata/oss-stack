#!/usr/bin/env bash
# =============================================================
# XD-oss-stack — One-line installer
# Supports: Linux, macOS, WSL2
# =============================================================

set -e

REGISTRY="ghcr.io/xplurdata"
INSTALL_DIR="${INSTALL_DIR:-$HOME/xd-oss-stack}"
VERSION="1.0.0"

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── TTY ───────────────────────────────────────────────────────
IS_TTY=false
[ -t 1 ] && IS_TTY=true

cleanup_terminal() { tput cnorm 2>/dev/null || true; }
trap cleanup_terminal EXIT

# ── Helpers ───────────────────────────────────────────────────
divider() { echo -e "  ${DIM}${CYAN}─────────────────────────────────────────────────────${NC}"; }
step()    { echo ""; echo -e "  ${BOLD}${MAGENTA}▶  $1${NC}"; divider; }
info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "\n  ${RED}✗${NC}  $1"; exit 1; }

# ── Banner ────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}  ╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}  ║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}  ║   ${WHITE}██╗  ██╗██████╗      ██████╗ ███████╗███████╗${CYAN}      ║${NC}"
    echo -e "${BOLD}${CYAN}  ║   ${WHITE}╚██╗██╔╝██╔══██╗    ██╔═══██╗██╔════╝██╔════╝${CYAN}      ║${NC}"
    echo -e "${BOLD}${CYAN}  ║   ${WHITE} ╚███╔╝ ██║  ██║    ██║   ██║███████╗███████╗${CYAN}      ║${NC}"
    echo -e "${BOLD}${CYAN}  ║   ${WHITE} ██╔██╗ ██║  ██║    ██║   ██║╚════██║╚════██║${CYAN}      ║${NC}"
    echo -e "${BOLD}${CYAN}  ║   ${WHITE}██╔╝ ██╗██████╔╝    ╚██████╔╝███████║███████║${CYAN}      ║${NC}"
    echo -e "${BOLD}${CYAN}  ║   ${WHITE}╚═╝  ╚═╝╚═════╝      ╚═════╝ ╚══════╝╚══════╝${CYAN}      ║${NC}"
    echo -e "${BOLD}${CYAN}  ║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}  ║        ${WHITE}Observability Stack Installer v${VERSION}${CYAN}         ║${NC}"
    echo -e "${BOLD}${CYAN}  ║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}  ╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Spinner ───────────────────────────────────────────────────
spinner() {
    local pid=$1
    local label="$2"
    local delay=0.10
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    if $IS_TTY; then tput civis 2>/dev/null || true; fi
    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spin}; i++ )); do
            printf "\r  ${CYAN}%s${NC}  ${BOLD}%s${NC} ${DIM}working...${NC}" \
                "${spin:$i:1}" "$label" > /dev/tty
            sleep "$delay"
            kill -0 "$pid" 2>/dev/null || break
        done
    done
    printf "\r%-80s\r" " " > /dev/tty
    if $IS_TTY; then tput cnorm 2>/dev/null || true; fi
}

# ── Health wait ───────────────────────────────────────────────
wait_healthy() {
    local container="$1"
    local label="$2"
    local start=$SECONDS
    local last_elapsed=-1

    echo -e "  ${CYAN}⟳${NC}  ${BOLD}$(printf '%-30s' "$label")${NC} ${DIM}waiting...${NC}"

    while true; do
        local elapsed=$(( SECONDS - start ))
        local status
        status=$($DOCKER_CMD inspect "$container" \
            --format="{{.State.Health.Status}}" 2>/dev/null || echo "starting")

        if [ "$status" = "healthy" ]; then
            echo -e "  ${GREEN}✓${NC}  ${BOLD}$(printf '%-30s' "$label")${NC} ${GREEN}healthy${NC} ${DIM}(${elapsed}s)${NC}"
            break
        fi

        if [ $(( elapsed % 15 )) -eq 0 ] && [ "$elapsed" -ne "$last_elapsed" ] && [ "$elapsed" -gt 0 ]; then
            echo -e "  ${CYAN}⟳${NC}  ${BOLD}$(printf '%-30s' "$label")${NC} ${DIM}${elapsed}s elapsed...${NC}"
            last_elapsed=$elapsed
        fi
        sleep 3
    done
}

print_banner

# ── OS Detection ──────────────────────────────────────────────
step "Detecting system"

OS="linux"
if [[ "$OSTYPE" == darwin* ]]; then
    OS="macos"
elif grep -qi microsoft /proc/version 2>/dev/null; then
    OS="wsl"
fi

case "$OS" in
    linux)  success "OS: Linux" ;;
    macos)  success "OS: macOS" ;;
    wsl)    success "OS: Linux (WSL2)" ;;
esac

# ── Docker ────────────────────────────────────────────────────
DOCKER_CMD="docker"
COMPOSE_CMD="docker compose"

if ! command -v docker &>/dev/null; then
    if [[ "$OS" == "macos" ]]; then
        error "Docker Desktop not found. Install from: https://docs.docker.com/desktop/install/mac-install/"
    fi
    warn "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER" || true
    DOCKER_CMD="sudo docker"
    COMPOSE_CMD="sudo docker compose"
    success "Docker installed"
elif ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
        COMPOSE_CMD="sudo docker compose"
    elif [[ "$OS" == "macos" ]]; then
        error "Docker Desktop is not running. Please start Docker Desktop and try again."
    else
        sudo systemctl start docker 2>/dev/null || true
        sleep 3
        docker info >/dev/null 2>&1 || { DOCKER_CMD="sudo docker"; COMPOSE_CMD="sudo docker compose"; }
    fi
fi

if ! $DOCKER_CMD compose version >/dev/null 2>&1; then
    warn "Docker Compose v2 not found. Installing..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq docker-compose-plugin
    elif command -v yum &>/dev/null; then
        sudo yum install -y docker-compose-plugin 2>/dev/null || true
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y docker-compose-plugin 2>/dev/null || true
    else
        error "Docker Compose v2 not found. Install from: https://docs.docker.com/compose/install/"
    fi
fi

success "Docker: $($DOCKER_CMD --version | awk '{print $3}' | tr -d ',')"
success "Docker Compose: $($COMPOSE_CMD version --short)"

# ── System requirements ───────────────────────────────────────
step "Checking system requirements"

CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)
if [ "$CPU_CORES" -ge 4 ]; then
    success "CPU: ${CPU_CORES} cores"
else
    warn "CPU: ${CPU_CORES} cores — recommended: 4+"
fi

if [[ "$OS" == "macos" ]]; then
    TOTAL_RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    FREE_RAM_GB=$(( $(vm_stat | grep "^Pages free" | awk '{print $3}' | tr -d '.') * 4096 / 1073741824 ))
else
    TOTAL_RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1048576 ))
    FREE_RAM_GB=$(( $(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1048576 ))
fi

success "RAM: ${TOTAL_RAM_GB} GB total / ${FREE_RAM_GB} GB available"

if [ "$TOTAL_RAM_GB" -lt 4 ]; then
    warn "Only ${TOTAL_RAM_GB} GB RAM — minimum 4 GB required"
    echo -ne "  ${CYAN}?${NC}  Continue anyway? [y/N] "
    read -r resp < /dev/tty
    [[ "$resp" =~ ^[Yy]$ ]] || error "Aborted."
elif [ "$TOTAL_RAM_GB" -lt 8 ]; then
    warn "RAM: ${TOTAL_RAM_GB} GB — 8 GB recommended. Reduced JVM settings will be applied."
fi

# Set JVM based on available RAM — minimum floor is always 1g/512m
if [ "$TOTAL_RAM_GB" -ge 8 ] && [ "$FREE_RAM_GB" -ge 4 ]; then
    FE_JVM_OPTS=""
    BE_MEM_LIMIT="3500m"
    FE_MEM_LIMIT="4g"
    success "Memory OK — using default JVM settings (FE: 2GB heap)"
elif [ "$TOTAL_RAM_GB" -ge 6 ] || [ "$FREE_RAM_GB" -ge 3 ]; then
    FE_JVM_OPTS="-Xmx1g -Xms512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -Djava.net.preferIPv4Stack=true"
    BE_MEM_LIMIT="2g"
    FE_MEM_LIMIT="2g"
    warn "Low memory detected — applying reduced JVM settings (FE: 1GB heap)"
else
    # Absolute minimum — Doris needs at least 1g to start
    FE_JVM_OPTS="-Xmx1g -Xms512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -Djava.net.preferIPv4Stack=true"
    BE_MEM_LIMIT="1500m"
    FE_MEM_LIMIT="1500m"
    warn "Very low memory — applying minimum JVM settings (FE: 1GB heap)"
    warn "Performance may be degraded. Closing other applications is recommended."
fi

FREE_DISK_GB=$(( $(df -k "$HOME" | tail -1 | awk '{print $4}') / 1048576 ))
if [ "$FREE_DISK_GB" -ge 20 ]; then
    success "Disk: ${FREE_DISK_GB} GB free"
else
    warn "Disk: ${FREE_DISK_GB} GB free — minimum 20 GB recommended"
    echo -ne "  ${CYAN}?${NC}  Continue anyway? [y/N] "
    read -r resp < /dev/tty
    [[ "$resp" =~ ^[Yy]$ ]] || error "Aborted."
fi

# vm.max_map_count — required by Doris BE
if [[ "$OS" != "macos" ]]; then
    CURRENT_MAP_COUNT=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
    if [ "$CURRENT_MAP_COUNT" -le 2000000 ]; then
        warn "vm.max_map_count is ${CURRENT_MAP_COUNT} — Doris BE requires > 2000000"
        info "Setting vm.max_map_count=2000001..."
        sudo sysctl -w vm.max_map_count=2000001 >/dev/null 2>&1 || true
        # Make it permanent
        if ! grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
            echo "vm.max_map_count=2000001" | sudo tee -a /etc/sysctl.conf >/dev/null 2>&1 || true
        fi
        success "vm.max_map_count set to 2000001 (persisted)"
    else
        success "vm.max_map_count: ${CURRENT_MAP_COUNT}"
    fi
fi

check_port() {
    local port="$1"
    local required="$2"
    local in_use=false
    if command -v ss &>/dev/null && ss -tlnH 2>/dev/null | grep -q ":${port} "; then
        in_use=true
    elif command -v lsof &>/dev/null && lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | grep -q .; then
        in_use=true
    fi
    if $in_use; then
        warn "Port ${port} is already in use"
        if [ "$required" = "true" ]; then
            info "Port ${port} is required. Find what is using it:"
            info "  sudo lsof -i :${port}"
            info "Stop the conflicting process then re-run the installer."
            echo -ne "  ${CYAN}?${NC}  Continue anyway? [y/N] "
            read -r port_resp < /dev/tty
            [[ "$port_resp" =~ ^[Yy]$ ]] || error "Aborted — port ${port} is in use."
        fi
    else
        success "Port ${port}: available"
    fi
}
check_port 80   true
check_port 4318 true

# ── Configuration ─────────────────────────────────────────────
step "Configuration"
echo ""

if [[ "$OS" == "macos" ]] || [[ "$OS" == "wsl" ]]; then
    DEFAULT_DATA_DIR="$HOME/.xd-oss-stack/data"
else
    DEFAULT_DATA_DIR="/var/lib/xd-oss-stack"
fi

echo -e "  Where should Doris store its data? (Survives reinstalls)"
echo -ne "  ${CYAN}?${NC}  Data directory [${DEFAULT_DATA_DIR}]: "
read -r DATA_DIR < /dev/tty
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
success "Data directory: $DATA_DIR"

mkdir -p "$DATA_DIR/doris-fe" "$DATA_DIR/doris-be" "$DATA_DIR/app" 2>/dev/null || \
    sudo mkdir -p "$DATA_DIR/doris-fe" "$DATA_DIR/doris-be" "$DATA_DIR/app"
chmod -R 777 "$DATA_DIR" 2>/dev/null || sudo chmod -R 777 "$DATA_DIR"
success "Data directories created"

echo ""
echo -e "  Installation summary:"
echo -e "  ${CYAN}│${NC}  Install dir : $INSTALL_DIR"
echo -e "  ${CYAN}│${NC}  Data dir    : $DATA_DIR"
echo -e "  ${CYAN}│${NC}  UI port     : 80"
echo -e "  ${CYAN}│${NC}  OTLP port   : 4318"
echo -e "  ${CYAN}│${NC}  FE JVM      : ${FE_JVM_OPTS:-default (2GB)}"
echo ""
echo -ne "  ${CYAN}?${NC}  Confirm installation? [Y/n]: "
read -r confirm < /dev/tty
confirm="${confirm:-Y}"
[[ "$confirm" =~ ^[Yy]$ ]] || error "Installation cancelled."

# ── Write config ──────────────────────────────────────────────
step "Writing configuration"

if $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" ps 2>/dev/null | grep -qE "Up|running"; then
    warn "Existing stack detected — cleaning up..."
    $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" down -v 2>/dev/null || true
    success "Existing stack removed"
fi

for net in xd-oss-stack_otel-net otel-doris-stack_otel-net; do
    if $DOCKER_CMD network ls --format "{{.Name}}" 2>/dev/null | grep -q "^${net}$"; then
        warn "Removing existing network: $net"
        $DOCKER_CMD network rm "$net" 2>/dev/null || true
    fi
done

mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"

if [ -n "$FE_JVM_OPTS" ]; then
    FE_ENV_BLOCK="    environment:
      - FE_SERVERS=fe1:172.28.0.10:9010
      - FE_ID=1
      - JAVA_OPTS_FOR_JDK_17=${FE_JVM_OPTS}"
else
    FE_ENV_BLOCK="    environment:
      - FE_SERVERS=fe1:172.28.0.10:9010
      - FE_ID=1"
fi

cat > "$INSTALL_DIR/docker-compose.yml" << COMPOSE
networks:
  otel-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/24

volumes:
  app-duckdb:

services:
  doris-fe:
    image: ${REGISTRY}/oss-stack-fe:1.0.0
    container_name: otel-doris-fe
    networks:
      otel-net:
        ipv4_address: 172.28.0.10
    ports:
      - "8030:8030"
      - "9030:9030"
      - "9020:9020"
      - "9010:9010"
    volumes:
      - ${DATA_DIR}/doris-fe:/opt/apache-doris/fe/doris-meta
${FE_ENV_BLOCK}
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8030/api/bootstrap | grep -q success || exit 1"]
      interval: 15s
      timeout: 10s
      start_period: 90s
      retries: 10
    restart: unless-stopped
    mem_limit: ${FE_MEM_LIMIT}
    cpus: '1.0'

  doris-be:
    image: ${REGISTRY}/oss-stack-be:1.0.0
    container_name: otel-doris-be
    entrypoint: ["bash", "/opt/xd/be-entrypoint.sh"]
    ulimits:
      nofile:
        soft: 655350
        hard: 655350
    networks:
      otel-net:
        ipv4_address: 172.28.0.11
    ports:
      - "8040:8040"
      - "8060:8060"
      - "9050:9050"
      - "9060:9060"
    volumes:
      - ${DATA_DIR}/doris-be:/opt/apache-doris/be/storage.HDD
      - ${INSTALL_DIR}/be-entrypoint.sh:/opt/xd/be-entrypoint.sh:ro
    environment:
      - FE_SERVERS=fe1:172.28.0.10:9010
      - BE_ADDR=172.28.0.11:9050
    depends_on:
      doris-fe:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8040/api/health | grep -q OK || exit 1"]
      interval: 15s
      timeout: 10s
      start_period: 120s
      retries: 10
    restart: unless-stopped
    mem_limit: ${BE_MEM_LIMIT}
    cpus: '1.5'

  app:
    image: ${REGISTRY}/oss-stack-app:1.0.0
    container_name: otel-app
    networks:
      otel-net:
        ipv4_address: 172.28.0.13
    ports:
      - "80:80"
    volumes:
      - app-duckdb:/data
    depends_on:
      - doris-be
    healthcheck:
      test: ["CMD", "/opt/venv/bin/python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost/health')"]
      interval: 15s
      timeout: 10s
      start_period: 30s
      retries: 40
    restart: unless-stopped
    mem_limit: 1g
    cpus: '0.5'

  otel-collector:
    image: ${REGISTRY}/oss-stack-collector:1.0.0
    container_name: otel-collector
    networks:
      otel-net:
        ipv4_address: 172.28.0.12
    ports:
      - "4318:4318"
    depends_on:
      - app
    healthcheck:
      disable: true
    restart: unless-stopped
    mem_limit: 1500m
    cpus: '0.5'
COMPOSE

success "docker-compose.yml written"

# Write BE entrypoint wrapper — skips mysql checks on restart
# Original entry_point.sh uses mysql -uroot which fails after root password is randomized
# Wrapper detects existing install and starts BE directly
cat > "$INSTALL_DIR/be-entrypoint.sh" << 'BEWRAP'
#!/bin/bash
# Wrapper for Doris BE entry_point.sh
# On first start: runs original entry_point.sh for registration
# On restart: starts BE directly — skips mysql checks (root password randomized by app)

DORIS_HOME="/opt/apache-doris"
BE_HOME="$DORIS_HOME/be"
STORAGE_HDD="$BE_HOME/storage.HDD"

if [ -d "$STORAGE_HDD/data" ] && [ "$(ls -A $STORAGE_HDD/data 2>/dev/null)" ]; then
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [INFO] [Wrapper]: Existing data found — starting BE directly"

    # Clean duplicate priority_networks from be.conf
    if [ -f "$BE_HOME/conf/be.conf" ]; then
        awk '!/priority_networks/{print} /priority_networks/ && !seen[$0]++{print}' \
            "$BE_HOME/conf/be.conf" > /tmp/be.conf.clean
        cp /tmp/be.conf.clean "$BE_HOME/conf/be.conf"
    fi

    # Remove stale PID file from previous run
    rm -f "$BE_HOME/bin/be.pid"

    # Set up environment that entry_point.sh normally handles
    ulimit -n 655350 2>/dev/null || true
    swapoff -a 2>/dev/null || true

    # Start BE in foreground — official docs say do NOT use --daemon in Docker
    exec $BE_HOME/bin/start_be.sh
else
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [INFO] [Wrapper]: First start — running original entry_point.sh"
    exec bash /usr/local/bin/entry_point.sh
fi
BEWRAP
chmod +x "$INSTALL_DIR/be-entrypoint.sh"
success "BE entrypoint wrapper written"

if [ -d "$DATA_DIR/doris-fe" ] && [ "$(ls -A "$DATA_DIR/doris-fe" 2>/dev/null)" ]; then
    warn "Existing Doris data found at $DATA_DIR"
    echo -ne "  ${CYAN}?${NC}  Clean existing data for fresh install? [Y/n]: "
    read -r clean_resp < /dev/tty
    clean_resp="${clean_resp:-Y}"
    if [[ "$clean_resp" =~ ^[Yy]$ ]]; then
        rm -rf "$DATA_DIR/doris-fe" "$DATA_DIR/doris-be" 2>/dev/null || \
            sudo rm -rf "$DATA_DIR/doris-fe" "$DATA_DIR/doris-be"
        mkdir -p "$DATA_DIR/doris-fe" "$DATA_DIR/doris-be" 2>/dev/null || \
            sudo mkdir -p "$DATA_DIR/doris-fe" "$DATA_DIR/doris-be"
        chmod -R 777 "$DATA_DIR" 2>/dev/null || sudo chmod -R 777 "$DATA_DIR"
        success "Data directories cleaned"
    else
        warn "Keeping existing data"
    fi
fi

# ── Pull images ───────────────────────────────────────────────
step "Pulling Docker images"
echo ""

(
    $DOCKER_CMD pull "${REGISTRY}/oss-stack-fe:1.0.0" &&
    $DOCKER_CMD pull "${REGISTRY}/oss-stack-be:1.0.0" &&
    $DOCKER_CMD pull "${REGISTRY}/oss-stack-collector:1.0.0" &&
    $DOCKER_CMD pull "${REGISTRY}/oss-stack-app:1.0.0"
) > /tmp/xd-pull.log 2>&1 &

PULL_PID=$!
spinner "$PULL_PID" "Downloading images"
wait "$PULL_PID" || { cat /tmp/xd-pull.log; error "Failed to pull images. Check your network connection."; }
rm -f /tmp/xd-pull.log
success "All images downloaded"

# ── Start containers ──────────────────────────────────────────
step "Starting containers"
echo ""
info "This may take up to 10 minutes on first run while Doris initializes."
echo ""

(
    $COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" up -d \
        > /tmp/xd-compose.log 2>&1
) &

COMPOSE_PID=$!
spinner "$COMPOSE_PID" "Starting Docker Compose"
wait "$COMPOSE_PID" || { echo ""; cat /tmp/xd-compose.log; error "Failed to start containers."; }

success "All containers started"
echo ""
$COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || true
echo ""
rm -f /tmp/xd-compose.log

# ── Wait for health ───────────────────────────────────────────
step "Waiting for services"
echo ""

wait_healthy "otel-doris-fe"  "Doris Frontend"
wait_healthy "otel-doris-be"  "Doris Backend"
wait_healthy "otel-app"       "Application (init + seeding)"

# Wait for login endpoint — confirms seeding complete and app fully ready
echo -e "  ${CYAN}⟳${NC}  ${BOLD}$(printf '%-30s' "Login endpoint")${NC} ${DIM}waiting...${NC}"
login_start=$SECONDS
login_last_elapsed=-1
while true; do
    login_elapsed=$(( SECONDS - login_start ))
    if curl -sf -o /dev/null         -X POST "http://localhost/api/v1/auth/login"         -H "Content-Type: application/json"         -d '{"username":"admin","password":"admin"}' 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC}  ${BOLD}$(printf '%-30s' "Login endpoint")${NC} ${GREEN}ready${NC} ${DIM}(${login_elapsed}s)${NC}"
        break
    fi
    if [ $(( login_elapsed % 15 )) -eq 0 ] && [ "$login_elapsed" -ne "$login_last_elapsed" ] && [ "$login_elapsed" -gt 0 ]; then
        echo -e "  ${CYAN}⟳${NC}  ${BOLD}$(printf '%-30s' "Login endpoint")${NC} ${DIM}${login_elapsed}s elapsed...${NC}"
        login_last_elapsed=$login_elapsed
    fi
    sleep 3
done

# Collector has no healthcheck — just verify it's running
if $DOCKER_CMD inspect otel-collector --format="{{.State.Running}}" 2>/dev/null | grep -q true; then
    echo -e "  ${GREEN}✓${NC}  ${BOLD}$(printf '%-30s' "OTel Collector")${NC} ${GREEN}running${NC}"
else
    warn "OTel Collector may not be running. Check: docker logs otel-collector"
fi

# ── Write manage.sh ───────────────────────────────────────────
cat > "$INSTALL_DIR/manage.sh" << 'MANAGE'
#!/bin/bash
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-status}"
DC="docker compose"
command -v docker &>/dev/null && docker compose version &>/dev/null || DC="docker-compose"
docker info &>/dev/null || DC="sudo docker compose"
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

resolve_service() {
    case "$1" in
        otel-collector|collector) echo "otel-collector" ;;
        doris-fe|fe)              echo "doris-fe" ;;
        doris-be|be)              echo "doris-be" ;;
        app|*)                    echo "app" ;;
    esac
}

wait_healthy() {
    local container="$1"
    local label="$2"
    local start=$SECONDS
    local last_elapsed=-1
    echo -e "  ${CYAN}⟳${NC}  ${BOLD}$(printf '%-30s' "$label")${NC} ${DIM}waiting...${NC}"
    while true; do
        local elapsed=$(( SECONDS - start ))
        local status
        status=$(docker inspect "$container" --format="{{.State.Health.Status}}" 2>/dev/null || echo "starting")
        if [ "$status" = "healthy" ]; then
            echo -e "  ${GREEN}✓${NC}  ${BOLD}$(printf '%-30s' "$label")${NC} ${GREEN}healthy${NC} ${DIM}(${elapsed}s)${NC}"
            break
        fi
        if [ $(( elapsed % 15 )) -eq 0 ] && [ "$elapsed" -ne "$last_elapsed" ] && [ "$elapsed" -gt 0 ]; then
            echo -e "  ${CYAN}⟳${NC}  ${BOLD}$(printf '%-30s' "$label")${NC} ${DIM}${elapsed}s elapsed...${NC}"
            last_elapsed=$elapsed
        fi
        sleep 3
    done
}

start_stack() {
    $DC -f "$INSTALL_DIR/docker-compose.yml" up -d doris-fe
    wait_healthy "otel-doris-fe" "Doris Frontend"
    # Wait for FE RPC port 9020 — BE uses this Thrift port to connect to FE
    # 8030 (HTTP) becomes healthy before 9020 (RPC) is ready
    echo -e "  ${CYAN}⟳${NC}  ${BOLD}$(printf '%-30s' "Doris FE RPC :9020")${NC} ${DIM}waiting...${NC}"
    local rpc_start=$SECONDS
    while true; do
        local rpc_elapsed=$(( SECONDS - rpc_start ))
        if docker exec otel-doris-fe bash -c "echo > /dev/tcp/localhost/9020" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC}  ${BOLD}$(printf '%-30s' "Doris FE RPC :9020")${NC} ${GREEN}ready${NC} ${DIM}(${rpc_elapsed}s)${NC}"
            break
        fi
        [ $rpc_elapsed -gt 120 ] && echo -e "  ${YELLOW}⚠${NC}  Doris FE RPC timed out — continuing anyway" && break
        sleep 3
    done
    $DC -f "$INSTALL_DIR/docker-compose.yml" up -d
    wait_healthy "otel-doris-be" "Doris Backend"
    wait_healthy "otel-app"      "Application"
    if docker inspect otel-collector --format="{{.State.Running}}" 2>/dev/null | grep -q true; then
        echo -e "  ${GREEN}✓${NC}  ${BOLD}$(printf '%-30s' "OTel Collector")${NC} ${GREEN}running${NC}"
    fi
}

case "$CMD" in
  start)
    echo -e "${CYAN}Starting XD-oss-stack...${NC}"
    echo ""
    start_stack
    echo ""
    echo -e "${GREEN}Started successfully${NC}"
    ;;
  stop)
    echo -e "${CYAN}Stopping XD-oss-stack...${NC}"
    $DC -f "$INSTALL_DIR/docker-compose.yml" stop
    echo -e "${GREEN}Stopped (containers preserved — run 'start' to resume)${NC}"
    ;;
  restart)
    echo -e "${CYAN}Restarting XD-oss-stack...${NC}"
    echo ""
    $DC -f "$INSTALL_DIR/docker-compose.yml" stop
    start_stack
    echo ""
    echo -e "${GREEN}Restarted successfully${NC}"
    ;;
  status)
    $DC -f "$INSTALL_DIR/docker-compose.yml" ps
    ;;
  logs)
    SVC=$(resolve_service "${2:-app}")
    $DC -f "$INSTALL_DIR/docker-compose.yml" logs -f "$SVC"
    ;;
  update)
    echo -e "${CYAN}Pulling latest images...${NC}"
    $DC -f "$INSTALL_DIR/docker-compose.yml" pull
    echo ""
    echo -e "${CYAN}Restarting with new images...${NC}"
    echo ""
    $DC -f "$INSTALL_DIR/docker-compose.yml" stop
    start_stack
    echo ""
    echo -e "${GREEN}Updated successfully${NC}"
    ;;
  uninstall)
    echo -e "${RED}This will remove all containers, volumes and the install directory.${NC}"
    echo -ne "${RED}Are you sure? [y/N]${NC} "
    read -r resp
    [[ "$resp" =~ ^[Yy]$ ]] || exit 0
    echo -e "${CYAN}Stopping and removing containers...${NC}"
    $DC -f "$INSTALL_DIR/docker-compose.yml" down -v 2>/dev/null || true
    echo -e "${CYAN}Removing install directory...${NC}"
    rm -rf "$INSTALL_DIR"
    echo ""
    echo -ne "${RED}Also remove Doris data directory? This deletes ALL stored data permanently. [y/N]${NC} "
    read -r data_resp
    if [[ "$data_resp" =~ ^[Yy]$ ]]; then
        DATA_DIR="/var/lib/xd-oss-stack"
        [ -d "$HOME/.xd-oss-stack" ] && DATA_DIR="$HOME/.xd-oss-stack"
        sudo rm -rf "$DATA_DIR" 2>/dev/null || rm -rf "$DATA_DIR" 2>/dev/null || true
        echo -e "${GREEN}Data directory removed.${NC}"
    else
        echo -e "${YELLOW}Data directory kept — remove manually: sudo rm -rf /var/lib/xd-oss-stack${NC}"
    fi
    echo -e "${GREEN}Uninstalled successfully.${NC}"
    ;;
  help|*)
    echo ""
    echo -e "  ${BOLD}XD-oss-stack — manage.sh${NC}"
    echo ""
    echo -e "  ${CYAN}Usage:${NC} $0 <command> [service]"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    ${GREEN}status${NC}              Show container status"
    echo -e "    ${GREEN}start${NC}               Start all containers (waits for health)"
    echo -e "    ${GREEN}stop${NC}                Stop all containers (preserves data)"
    echo -e "    ${GREEN}restart${NC}             Restart all containers (waits for health)"
    echo -e "    ${GREEN}logs [service]${NC}      Follow logs (default: app)"
    echo -e "    ${GREEN}update${NC}              Pull latest images and restart"
    echo -e "    ${GREEN}uninstall${NC}           Remove all containers and data"
    echo ""
    echo -e "  ${BOLD}Services:${NC} app, collector, fe, be"
    echo ""
    ;;
esac
MANAGE
chmod +x "$INSTALL_DIR/manage.sh"

# ── Done ──────────────────────────────────────────────────────
if [[ "$OS" == "macos" ]]; then
    HOST_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "localhost")
else
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
fi
[ -z "$HOST_IP" ] && HOST_IP="localhost"

echo ""
echo -e "  ${BOLD}${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}${GREEN}║                                                       ║${NC}"
echo -e "  ${BOLD}${GREEN}║   ${WHITE}✓  Installation Complete!${GREEN}                          ║${NC}"
echo -e "  ${BOLD}${GREEN}║                                                       ║${NC}"
echo -e "  ${BOLD}${GREEN}║   ${YELLOW}Happy Xpluring your data!${GREEN}                         ║${NC}"
echo -e "  ${BOLD}${GREEN}║                                                       ║${NC}"
echo -e "  ${BOLD}${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}${WHITE}Access:${NC}"
echo -e "  ${CYAN}│${NC}  UI        -> ${BOLD}${CYAN}http://${HOST_IP}${NC}"
echo -e "  ${CYAN}│${NC}  Login     -> ${BOLD}admin${NC} / ${BOLD}admin${NC}"
echo -e "  ${CYAN}│${NC}  OTLP HTTP -> ${BOLD}${CYAN}http://${HOST_IP}:4318${NC}"
echo ""
echo -e "  ${BOLD}${WHITE}Manage:${NC}"
echo -e "  ${CYAN}│${NC}  ${CYAN}$INSTALL_DIR/manage.sh${NC} ${BOLD}status${NC}             ${DIM}# container status${NC}"
echo -e "  ${CYAN}│${NC}  ${CYAN}$INSTALL_DIR/manage.sh${NC} ${BOLD}start${NC}              ${DIM}# start all containers${NC}"
echo -e "  ${CYAN}│${NC}  ${CYAN}$INSTALL_DIR/manage.sh${NC} ${BOLD}stop${NC}               ${DIM}# stop all containers${NC}"
echo -e "  ${CYAN}│${NC}  ${CYAN}$INSTALL_DIR/manage.sh${NC} ${BOLD}restart${NC}            ${DIM}# restart all containers${NC}"
echo -e "  ${CYAN}│${NC}  ${CYAN}$INSTALL_DIR/manage.sh${NC} ${BOLD}logs${NC} ${DIM}[service]${NC}     ${DIM}# follow logs${NC}"
echo -e "  ${CYAN}│${NC}  ${CYAN}$INSTALL_DIR/manage.sh${NC} ${BOLD}update${NC}             ${DIM}# pull latest images${NC}"
echo -e "  ${CYAN}│${NC}  ${CYAN}$INSTALL_DIR/manage.sh${NC} ${BOLD}uninstall${NC}          ${DIM}# remove everything${NC}"
echo ""
echo -e "  ${BOLD}${GREEN}─────────────────────────────────────────────────────${NC}"
echo ""

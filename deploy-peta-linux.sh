#!/bin/bash

# ====================================
# Peta Core & Console Unified Deployment Script (Linux Version)
# ====================================
# Enhanced with automatic Docker service management
# Supports selective deployment: Core only, Console only, or Both
# Merged from docker-deploy.sh and start-console.sh

set -e

# ================== Configuration Variables ==================
DEPLOY_DIR=${DEPLOY_DIR:-./peta-deployment}
BACKEND_PORT=${BACKEND_PORT:-3002}
CONSOLE_PORT=${CONSOLE_PORT:-3000}
CORE_DB_PORT=${CORE_DB_PORT:-5434}
CONSOLE_DB_PORT=${CONSOLE_DB_PORT:-5435}
PETA_VERSION=${PETA_VERSION:-1.3.0}
PETA_AUTH_VERSION=${PETA_AUTH_VERSION:-1.3.0}

# ================== Color Definitions ==================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ================== Logging Functions ==================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "\n${CYAN}==>${NC} $1" >&2
}

# ================== Docker Service Management ==================

# Check if Docker daemon is running
check_docker_daemon() {
    if docker info > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Start Docker service
start_docker_service() {
    log_step "Checking Docker daemon status"

    if check_docker_daemon; then
        log_success "Docker daemon is already running"
        return 0
    fi

    log_warn "Docker daemon is not running, attempting to start..."

    # Try systemctl first (most common on modern Linux)
    if command -v systemctl &> /dev/null; then
        log_info "Using systemctl to start Docker..."
        if sudo systemctl start docker 2>/dev/null; then
            # Wait a moment for Docker to fully start
            sleep 2
            if check_docker_daemon; then
                log_success "Docker daemon started successfully via systemctl"
                # Enable Docker to start on boot
                sudo systemctl enable docker > /dev/null 2>&1
                log_info "Docker service enabled for auto-start on boot"
                return 0
            fi
        fi
    fi

    # Try service command (older init systems)
    if command -v service &> /dev/null; then
        log_info "Using service command to start Docker..."
        if sudo service docker start 2>/dev/null; then
            sleep 2
            if check_docker_daemon; then
                log_success "Docker daemon started successfully via service"
                return 0
            fi
        fi
    fi

    # Try direct dockerd start (last resort)
    log_error "Failed to start Docker daemon automatically"
    log_error "Please start Docker manually with one of these commands:"
    echo -e "  ${BLUE}sudo systemctl start docker${NC}"
    echo -e "  ${BLUE}sudo service docker start${NC}"
    echo ""
    exit 1
}

# ================== Utility Functions ==================

# Generate random password
generate_password() {
    local length=${1:-32}
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required to generate deployment secrets securely"
        return 1
    fi
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed, please install $1 first"
        exit 1
    fi
}

# Check if port is in use (cross-platform: Linux & macOS)
check_port() {
    local port=$1

    # Method 1: Use ss (modern Linux standard, most reliable)
    if command -v ss &> /dev/null; then
        if ss -tlnp 2>/dev/null | grep -qE ":${port}\s" || \
           ss -tln 2>/dev/null | grep -qE ":${port}\s"; then
            return 1  # Port is in use
        fi
        return 0  # Port is available
    fi

    # Method 2: Use netstat (cross-platform compatible)
    if command -v netstat &> /dev/null; then
        # Linux format
        if netstat -tlnp 2>/dev/null | grep -qE ":${port}\s" || \
           netstat -tln 2>/dev/null | grep -qE ":${port}\s"; then
            return 1
        fi
        # macOS format (uses . instead of :)
        if netstat -an 2>/dev/null | grep -qE "\.${port}\s.*LISTEN"; then
            return 1
        fi
        return 0
    fi

    # Method 3: Use lsof (macOS default, some Linux distributions)
    if command -v lsof &> /dev/null; then
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            return 1
        fi
        return 0
    fi

    # If no command is available, warn user but continue
    log_warn "Cannot check port availability (ss/netstat/lsof not found)"
    log_warn "Please manually verify port $port is not in use"
    return 0  # Assume available to continue deployment
}

# Interactive port input function
# Parameters: $1=port description, $2=current port, $3=forbidden port (optional)
# Returns: outputs new port to stdout, exit code 0=success, 2=user cancelled
prompt_for_port() {
    local port_description=$1
    local current_port=$2
    local forbidden_port=$3
    local new_port
    local first_attempt=true

    while true; do
        if [ "$first_attempt" = true ]; then
            echo "" >&2
            log_warn "Port $current_port is already in use"
            log_info "Purpose: $port_description"
            echo "" >&2
            first_attempt=false
        fi

        if ! read -r -p "Please enter a new port number (1024-65535) or 'q' to quit: " new_port; then
            echo "" >&2
            log_error "Input closed before a replacement port was provided"
            return 1
        fi

        # Check if user wants to exit
        if [[ "$new_port" == "q" ]] || [[ "$new_port" == "quit" ]]; then
            echo "" >&2
            log_info "User cancelled deployment"
            return 2
        fi

        # Validate port number format
        if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
            log_error "Invalid input: port number must be numeric"
            continue
        fi

        # Validate port number range
        if [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
            log_error "Port out of range: must be between 1024-65535"
            continue
        fi

        # Check if conflicts with forbidden port
        if [ -n "$forbidden_port" ] && [ "$new_port" = "$forbidden_port" ]; then
            log_error "Port $new_port is already used by another service, please enter a different port"
            continue
        fi

        # Check if new port is also in use
        if ! check_port $new_port; then
            log_error "Port $new_port is also in use, please enter a different port"
            continue
        fi

        # Port available, update variable
        echo "" >&2
        log_success "Port $new_port is available"
        echo "$new_port"
        return 0
    done
}

# Wait for service health check
wait_for_health() {
    local url=$1
    local max_attempts=30
    local attempt=0

    log_info "Waiting for service health check..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf $url > /dev/null 2>&1; then
            log_success "Service health check passed"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done

    echo ""
    log_error "Service health check timeout"
    return 1
}

# Display deployment information (access info, config files, common commands)
# Read ports and deployment mode from .env file
show_deployment_info() {
    local deploy_dir=${1:-$DEPLOY_DIR}
    local quoted_deploy_dir

    printf -v quoted_deploy_dir '%q' "$deploy_dir"

    # Read .env file to get ports and deployment mode
    if [ -f "$deploy_dir/.env" ]; then
        local backend_port=$(grep "^BACKEND_PORT=" "$deploy_dir/.env" | cut -d'=' -f2)
        local console_port=$(grep "^CONSOLE_PORT=" "$deploy_dir/.env" | cut -d'=' -f2)

        # Determine deployment mode (by checking services in docker-compose.yml)
        local has_core=false
        local has_console=false
        local has_auth=false
        if grep -q "peta-core:" "$deploy_dir/docker-compose.yml" 2>/dev/null; then
            has_core=true
        fi
        if grep -q "peta-console:" "$deploy_dir/docker-compose.yml" 2>/dev/null; then
            has_console=true
        fi
        if grep -q "peta-auth:" "$deploy_dir/docker-compose.yml" 2>/dev/null; then
            has_auth=true
        fi

        echo "" >&2
        echo -e "${CYAN}===========================================${NC}" >&2
        echo -e "${CYAN}Access Information:${NC}" >&2

        if [ "$has_core" = true ]; then
            echo -e "  Core API:        ${BLUE}http://localhost:${backend_port}${NC}" >&2
            echo -e "  Core Health:     ${BLUE}http://localhost:${backend_port}/health${NC}" >&2
        fi

        if [ "$has_console" = true ]; then
            echo -e "  Console Web:     ${BLUE}http://localhost:${console_port}${NC}" >&2
        fi
        if [ "$has_auth" = true ]; then
            echo -e "  Peta Auth:       ${BLUE}http://peta-auth:7788/healthz${NC} (internal-only)" >&2
        fi

        echo "" >&2
        echo -e "${CYAN}Configuration Files:${NC}" >&2
        echo -e "  Deployment Dir:      ${BLUE}${deploy_dir}${NC}" >&2
        echo -e "  docker-compose.yml:  ${BLUE}${deploy_dir}/docker-compose.yml${NC}" >&2
        echo -e "  .env file:           ${BLUE}${deploy_dir}/.env${NC}" >&2

        echo "" >&2
        echo -e "${CYAN}Common Commands:${NC}" >&2
        echo -e "  View logs:      ${BLUE}cd -- ${quoted_deploy_dir} && $COMPOSE_CMD logs -f${NC}" >&2
        echo -e "  View status:    ${BLUE}cd -- ${quoted_deploy_dir} && $COMPOSE_CMD ps${NC}" >&2
        echo -e "  Stop services:  ${BLUE}cd -- ${quoted_deploy_dir} && $COMPOSE_CMD down${NC}" >&2
        echo -e "  Restart:        ${BLUE}cd -- ${quoted_deploy_dir} && $COMPOSE_CMD restart${NC}" >&2
        echo -e "${CYAN}===========================================${NC}" >&2
        echo "" >&2
    else
        log_warn ".env file not found, unable to display details" >&2
    fi
}

# Check existing volumes
check_existing_volumes() {
    local volume_name=$1
    if docker volume ls | grep -q "${volume_name}" 2>/dev/null; then
        return 0
    fi
    return 1
}

has_existing_deployment() {
    local deploy_dir="$1"
    [ -f "$deploy_dir/docker-compose.yml" ] || [ -f "$deploy_dir/.env" ]
}

stat_secret_path() {
    local gnu_format="$1"
    local bsd_format="$2"
    local path="$3"

    if stat -c "$gnu_format" "$path" >/dev/null 2>&1; then
        stat -c "$gnu_format" "$path"
    else
        stat -f "$bsd_format" "$path"
    fi
}

has_valid_peta_auth_runtime_secrets() {
    local secrets_dir="${1:-./secrets}"
    local master_key="$secrets_dir/peta_auth_master_key"
    local client_secrets="$secrets_dir/peta_auth_client_secrets.json"
    local path mode owner

    if [ ! -d "$secrets_dir" ] || [ -L "$secrets_dir" ]; then
        return 1
    fi
    mode="$(stat_secret_path '%a' '%Lp' "$secrets_dir")"
    owner="$(stat_secret_path '%u' '%u' "$secrets_dir")"
    if [ "$owner" != "$(id -u)" ] || [ $((8#$mode & 077)) -ne 0 ]; then
        return 1
    fi

    for path in "$master_key" "$client_secrets"; do
        if [ ! -f "$path" ] || [ -L "$path" ] || [ ! -r "$path" ]; then
            return 1
        fi
        mode="$(stat_secret_path '%a' '%Lp' "$path")"
        owner="$(stat_secret_path '%u' '%u' "$path")"
        if [ "$owner" != "$(id -u)" ] || [ $((8#$mode & 077)) -ne 0 ]; then
            return 1
        fi
    done

    if [ "$(wc -c < "$master_key")" -ne 32 ] || [ ! -s "$client_secrets" ]; then
        return 1
    fi
}

is_safe_new_deployment_directory() {
    local deploy_dir="$1"
    local secrets_dir="$deploy_dir/secrets"

    [ ! -e "$deploy_dir" ] && return 0
    [ -d "$deploy_dir" ] && [ ! -L "$deploy_dir" ] && [ -r "$deploy_dir" ] && [ -x "$deploy_dir" ] || return 1

    if ! find "$deploy_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        return 0
    fi
    if find "$deploy_dir" -mindepth 1 -maxdepth 1 ! -name secrets -print -quit | grep -q .; then
        return 1
    fi
    [ -d "$secrets_dir" ] && [ ! -L "$secrets_dir" ] && [ -r "$secrets_dir" ] && [ -x "$secrets_dir" ] || return 1
    if find "$secrets_dir" -mindepth 1 -maxdepth 1 ! -type f -print -quit | grep -q . ||
       find "$secrets_dir" -mindepth 1 -maxdepth 1 -type f ! \( -name peta_auth_master_key -o -name peta_auth_client_secrets.json \) -print -quit | grep -q .; then
        return 1
    fi
    has_valid_peta_auth_runtime_secrets "$secrets_dir"
}

require_peta_auth_runtime_secrets() {
    if ! has_valid_peta_auth_runtime_secrets; then
        log_error "Peta Auth requires current-user-only, readable runtime secrets in ./secrets"
        return 1
    fi
}

# ================== Docker Compose Generation Functions ==================

generate_docker_compose() {
    local deploy_mode=$1
    local compose_file="docker-compose.yml"

    log_step "Generating docker-compose.yml"

    # Generate file header
    cat > "$compose_file" <<'EOF'
services:
EOF

    # Generate service configuration based on deployment mode
    if [ "$deploy_mode" = "1" ] || [ "$deploy_mode" = "2" ]; then
        # Generate Core services
        cat >> "$compose_file" <<'EOF'
  # PostgreSQL for peta-core
  postgres-core:
    image: postgres:16-alpine
    container_name: peta-core-postgres-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${CORE_DB_USER}
      POSTGRES_PASSWORD: ${CORE_DB_PASSWORD}
      POSTGRES_DB: ${CORE_DB_NAME}
    ports:
      - '${CORE_DB_PORT}:5432'
    volumes:
      - postgres_peta_core:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ${CORE_DB_USER} -d ${CORE_DB_NAME}']
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - peta-network

  # Peta Core Service (MCP Gateway)
  peta-core:
    image: bcdunia/peta-core:${PETA_VERSION}
    container_name: peta-core
    restart: unless-stopped
    user: root
    depends_on:
      postgres-core:
        condition: service_healthy
EOF
        if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
            cat >> "$compose_file" <<'EOF'
      peta-auth:
        condition: service_healthy
EOF
        fi
        cat >> "$compose_file" <<'EOF'
    environment:
      NODE_ENV: ${NODE_ENV}
      DATABASE_URL: ${CORE_DATABASE_URL}
      BACKEND_PORT: ${BACKEND_PORT}
      JWT_SECRET: ${CORE_JWT_SECRET}
      LOG_LEVEL: ${LOG_LEVEL}
      LOG_PRETTY: ${LOG_PRETTY}
      CLOUDFLARED_CONTAINER_NAME: ${CLOUDFLARED_CONTAINER_NAME}
      PETA_CORE_IN_DOCKER: "true"
      SKIP_DB_CONTAINER_START: "true"
      LAZY_START_ENABLED: ${LAZY_START_ENABLED}
      PETA_AUTH_AUTOSTART: ${PETA_AUTH_AUTOSTART}
      RESULT_CACHE_ENABLED: ${RESULT_CACHE_ENABLED}
      RESULT_CACHE_BACKEND: ${RESULT_CACHE_BACKEND}
      RESULT_CACHE_STRICT_STARTUP: ${RESULT_CACHE_STRICT_STARTUP}
      RESULT_CACHE_DEFAULT_TTL_SECONDS: ${RESULT_CACHE_DEFAULT_TTL_SECONDS}
      RESULT_CACHE_DEFAULT_ADMISSION_POLICY: ${RESULT_CACHE_DEFAULT_ADMISSION_POLICY}
      RESULT_CACHE_DEFAULT_ADMISSION_WINDOW_SECONDS: ${RESULT_CACHE_DEFAULT_ADMISSION_WINDOW_SECONDS}
      RESULT_CACHE_MAX_ENTRY_BYTES: ${RESULT_CACHE_MAX_ENTRY_BYTES}
      RESULT_CACHE_KEY_PREFIX: ${RESULT_CACHE_KEY_PREFIX}
      RESULT_CACHE_COMPRESS: ${RESULT_CACHE_COMPRESS}
      RESULT_CACHE_COMPRESSION_MIN_BYTES: ${RESULT_CACHE_COMPRESSION_MIN_BYTES}
      RESULT_CACHE_DB_SWEEP_INTERVAL_SECONDS: ${RESULT_CACHE_DB_SWEEP_INTERVAL_SECONDS}
      RESULT_CACHE_DB_SWEEP_BATCH_SIZE: ${RESULT_CACHE_DB_SWEEP_BATCH_SIZE}
      RESULT_CACHE_MEMORY_MAX_ENTRIES: ${RESULT_CACHE_MEMORY_MAX_ENTRIES}
      REDIS_URL: ${REDIS_URL}
      SKILLS_DIR: "/data/skills"
    ports:
      - '${BACKEND_PORT}:${BACKEND_PORT}'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./cloudflared:/app/cloudflared
      - ./skills:/data/skills  # Skills storage directory (enables auto host-path detection for child containers)
    networks:
      - peta-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${BACKEND_PORT}/health']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

EOF
        if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
            cat >> "$compose_file" <<'EOF'
  # Peta Auth Service (optional, internal-only)
  peta-auth:
    image: bcdunia/peta-auth:${PETA_AUTH_VERSION}
    container_name: peta-auth-core
    restart: unless-stopped
    networks:
      - peta-network
    volumes:
      - peta-auth-core-data:/data
    environment:
      PETA_AUTH_MASTER_KEY_FILE: /run/secrets/peta_auth_master_key
      PETA_AUTH_CLIENT_SECRETS_FILE: /run/secrets/peta_auth_client_secrets_json
    secrets:
      - peta_auth_master_key
      - peta_auth_client_secrets_json
    healthcheck:
      test: ['CMD', '/usr/bin/bash', '-c', 'exec 3<>/dev/tcp/localhost/7788 || exit 1; printf "GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3; response=""; while IFS= read -r -t 2 line <&3; do response+="$$line"; done; [[ "$$response" == *"\"ok\":true"* ]]']
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s

EOF
        fi
        cat >> "$compose_file" <<'EOF'
  # Cloudflared Service
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: ${CLOUDFLARED_CONTAINER_NAME}
    restart: "no"
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-}
    networks:
      - peta-network
    volumes:
      - ./cloudflared:/etc/cloudflared

EOF
    fi

    if [ "$deploy_mode" = "1" ] || [ "$deploy_mode" = "3" ]; then
        # Generate Console services
        cat >> "$compose_file" <<'EOF'
  # PostgreSQL for peta-console
  postgres-console:
    image: postgres:16-alpine
    container_name: peta-console-postgres-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${CONSOLE_DB_USER}
      POSTGRES_PASSWORD: ${CONSOLE_DB_PASSWORD}
      POSTGRES_DB: ${CONSOLE_DB_NAME}
    ports:
      - '${CONSOLE_DB_PORT}:5432'
    volumes:
      - postgres_peta_console:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ${CONSOLE_DB_USER} -d ${CONSOLE_DB_NAME}']
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - peta-network

  # Peta Console Service
  peta-console:
    image: bcdunia/peta-console:${PETA_VERSION}
    container_name: peta-console
    restart: unless-stopped
    depends_on:
      postgres-console:
        condition: service_healthy
    environment:
      NODE_ENV: ${NODE_ENV}
      DATABASE_URL: ${CONSOLE_DATABASE_URL}
      PORT: ${CONSOLE_PORT}
      JWT_SECRET: ${CONSOLE_JWT_SECRET}
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
      NEXTAUTH_URL: ${NEXTAUTH_URL}
      MCP_GATEWAY_URL: ${MCP_GATEWAY_URL}
      LOG_SYNC_ENABLED: ${LOG_SYNC_ENABLED}
      LOG_SYNC_INTERVAL_MINUTES: ${LOG_SYNC_INTERVAL_MINUTES}
      MAX_LOGS_PER_REQUEST: ${MAX_LOGS_PER_REQUEST}
      LOG_BATCH_SIZE: ${LOG_BATCH_SIZE}
      LOG_SYNC_TIMEOUT: ${LOG_SYNC_TIMEOUT}
      LOG_SYNC_RETRY_ATTEMPTS: ${LOG_SYNC_RETRY_ATTEMPTS}
    ports:
      - '${CONSOLE_PORT}:${CONSOLE_PORT}'
    networks:
      - peta-network
    healthcheck:
      test: ['CMD', 'curl', '-f', 'http://localhost:${CONSOLE_PORT}']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

EOF
    fi

    # Generate volumes configuration
    cat >> "$compose_file" <<'EOF'
volumes:
EOF

    if [ "$deploy_mode" = "1" ] || [ "$deploy_mode" = "2" ]; then
        cat >> "$compose_file" <<'EOF'
  postgres_peta_core:
    driver: local
EOF
    fi

    if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
        cat >> "$compose_file" <<'EOF'
  peta-auth-core-data:
    driver: local
EOF
    fi

    if [ "$deploy_mode" = "1" ] || [ "$deploy_mode" = "3" ]; then
        cat >> "$compose_file" <<'EOF'
  postgres_peta_console:
    driver: local
EOF
    fi

    # Generate networks configuration
    cat >> "$compose_file" <<'EOF'

networks:
  peta-network:
    driver: bridge
EOF

    if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
        cat >> "$compose_file" <<'EOF'

secrets:
  peta_auth_master_key:
    file: ./secrets/peta_auth_master_key
  peta_auth_client_secrets_json:
    file: ./secrets/peta_auth_client_secrets.json
EOF
    fi

    log_success "docker-compose.yml generated successfully"
}

# ================== .env File Generation Functions ==================

generate_env_file() {
    local deploy_mode=$1
    local env_file=".env"

    log_step "Generating .env file"
    umask 077

    # Generate file header
    cat > "$env_file" <<EOF
# ====================================
# Peta Deployment Environment Variables
# ====================================
# Auto-generated by deploy-peta-linux.sh
# Please keep this file secure in production, do not expose passwords

# -------------------- General Configuration --------------------
NODE_ENV=production
PETA_VERSION=${PETA_VERSION}
PETA_AUTH_VERSION=${PETA_AUTH_VERSION}

EOF

    # Generate configuration based on deployment mode
    if [ "$deploy_mode" = "1" ] || [ "$deploy_mode" = "2" ]; then
        # Generate Core environment variables
        CORE_JWT_SECRET=$(generate_password 32)
        CORE_DB_PASSWORD=$(generate_password 24)

        cat >> "$env_file" <<EOF
# -------------------- Peta Core Configuration --------------------
# Core service port
BACKEND_PORT=${BACKEND_PORT}

# Core database configuration
CORE_DB_USER=peta
CORE_DB_PASSWORD=${CORE_DB_PASSWORD}
CORE_DB_NAME=peta_core_postgres
CORE_DB_PORT=${CORE_DB_PORT}

# Core database connection string
CORE_DATABASE_URL="postgresql://\${CORE_DB_USER}:\${CORE_DB_PASSWORD}@postgres-core:5432/\${CORE_DB_NAME}?schema=public"

# Core JWT Secret
CORE_JWT_SECRET=${CORE_JWT_SECRET}

# Logging configuration
LOG_LEVEL=info
LOG_PRETTY=false
LOG_RESPONSE_MAX_LENGTH=300

# Result cache configuration
# Controls caching for tools/call, resources/read, prompts/get.
RESULT_CACHE_ENABLED=false
RESULT_CACHE_BACKEND=db
RESULT_CACHE_STRICT_STARTUP=false
RESULT_CACHE_DEFAULT_TTL_SECONDS=30
RESULT_CACHE_DEFAULT_ADMISSION_POLICY=immediate
RESULT_CACHE_DEFAULT_ADMISSION_WINDOW_SECONDS=300
RESULT_CACHE_MAX_ENTRY_BYTES=262144
# Leave empty to use peta-core default: peta:\${NODE_ENV}
# RESULT_CACHE_KEY_PREFIX=peta:production
RESULT_CACHE_COMPRESS=auto
RESULT_CACHE_COMPRESSION_MIN_BYTES=4096
# DB backend housekeeping
RESULT_CACHE_DB_SWEEP_INTERVAL_SECONDS=300
RESULT_CACHE_DB_SWEEP_BATCH_SIZE=1000
# Memory backend capacity
RESULT_CACHE_MEMORY_MAX_ENTRIES=1000
# Required only when RESULT_CACHE_BACKEND=redis
# REDIS_URL=redis://localhost:6379

# Cloudflared configuration
CLOUDFLARED_CONTAINER_NAME=peta-core-cloudflared-tunnel
CLOUDFLARE_TUNNEL_TOKEN=

# -------------------- MCP Server Management --------------------
# Lazy loading: Servers load config but delay startup until first use
# Idle servers auto-shutdown to conserve resources
LAZY_START_ENABLED=true

# -------------------- Peta Auth (optional) --------------------
# If false, peta-auth will not be installed or started
PETA_AUTH_AUTOSTART=${PETA_AUTH_AUTOSTART}

EOF
    fi

    if [ "$deploy_mode" = "1" ] || [ "$deploy_mode" = "3" ]; then
        # Generate Console environment variables
        CONSOLE_JWT_SECRET=$(generate_password 32)
        NEXTAUTH_SECRET=$(generate_password 32)
        CONSOLE_DB_PASSWORD=$(generate_password 24)

        # Set MCP Gateway URL based on deployment mode
        if [ "$deploy_mode" = "1" ]; then
            MCP_GATEWAY_URL="http://peta-core:\${BACKEND_PORT}"
        else
            MCP_GATEWAY_URL="http://localhost:\${BACKEND_PORT}"
        fi

        cat >> "$env_file" <<EOF
# -------------------- Peta Console Configuration --------------------
# Console service port
CONSOLE_PORT=${CONSOLE_PORT}

# Console database configuration
CONSOLE_DB_USER=peta
CONSOLE_DB_PASSWORD=${CONSOLE_DB_PASSWORD}
CONSOLE_DB_NAME=peta_console_postgres
CONSOLE_DB_PORT=${CONSOLE_DB_PORT}

# Console database connection string
CONSOLE_DATABASE_URL="postgresql://\${CONSOLE_DB_USER}:\${CONSOLE_DB_PASSWORD}@postgres-console:5432/\${CONSOLE_DB_NAME}?schema=public"

# Console authentication configuration
CONSOLE_JWT_SECRET=${CONSOLE_JWT_SECRET}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
NEXTAUTH_URL=http://localhost:${CONSOLE_PORT}

# MCP Gateway connection configuration
MCP_GATEWAY_URL=${MCP_GATEWAY_URL}

# Log synchronization configuration
LOG_SYNC_ENABLED=true
LOG_SYNC_INTERVAL_MINUTES=2
MAX_LOGS_PER_REQUEST=5000
LOG_BATCH_SIZE=500
LOG_SYNC_TIMEOUT=180000
LOG_SYNC_RETRY_ATTEMPTS=2

EOF
    fi

    log_success ".env file generated successfully"
    chmod 600 "$env_file"
    log_warn "Please keep the .env file secure, it contains sensitive password information"
}

# ================== Main Function ==================

main() {
    local quoted_deploy_dir

    printf -v quoted_deploy_dir '%q' "$DEPLOY_DIR"
    log_step "Peta Core & Console Unified Deployment Script (Linux Enhanced Version)"
    echo ""

    # Check environment dependencies
    log_step "Checking environment dependencies"
    check_command docker

    # Check and start Docker daemon if needed
    start_docker_service

    # Check docker compose (V2) or docker-compose (V1)
    if docker compose version > /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        log_success "Docker Compose V2 is installed"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        log_success "Docker Compose V1 is installed"
    else
        log_error "Docker Compose is not installed, please install Docker Compose first"
        exit 1
    fi

    log_success "Docker environment check passed"

    # Check if deployment directory already exists
    log_step "Checking deployment environment"
    if has_existing_deployment "$DEPLOY_DIR"; then
        log_warn "Existing deployment detected: $DEPLOY_DIR"
        echo ""
        echo "Please choose an option:"
        echo "  1) Start existing deployed services"
        echo "  2) Complete redeployment (will delete all data!)"
        echo ""
        read -p "Please enter option [1-2]: " existing_choice

        # Validate input
        if [[ ! "$existing_choice" =~ ^[1-2]$ ]]; then
            log_error "Invalid option, please enter 1 or 2"
            exit 1
        fi

        # Handle option 1: Direct start
        if [ "$existing_choice" = "1" ]; then
            log_step "Starting existing deployed services"
            cd -- "$DEPLOY_DIR"

            # Check if services are already running
            if $COMPOSE_CMD ps --services --filter "status=running" 2>/dev/null | grep -q .; then
                log_warn "Services are already running"
                echo ""
                echo "Service status:"
                $COMPOSE_CMD ps

                # Display deployment info (already cd to deployment dir, use current dir)
                show_deployment_info "."

                log_info "To restart services, run: cd -- $quoted_deploy_dir && $COMPOSE_CMD restart"
                exit 0
            fi

            # Start services
            log_info "Starting services..."
            $COMPOSE_CMD up -d

            # Wait and verify startup
            sleep 3
            echo ""
            echo "Service status:"
            $COMPOSE_CMD ps
            echo ""
            log_success "Services started"
            exit 0
        fi

        # Handle option 2: Complete redeployment
        if [ "$existing_choice" = "2" ]; then
            echo ""
            log_warn "Complete redeployment requires manual execution of the following steps:"
            echo ""
            echo -e "${CYAN}Step 1: Stop and remove all containers, networks and volumes${NC}"
            echo -e "  ${BLUE}cd -- $quoted_deploy_dir && $COMPOSE_CMD down -v && cd ../${NC}"
            echo ""
            echo -e "${CYAN}Step 2: Remove deployment directory${NC}"
            echo -e "  ${BLUE}rm -rf -- $quoted_deploy_dir${NC}"
            echo ""
            echo -e "${CYAN}Step 3: Re-run deployment script${NC}"
            echo -e "  ${BLUE}./deploy-peta-linux.sh${NC}"
            echo ""
            log_error "⚠️  Warning: Running 'docker compose down -v' will permanently delete all database data!"
            echo ""
            log_info "Please manually execute the above commands to complete redeployment"
            exit 0
        fi
    fi
    if ! is_safe_new_deployment_directory "$DEPLOY_DIR"; then
        log_error "Refusing to use $DEPLOY_DIR: it must be empty or contain only validated Peta Auth secrets"
        exit 1
    fi
    log_success "Deployment environment check passed"

    # Display deployment menu
    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}    Peta Service Deployment Wizard${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    echo "Please select deployment mode:"
    echo "  1) Deploy both Core and Console (recommended, full experience) [default]"
    echo "  2) Deploy peta-core only (MCP Gateway)"
    echo "  3) Deploy peta-console only (requires Core already deployed)"
    echo ""

    # Get user choice
    read -p "Please enter option [1-3] (press Enter for default option 1): " DEPLOY_MODE
    DEPLOY_MODE=${DEPLOY_MODE:-1}

    # Validate input
    if [[ ! "$DEPLOY_MODE" =~ ^[1-3]$ ]]; then
        log_error "Invalid option, please enter 1, 2 or 3"
        exit 1
    fi

    # Optional peta-auth selection (only when deploying peta-core)
    PETA_AUTH_AUTOSTART="false"
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "2" ]; then
        echo ""
        log_warn "Peta Auth (optional) provides Peta-managed OAuth credentials (clientId/clientSecret)."
        log_warn "If you plan to use Peta-managed credentials, peta-auth is REQUIRED."
        log_warn "If you do NOT install it, any Peta-managed OAuth integration will fail when used."
        log_info "If you will only bring your own credentials, you can safely skip."
        echo ""
        read -p "Install and start peta-auth service? [Y/n]: " PETA_AUTH_CHOICE
        PETA_AUTH_CHOICE=${PETA_AUTH_CHOICE:-y}

        if [[ "$PETA_AUTH_CHOICE" =~ ^[Nn]$ ]]; then
            PETA_AUTH_AUTOSTART="false"
            log_warn "peta-auth will NOT be installed. Peta-managed OAuth features will error if used."
        else
            PETA_AUTH_AUTOSTART="true"
            log_info "peta-auth will be installed and started."
        fi
    fi

    # Display services to be deployed
    echo ""
    log_info "Your selected deployment mode:"
    case $DEPLOY_MODE in
        1)
            log_info "  - peta-core (MCP Gateway)"
            log_info "  - peta-console (Web Console)"
            log_info "  - postgres-core (Core database)"
            log_info "  - postgres-console (Console database)"
            log_info "  - cloudflared (Cloudflare Tunnel)"
            if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
                log_info "  - peta-auth (OAuth service, internal-only)"
            fi
            ;;
        2)
            log_info "  - peta-core (MCP Gateway)"
            log_info "  - postgres-core (Core database)"
            log_info "  - cloudflared (Cloudflare Tunnel)"
            if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
                log_info "  - peta-auth (OAuth service, internal-only)"
            fi
            ;;
        3)
            log_info "  - peta-console (Web Console)"
            log_info "  - postgres-console (Console database)"
            log_warn "  Note: Please ensure peta-core service is running at http://localhost:${BACKEND_PORT}"
            ;;
    esac
    echo ""

    # Check port availability
    log_step "Checking port availability"

    # Check Core port
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "2" ]; then
        log_info "Checking peta-core service port $BACKEND_PORT..."
        while ! check_port $BACKEND_PORT; do
            BACKEND_PORT=$(prompt_for_port "peta-core service startup port" $BACKEND_PORT)
            if [ $? -eq 2 ]; then
                exit 0
            fi
        done
        log_success "Core port $BACKEND_PORT is available"
    fi

    # Check Console port
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "3" ]; then
        log_info "Checking peta-console service port $CONSOLE_PORT..."
        while ! check_port $CONSOLE_PORT || [ "$CONSOLE_PORT" = "$BACKEND_PORT" ]; do
            # If port is same as BACKEND_PORT, show error message
            if [ "$CONSOLE_PORT" = "$BACKEND_PORT" ]; then
                log_error "Console port cannot be the same as Core port"
            fi
            CONSOLE_PORT=$(prompt_for_port "peta-console service startup port" $CONSOLE_PORT "$BACKEND_PORT")
            if [ $? -eq 2 ]; then
                exit 0
            fi
        done
        log_success "Console port $CONSOLE_PORT is available"
    fi

    log_success "All port checks completed"

    # Create deployment directory
    log_step "Creating deployment directory"
    mkdir -p -- "$DEPLOY_DIR"
    cd -- "$DEPLOY_DIR"
    log_success "Deployment directory: $(pwd)"

    # Check existing volumes
    log_step "Checking existing databases"
    EXISTING_DB=false
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "2" ]; then
        if check_existing_volumes "postgres_peta_core"; then
            log_warn "Existing Core database volume detected"
            EXISTING_DB=true
        fi
    fi
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "3" ]; then
        if check_existing_volumes "postgres_peta_console"; then
            log_warn "Existing Console database volume detected"
            EXISTING_DB=true
        fi
    fi

    # Generate configuration files
    if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
        require_peta_auth_runtime_secrets
    fi
    generate_docker_compose "$DEPLOY_MODE"
    generate_env_file "$DEPLOY_MODE"

    # Create cloudflared directory (if needed)
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "2" ]; then
        log_step "Creating Cloudflared configuration directory"
        mkdir -p cloudflared
        log_success "Cloudflared configuration directory created"
    fi

    # If existing database detected, prompt user
    if [ "$EXISTING_DB" = true ]; then
        local quoted_current_dir quoted_env_file

        printf -v quoted_current_dir '%q' "$PWD"
        printf -v quoted_env_file '%q' "$PWD/.env"
        echo ""
        log_warn "════════════════════════════════════════════════════════"
        log_warn "  Existing database volume detected!"
        log_warn "════════════════════════════════════════════════════════"
        echo ""
        log_info "Configuration files generated, but services not started due to possible password mismatch."
        echo ""
        log_info "Please follow these steps:"
        echo -e "  1. Edit .env file to match existing database password:"
        echo -e "     ${BLUE}vi -- $quoted_env_file${NC}"
        echo ""
        echo -e "  2. Modify the relevant configuration values"
        echo ""
        echo -e "  3. After modification, start services:"
        echo -e "     ${BLUE}cd -- $quoted_current_dir && $COMPOSE_CMD up -d${NC}"
        echo ""
        log_info "Or, if you need a fresh deployment, delete old volumes first:"
        echo -e "     ${BLUE}docker volume ls${NC}"
        echo -e "     ${BLUE}docker volume rm <volume_name>${NC}"
        echo -e "     ${BLUE}rm -rf -- $quoted_current_dir${NC}"
        echo -e "     Then re-run the deployment script"
        echo ""
        exit 0
    fi

    # Pull Docker images
    log_step "Pulling Docker images"
    $COMPOSE_CMD pull
    log_success "Image pull completed"

    # Start services
    log_step "Starting services"
    $COMPOSE_CMD up -d
    log_success "Service start command executed"

    # Wait for services to be ready
    log_step "Waiting for services to be ready"
    sleep 5

    # Wait for database health check
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "2" ]; then
        log_info "Waiting for Core database to be ready..."
        max_attempts=30
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if $COMPOSE_CMD exec -T postgres-core pg_isready -U peta -d peta_core_postgres > /dev/null 2>&1; then
                log_success "Core database is ready"
                break
            fi
            attempt=$((attempt + 1))
            echo -n "."
            sleep 2
        done
        echo ""

        if [ $attempt -eq $max_attempts ]; then
            log_error "Core database startup timeout"
            $COMPOSE_CMD logs postgres-core
            exit 1
        fi
    fi

    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "3" ]; then
        log_info "Waiting for Console database to be ready..."
        max_attempts=30
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if $COMPOSE_CMD exec -T postgres-console pg_isready -U peta -d peta_console_postgres > /dev/null 2>&1; then
                log_success "Console database is ready"
                break
            fi
            attempt=$((attempt + 1))
            echo -n "."
            sleep 2
        done
        echo ""

        if [ $attempt -eq $max_attempts ]; then
            log_error "Console database startup timeout"
            $COMPOSE_CMD logs postgres-console
            exit 1
        fi
    fi

    # Wait for service health check
    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "2" ]; then
        log_info "Waiting for Peta-Core to be ready..."
        if wait_for_health "http://localhost:${BACKEND_PORT}/health"; then
            log_success "Peta-Core is ready"
        else
            log_error "Peta-Core startup failed"
            $COMPOSE_CMD logs peta-core
            exit 1
        fi
    fi

    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "3" ]; then
        log_info "Waiting for Peta-Console to be ready..."
        if wait_for_health "http://localhost:${CONSOLE_PORT}"; then
            log_success "Peta-Console is ready"
        else
            log_error "Peta-Console startup failed"
            $COMPOSE_CMD logs peta-console
            exit 1
        fi
    fi

    # Display deployment success message
    echo ""
    log_step "Deployment completed!"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Peta Services Deployed Successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Access Information:${NC}"

    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "2" ]; then
        echo -e "  Core API:        ${BLUE}http://localhost:${BACKEND_PORT}${NC}"
        echo -e "  Core Health:     ${BLUE}http://localhost:${BACKEND_PORT}/health${NC}"
    fi

    if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
        echo -e "  Peta Auth:       ${BLUE}http://peta-auth:7788/healthz${NC} (internal-only)"
    fi

    if [ "$DEPLOY_MODE" = "1" ] || [ "$DEPLOY_MODE" = "3" ]; then
        echo -e "  Console Web:     ${BLUE}http://localhost:${CONSOLE_PORT}${NC}"
    fi

    echo ""
    echo -e "${CYAN}Configuration Files:${NC}"
    echo -e "  Deployment Dir:      ${BLUE}$(pwd)${NC}"
    echo -e "  docker-compose.yml:  ${BLUE}$(pwd)/docker-compose.yml${NC}"
    echo -e "  .env file:           ${BLUE}$(pwd)/.env${NC}"
    echo ""
    echo -e "${CYAN}Common Commands:${NC}"
    echo -e "  View logs:      ${BLUE}$COMPOSE_CMD logs -f${NC}"
    echo -e "  View status:    ${BLUE}$COMPOSE_CMD ps${NC}"
    echo -e "  Stop services:  ${BLUE}$COMPOSE_CMD down${NC}"
    echo -e "  Restart:        ${BLUE}$COMPOSE_CMD restart${NC}"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    note_num=1
    echo -e "  ${note_num}. Please keep the .env file secure, it contains sensitive password information"
    note_num=$((note_num + 1))
    echo -e "  ${note_num}. It is recommended to change default passwords in production"
    note_num=$((note_num + 1))
    if [ "$PETA_AUTH_AUTOSTART" = "true" ]; then
        echo -e "  ${note_num}. Peta Auth is internal-only; no host port is exposed. Check status via ${BLUE}$COMPOSE_CMD ps${NC}"
        note_num=$((note_num + 1))
    fi
    if [ "$DEPLOY_MODE" = "3" ]; then
        echo -e "  ${note_num}. Please ensure Core service is accessible at ${BLUE}http://localhost:${BACKEND_PORT}${NC}"
        note_num=$((note_num + 1))
        echo -e "  ${note_num}. To modify Core address, edit MCP_GATEWAY_URL in the .env file"
        note_num=$((note_num + 1))
    fi
    echo ""
}

# Error handling
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap 'log_error "Error occurred during deployment, please check logs"; exit 1' ERR
    main "$@"
fi

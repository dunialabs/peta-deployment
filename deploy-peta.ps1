# ====================================
# Peta Core & Console Unified Deployment Script (PowerShell)
# ====================================
# Supports selective deployment: Core only, Console only, or Both
# Windows version of deploy-peta.sh

# Stop on errors
$ErrorActionPreference = "Stop"

# ================== Configuration Variables ==================
$DEPLOY_DIR = if ($env:DEPLOY_DIR) { $env:DEPLOY_DIR } else { ".\peta-deployment" }
$BACKEND_PORT = if ($env:BACKEND_PORT) { $env:BACKEND_PORT } else { 3002 }
$CONSOLE_PORT = if ($env:CONSOLE_PORT) { $env:CONSOLE_PORT } else { 3000 }
$CORE_DB_PORT = if ($env:CORE_DB_PORT) { $env:CORE_DB_PORT } else { 5434 }
$CONSOLE_DB_PORT = if ($env:CONSOLE_DB_PORT) { $env:CONSOLE_DB_PORT } else { 5435 }
$PETA_VERSION = if ($env:PETA_VERSION) { $env:PETA_VERSION } else { "1.3.0" }

# Script-level variable for compose command
$script:COMPOSE_CMD = ""
$script:USE_COMPOSE_V2 = $false

# ================== Docker Compose Wrapper ==================
function Invoke-DockerCompose {
    param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)

    if ($script:USE_COMPOSE_V2) {
        & docker compose $Arguments
    } else {
        & docker-compose $Arguments
    }
}

# ================== Logging Functions ==================
function Log-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Log-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Log-Warn {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Log-Error {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Log-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

# ================== Utility Functions ==================

# Generate random password
function Generate-Password {
    param([int]$Length = 32)

    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).Substring(0, $Length)
}

# Check if command exists
function Test-Command {
    param([string]$Command)

    $exists = $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
    if (-not $exists) {
        Log-Error "$Command is not installed, please install $Command first"
        exit 1
    }
}

# Check if port is in use
function Test-Port {
    param([int]$Port)

    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return $null -eq $connection
}

# Interactive port input function
function Get-AlternativePort {
    param(
        [string]$PortDescription,
        [int]$CurrentPort,
        [int]$ForbiddenPort = 0
    )

    $firstAttempt = $true

    while ($true) {
        if ($firstAttempt) {
            Write-Host ""
            Log-Warn "Port $CurrentPort is already in use"
            Log-Info "Purpose: $PortDescription"
            Write-Host ""
            $firstAttempt = $false
        }

        $newPort = Read-Host "Please enter a new port number (1024-65535) or 'q' to quit"

        # Check if user wants to exit
        if ($newPort -eq "q" -or $newPort -eq "quit") {
            Write-Host ""
            Log-Info "User cancelled deployment"
            exit 0
        }

        # Validate port number format
        if ($newPort -notmatch '^\d+$') {
            Log-Error "Invalid input: port number must be numeric"
            continue
        }

        $newPortNum = [int]$newPort

        # Validate port number range
        if ($newPortNum -lt 1024 -or $newPortNum -gt 65535) {
            Log-Error "Port out of range: must be between 1024-65535"
            continue
        }

        # Check if conflicts with forbidden port
        if ($ForbiddenPort -ne 0 -and $newPortNum -eq $ForbiddenPort) {
            Log-Error "Port $newPortNum is already used by another service, please enter a different port"
            continue
        }

        # Check if new port is also in use
        if (-not (Test-Port -Port $newPortNum)) {
            Log-Error "Port $newPortNum is also in use, please enter a different port"
            continue
        }

        # Port available
        Write-Host ""
        Log-Success "Port $newPortNum is available"
        return $newPortNum
    }
}

# Wait for service health check
function Wait-ForHealth {
    param(
        [string]$Url,
        [int]$MaxAttempts = 30
    )

    Log-Info "Waiting for service health check..."

    for ($attempt = 0; $attempt -lt $MaxAttempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Log-Success "Service health check passed"
                return $true
            }
        }
        catch {
            # Continue waiting
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
    }

    Write-Host ""
    Log-Error "Service health check timeout"
    return $false
}

# Display deployment information
function Show-DeploymentInfo {
    param([string]$DeployDir = $DEPLOY_DIR)

    $envFile = Join-Path $DeployDir ".env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile
        $backendPort = ($envContent | Select-String "^BACKEND_PORT=").ToString().Split("=")[1]
        $consolePort = ($envContent | Select-String "^CONSOLE_PORT=").ToString().Split("=")[1]

        # Determine deployment mode
        $composeFile = Join-Path $DeployDir "docker-compose.yml"
        $composeContent = Get-Content $composeFile -Raw
        $hasCore = $composeContent -match "peta-core:"
        $hasConsole = $composeContent -match "peta-console:"
        $hasAuth = $composeContent -match "peta-auth:"

        Write-Host ""
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "Access Information:" -ForegroundColor Cyan

        if ($hasCore) {
            Write-Host "  Core API:        " -NoNewline
            Write-Host "http://localhost:$backendPort" -ForegroundColor Blue
            Write-Host "  Core Health:     " -NoNewline
            Write-Host "http://localhost:$backendPort/health" -ForegroundColor Blue
        }

        if ($hasConsole) {
            Write-Host "  Console Web:     " -NoNewline
            Write-Host "http://localhost:$consolePort" -ForegroundColor Blue
        }
        if ($hasAuth) {
            Write-Host "  Peta Auth:       " -NoNewline
            Write-Host "http://peta-auth:7788/healthz (internal-only)" -ForegroundColor Blue
        }

        Write-Host ""
        Write-Host "Configuration Files:" -ForegroundColor Cyan
        Write-Host "  Deployment Dir:      " -NoNewline
        Write-Host $DeployDir -ForegroundColor Blue
        Write-Host "  docker-compose.yml:  " -NoNewline
        Write-Host "$DeployDir\docker-compose.yml" -ForegroundColor Blue
        Write-Host "  .env file:           " -NoNewline
        Write-Host "$DeployDir\.env" -ForegroundColor Blue

        Write-Host ""
        Write-Host "Common Commands:" -ForegroundColor Cyan
        Write-Host "  View logs:      " -NoNewline
        Write-Host "cd $DeployDir; $script:COMPOSE_CMD logs -f" -ForegroundColor Blue
        Write-Host "  View status:    " -NoNewline
        Write-Host "cd $DeployDir; $script:COMPOSE_CMD ps" -ForegroundColor Blue
        Write-Host "  Stop services:  " -NoNewline
        Write-Host "cd $DeployDir; $script:COMPOSE_CMD down" -ForegroundColor Blue
        Write-Host "  Restart:        " -NoNewline
        Write-Host "cd $DeployDir; $script:COMPOSE_CMD restart" -ForegroundColor Blue
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host ""
    }
    else {
        Log-Warn ".env file not found, unable to display details"
    }
}

# Check existing volumes
function Test-ExistingVolume {
    param([string]$VolumeName)

    $volumes = docker volume ls --format "{{.Name}}" 2>$null
    return $volumes -contains $VolumeName
}

# ================== Docker Compose Generation Functions ==================

function New-DockerCompose {
    param([string]$DeployMode)

    $composeFile = "docker-compose.yml"
    Log-Step "Generating docker-compose.yml"

    # Generate file header
    $content = @"
services:
"@

    # Generate Core services
    if ($DeployMode -eq "1" -or $DeployMode -eq "2") {
        $content += @"

  # PostgreSQL for peta-core
  postgres-core:
    image: postgres:16-alpine
    container_name: peta-core-postgres-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: `${CORE_DB_USER}
      POSTGRES_PASSWORD: `${CORE_DB_PASSWORD}
      POSTGRES_DB: `${CORE_DB_NAME}
    ports:
      - '`${CORE_DB_PORT}:5432'
    volumes:
      - postgres_peta_core:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U `${CORE_DB_USER} -d `${CORE_DB_NAME}']
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - peta-network

  # Peta Core Service (MCP Gateway)
  peta-core:
    image: petaio/peta-core:`${PETA_VERSION}
    container_name: peta-core
    restart: unless-stopped
    user: root
"@
        $nl = [Environment]::NewLine
        if (-not $content.EndsWith($nl)) {
            $content += $nl
        }
        $dependsOnLines = @(
            "    depends_on:",
            "      postgres-core:",
            "        condition: service_healthy"
        )
        if ($script:PETA_AUTH_AUTOSTART -eq "true") {
            $dependsOnLines += "      peta-auth:"
            $dependsOnLines += "        condition: service_healthy"
        }
        $content += ($dependsOnLines -join $nl)
        $content += $nl
        $envBlock = @"
    environment:
      NODE_ENV: `${NODE_ENV}
      DATABASE_URL: `${CORE_DATABASE_URL}
      BACKEND_PORT: `${BACKEND_PORT}
      JWT_SECRET: `${CORE_JWT_SECRET}
      LOG_LEVEL: `${LOG_LEVEL}
      LOG_PRETTY: `${LOG_PRETTY}
      CLOUDFLARED_CONTAINER_NAME: `${CLOUDFLARED_CONTAINER_NAME}
      PETA_CORE_IN_DOCKER: "true"
      SKIP_DB_CONTAINER_START: "true"
      LAZY_START_ENABLED: `${LAZY_START_ENABLED}
      PETA_AUTH_AUTOSTART: `${PETA_AUTH_AUTOSTART}
      RESULT_CACHE_ENABLED: `${RESULT_CACHE_ENABLED}
      RESULT_CACHE_BACKEND: `${RESULT_CACHE_BACKEND}
      RESULT_CACHE_STRICT_STARTUP: `${RESULT_CACHE_STRICT_STARTUP}
      RESULT_CACHE_DEFAULT_TTL_SECONDS: `${RESULT_CACHE_DEFAULT_TTL_SECONDS}
      RESULT_CACHE_DEFAULT_ADMISSION_POLICY: `${RESULT_CACHE_DEFAULT_ADMISSION_POLICY}
      RESULT_CACHE_DEFAULT_ADMISSION_WINDOW_SECONDS: `${RESULT_CACHE_DEFAULT_ADMISSION_WINDOW_SECONDS}
      RESULT_CACHE_MAX_ENTRY_BYTES: `${RESULT_CACHE_MAX_ENTRY_BYTES}
      RESULT_CACHE_KEY_PREFIX: `${RESULT_CACHE_KEY_PREFIX}
      RESULT_CACHE_COMPRESS: `${RESULT_CACHE_COMPRESS}
      RESULT_CACHE_COMPRESSION_MIN_BYTES: `${RESULT_CACHE_COMPRESSION_MIN_BYTES}
      RESULT_CACHE_DB_SWEEP_INTERVAL_SECONDS: `${RESULT_CACHE_DB_SWEEP_INTERVAL_SECONDS}
      RESULT_CACHE_DB_SWEEP_BATCH_SIZE: `${RESULT_CACHE_DB_SWEEP_BATCH_SIZE}
      RESULT_CACHE_MEMORY_MAX_ENTRIES: `${RESULT_CACHE_MEMORY_MAX_ENTRIES}
      REDIS_URL: `${REDIS_URL}
      SKILLS_DIR: "/data/skills"
    ports:
      - '`${BACKEND_PORT}:`${BACKEND_PORT}'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./cloudflared:/app/cloudflared
      - ./skills:/data/skills  # Skills storage directory (enables auto host-path detection for child containers)
    networks:
      - peta-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:`${BACKEND_PORT}/health']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

"@
        $content += $envBlock.TrimStart("`r", "`n")
        if ($script:PETA_AUTH_AUTOSTART -eq "true") {
            $content += @'
  # Peta Auth Service (optional, internal-only)
  peta-auth:
    image: petaio/peta-auth:${PETA_VERSION}
    container_name: peta-auth-core
    restart: unless-stopped
    networks:
      - peta-network
    volumes:
      - peta-auth-core-data:/data
    healthcheck:
      test: ['CMD', '/usr/bin/bash', '-c', 'exec 3<>/dev/tcp/localhost/7788 || exit 1; printf "GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3; response=""; while IFS= read -r -t 2 line <&3; do response+="$$line"; done; [[ "$$response" == *"\"ok\":true"* ]]']
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s

'@
        }
        $content += @"
  # Cloudflared Service
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: `${CLOUDFLARED_CONTAINER_NAME}
    restart: "no"
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=`${CLOUDFLARE_TUNNEL_TOKEN:-}
    networks:
      - peta-network
    volumes:
      - ./cloudflared:/etc/cloudflared

"@
    }

    # Generate Console services
    if ($DeployMode -eq "1" -or $DeployMode -eq "3") {
        $content += @"

  # PostgreSQL for peta-console
  postgres-console:
    image: postgres:16-alpine
    container_name: peta-console-postgres-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: `${CONSOLE_DB_USER}
      POSTGRES_PASSWORD: `${CONSOLE_DB_PASSWORD}
      POSTGRES_DB: `${CONSOLE_DB_NAME}
    ports:
      - '`${CONSOLE_DB_PORT}:5432'
    volumes:
      - postgres_peta_console:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U `${CONSOLE_DB_USER} -d `${CONSOLE_DB_NAME}']
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - peta-network

  # Peta Console Service
  peta-console:
    image: petaio/peta-console:`${PETA_VERSION}
    container_name: peta-console
    restart: unless-stopped
    depends_on:
      postgres-console:
        condition: service_healthy
    environment:
      NODE_ENV: `${NODE_ENV}
      DATABASE_URL: `${CONSOLE_DATABASE_URL}
      PORT: `${CONSOLE_PORT}
      JWT_SECRET: `${CONSOLE_JWT_SECRET}
      NEXTAUTH_SECRET: `${NEXTAUTH_SECRET}
      NEXTAUTH_URL: `${NEXTAUTH_URL}
      MCP_GATEWAY_URL: `${MCP_GATEWAY_URL}
      LOG_SYNC_ENABLED: `${LOG_SYNC_ENABLED}
      LOG_SYNC_INTERVAL_MINUTES: `${LOG_SYNC_INTERVAL_MINUTES}
      MAX_LOGS_PER_REQUEST: `${MAX_LOGS_PER_REQUEST}
      LOG_BATCH_SIZE: `${LOG_BATCH_SIZE}
      LOG_SYNC_TIMEOUT: `${LOG_SYNC_TIMEOUT}
      LOG_SYNC_RETRY_ATTEMPTS: `${LOG_SYNC_RETRY_ATTEMPTS}
    ports:
      - '`${CONSOLE_PORT}:`${CONSOLE_PORT}'
    networks:
      - peta-network
    healthcheck:
      test: ['CMD', 'curl', '-f', 'http://localhost:`${CONSOLE_PORT}']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

"@
    }

    # Generate volumes configuration
    $content += @"
volumes:
"@

    if ($DeployMode -eq "1" -or $DeployMode -eq "2") {
        $content += @"

  postgres_peta_core:
    driver: local
"@
    }

    if ($script:PETA_AUTH_AUTOSTART -eq "true") {
        $content += @"

  peta-auth-core-data:
    driver: local
"@
    }

    if ($DeployMode -eq "1" -or $DeployMode -eq "3") {
        $content += @"

  postgres_peta_console:
    driver: local
"@
    }

    # Generate networks configuration
    $content += @"

networks:
  peta-network:
    driver: bridge
"@

    Set-Content -Path $composeFile -Value $content -Encoding UTF8
    Log-Success "docker-compose.yml generated successfully"
}

# ================== .env File Generation Functions ==================

function New-EnvFile {
    param([string]$DeployMode)

    $envFile = ".env"
    Log-Step "Generating .env file"

    # Generate file header
    $content = @"
# ====================================
# Peta Deployment Environment Variables
# ====================================
# Auto-generated by deploy-peta.ps1
# Please keep this file secure in production, do not expose passwords

# -------------------- General Configuration --------------------
NODE_ENV=production
PETA_VERSION=$PETA_VERSION

"@

    # Generate Core configuration
    if ($DeployMode -eq "1" -or $DeployMode -eq "2") {
        $CORE_JWT_SECRET = Generate-Password -Length 32
        $CORE_DB_PASSWORD = Generate-Password -Length 24

        $content += @"
# -------------------- Peta Core Configuration --------------------
# Core service port
BACKEND_PORT=$BACKEND_PORT

# Core database configuration
CORE_DB_USER=peta
CORE_DB_PASSWORD=$CORE_DB_PASSWORD
CORE_DB_NAME=peta_core_postgres
CORE_DB_PORT=$CORE_DB_PORT

# Core database connection string
CORE_DATABASE_URL="postgresql://`${CORE_DB_USER}:`${CORE_DB_PASSWORD}@postgres-core:5432/`${CORE_DB_NAME}?schema=public"

# Core JWT Secret
CORE_JWT_SECRET=$CORE_JWT_SECRET

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
# Leave empty to use peta-core default: peta:`${NODE_ENV}
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
PETA_AUTH_AUTOSTART=$script:PETA_AUTH_AUTOSTART

"@
    }

    # Generate Console configuration
    if ($DeployMode -eq "1" -or $DeployMode -eq "3") {
        $CONSOLE_JWT_SECRET = Generate-Password -Length 32
        $NEXTAUTH_SECRET = Generate-Password -Length 32
        $CONSOLE_DB_PASSWORD = Generate-Password -Length 24

        # Set MCP Gateway URL based on deployment mode
        if ($DeployMode -eq "1") {
            $MCP_GATEWAY_URL = "http://peta-core:`${BACKEND_PORT}"
        }
        else {
            $MCP_GATEWAY_URL = "http://localhost:`${BACKEND_PORT}"
        }

        $content += @"
# -------------------- Peta Console Configuration --------------------
# Console service port
CONSOLE_PORT=$CONSOLE_PORT

# Console database configuration
CONSOLE_DB_USER=peta
CONSOLE_DB_PASSWORD=$CONSOLE_DB_PASSWORD
CONSOLE_DB_NAME=peta_console_postgres
CONSOLE_DB_PORT=$CONSOLE_DB_PORT

# Console database connection string
CONSOLE_DATABASE_URL="postgresql://`${CONSOLE_DB_USER}:`${CONSOLE_DB_PASSWORD}@postgres-console:5432/`${CONSOLE_DB_NAME}?schema=public"

# Console authentication configuration
CONSOLE_JWT_SECRET=$CONSOLE_JWT_SECRET
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
NEXTAUTH_URL=http://localhost:$CONSOLE_PORT

# MCP Gateway connection configuration
MCP_GATEWAY_URL=$MCP_GATEWAY_URL

# Log synchronization configuration
LOG_SYNC_ENABLED=true
LOG_SYNC_INTERVAL_MINUTES=2
MAX_LOGS_PER_REQUEST=5000
LOG_BATCH_SIZE=500
LOG_SYNC_TIMEOUT=180000
LOG_SYNC_RETRY_ATTEMPTS=2

"@
    }

    Set-Content -Path $envFile -Value $content -Encoding UTF8
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetOwner([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $envFile -AclObject $acl
    Log-Success ".env file generated successfully"
    Log-Warn "Please keep the .env file secure, it contains sensitive password information"
}

# ================== Main Function ==================

function Main {
    Log-Step "Peta Core & Console Unified Deployment Script"
    Write-Host ""

    # Check environment dependencies
    Log-Step "Checking environment dependencies"
    Test-Command "docker"

    # Check docker compose version
    try {
        $composeV2 = docker compose version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $script:USE_COMPOSE_V2 = $true
            $script:COMPOSE_CMD = "docker compose"
            Log-Success "Docker Compose V2 is installed"
        }
        else {
            throw "V2 not found"
        }
    }
    catch {
        try {
            Test-Command "docker-compose"
            $script:USE_COMPOSE_V2 = $false
            $script:COMPOSE_CMD = "docker-compose"
            Log-Success "Docker Compose V1 is installed"
        }
        catch {
            Log-Error "Docker Compose is not installed, please install Docker Compose first"
            exit 1
        }
    }

    Log-Success "Docker environment check passed"

    # Check if deployment directory already exists
    Log-Step "Checking deployment environment"
    if (Test-Path $DEPLOY_DIR) {
        Log-Warn "Existing deployment detected: $DEPLOY_DIR"
        Write-Host ""
        Write-Host "Please choose an option:"
        Write-Host "  1) Start existing deployed services"
        Write-Host "  2) Complete redeployment (will delete all data!)"
        Write-Host ""
        $existingChoice = Read-Host "Please enter option [1-2]"

        # Validate input
        if ($existingChoice -notmatch '^[1-2]$') {
            Log-Error "Invalid option, please enter 1 or 2"
            exit 1
        }

        # Handle option 1: Direct start
        if ($existingChoice -eq "1") {
            Log-Step "Starting existing deployed services"
            Push-Location $DEPLOY_DIR

            # Check if services are already running
            $runningServices = Invoke-DockerCompose ps --services --filter "status=running" 2>$null
            if ($runningServices) {
                Log-Warn "Services are already running"
                Write-Host ""
                Write-Host "Service status:"
                Invoke-DockerCompose ps

                Show-DeploymentInfo -DeployDir "."

                Log-Info "To restart services, run: cd $DEPLOY_DIR; $script:COMPOSE_CMD restart"
                Pop-Location
                exit 0
            }

            # Start services
            Log-Info "Starting services..."
            Invoke-DockerCompose up -d

            # Wait and verify startup
            Start-Sleep -Seconds 3
            Write-Host ""
            Write-Host "Service status:"
            Invoke-DockerCompose ps
            Write-Host ""
            Log-Success "Services started"
            Pop-Location
            exit 0
        }

        # Handle option 2: Complete redeployment
        if ($existingChoice -eq "2") {
            Write-Host ""
            Log-Warn "Complete redeployment requires manual execution of the following steps:"
            Write-Host ""
            Write-Host "Step 1: Stop and remove all containers, networks and volumes" -ForegroundColor Cyan
            Write-Host "  cd $DEPLOY_DIR; $script:COMPOSE_CMD down -v; cd .." -ForegroundColor Blue
            Write-Host ""
            Write-Host "Step 2: Remove deployment directory" -ForegroundColor Cyan
            Write-Host "  Remove-Item -Recurse -Force $DEPLOY_DIR" -ForegroundColor Blue
            Write-Host ""
            Write-Host "Step 3: Re-run deployment script" -ForegroundColor Cyan
            Write-Host "  .\deploy-peta.ps1" -ForegroundColor Blue
            Write-Host ""
            Log-Error "⚠️  Warning: Running 'docker compose down -v' will permanently delete all database data!"
            Write-Host ""
            Log-Info "Please manually execute the above commands to complete redeployment"
            exit 0
        }
    }
    Log-Success "Deployment environment check passed"

    # Display deployment menu
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "    Peta Service Deployment Wizard" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Please select deployment mode:"
    Write-Host "  1) Deploy both Core and Console (recommended, full experience) [default]"
    Write-Host "  2) Deploy peta-core only (MCP Gateway)"
    Write-Host "  3) Deploy peta-console only (requires Core already deployed)"
    Write-Host ""

    # Get user choice
    $DEPLOY_MODE = Read-Host "Please enter option [1-3] (press Enter for default option 1)"
    if ([string]::IsNullOrWhiteSpace($DEPLOY_MODE)) {
        $DEPLOY_MODE = "1"
    }

    # Validate input
    if ($DEPLOY_MODE -notmatch '^[1-3]$') {
        Log-Error "Invalid option, please enter 1, 2 or 3"
        exit 1
    }

    # Optional peta-auth selection (only when deploying peta-core)
    $script:PETA_AUTH_AUTOSTART = "false"
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "2") {
        Write-Host ""
        Log-Warn "Peta Auth (optional) provides Peta-managed OAuth credentials (clientId/clientSecret)."
        Log-Warn "If you plan to use Peta-managed credentials, peta-auth is REQUIRED."
        Log-Warn "If you do NOT install it, any Peta-managed OAuth integration will fail when used."
        Log-Info "If you will only bring your own credentials, you can safely skip."
        Write-Host ""
        $petaAuthChoice = Read-Host "Install and start peta-auth service? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($petaAuthChoice)) {
            $petaAuthChoice = "y"
        }

        if ($petaAuthChoice -match '^[Nn]') {
            $script:PETA_AUTH_AUTOSTART = "false"
            Log-Warn "peta-auth will NOT be installed. Peta-managed OAuth features will error if used."
        }
        else {
            $script:PETA_AUTH_AUTOSTART = "true"
            Log-Info "peta-auth will be installed and started."
        }
    }

    # Display services to be deployed
    Write-Host ""
    Log-Info "Your selected deployment mode:"
    switch ($DEPLOY_MODE) {
        "1" {
            Log-Info "  - peta-core (MCP Gateway)"
            Log-Info "  - peta-console (Web Console)"
            Log-Info "  - postgres-core (Core database)"
            Log-Info "  - postgres-console (Console database)"
            Log-Info "  - cloudflared (Cloudflare Tunnel)"
            if ($script:PETA_AUTH_AUTOSTART -eq "true") {
                Log-Info "  - peta-auth (OAuth service, internal-only)"
            }
        }
        "2" {
            Log-Info "  - peta-core (MCP Gateway)"
            Log-Info "  - postgres-core (Core database)"
            Log-Info "  - cloudflared (Cloudflare Tunnel)"
            if ($script:PETA_AUTH_AUTOSTART -eq "true") {
                Log-Info "  - peta-auth (OAuth service, internal-only)"
            }
        }
        "3" {
            Log-Info "  - peta-console (Web Console)"
            Log-Info "  - postgres-console (Console database)"
            Log-Warn "  Note: Please ensure peta-core service is running at http://localhost:$BACKEND_PORT"
        }
    }
    Write-Host ""

    # Check port availability
    Log-Step "Checking port availability"

    # Check Core port
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "2") {
        Log-Info "Checking peta-core service port $BACKEND_PORT..."
        while (-not (Test-Port -Port $BACKEND_PORT)) {
            $BACKEND_PORT = Get-AlternativePort -PortDescription "peta-core service startup port" -CurrentPort $BACKEND_PORT
        }
        Log-Success "Core port $BACKEND_PORT is available"
    }

    # Check Console port
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "3") {
        Log-Info "Checking peta-console service port $CONSOLE_PORT..."
        while ((-not (Test-Port -Port $CONSOLE_PORT)) -or ($CONSOLE_PORT -eq $BACKEND_PORT)) {
            if ($CONSOLE_PORT -eq $BACKEND_PORT) {
                Log-Error "Console port cannot be the same as Core port"
            }
            $CONSOLE_PORT = Get-AlternativePort -PortDescription "peta-console service startup port" -CurrentPort $CONSOLE_PORT -ForbiddenPort $BACKEND_PORT
        }
        Log-Success "Console port $CONSOLE_PORT is available"
    }

    Log-Success "All port checks completed"

    # Create deployment directory
    Log-Step "Creating deployment directory"
    New-Item -ItemType Directory -Force -Path $DEPLOY_DIR | Out-Null
    Push-Location $DEPLOY_DIR
    Log-Success "Deployment directory: $(Get-Location)"

    # Check existing volumes
    Log-Step "Checking existing databases"
    $EXISTING_DB = $false
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "2") {
        if (Test-ExistingVolume -VolumeName "postgres_peta_core") {
            Log-Warn "Existing Core database volume detected"
            $EXISTING_DB = $true
        }
    }
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "3") {
        if (Test-ExistingVolume -VolumeName "postgres_peta_console") {
            Log-Warn "Existing Console database volume detected"
            $EXISTING_DB = $true
        }
    }

    # Generate configuration files
    New-DockerCompose -DeployMode $DEPLOY_MODE
    New-EnvFile -DeployMode $DEPLOY_MODE

    # Create cloudflared directory (if needed)
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "2") {
        Log-Step "Creating Cloudflared configuration directory"
        New-Item -ItemType Directory -Force -Path "cloudflared" | Out-Null
        Log-Success "Cloudflared configuration directory created"
    }

    # If existing database detected, prompt user
    if ($EXISTING_DB) {
        Write-Host ""
        Log-Warn "════════════════════════════════════════════════════════"
        Log-Warn "  Existing database volume detected!"
        Log-Warn "════════════════════════════════════════════════════════"
        Write-Host ""
        Log-Info "Configuration files generated, but services not started due to possible password mismatch."
        Write-Host ""
        Log-Info "Please follow these steps:"
        Write-Host "  1. Edit .env file to match existing database password:"
        Write-Host "     notepad $(Get-Location)\.env" -ForegroundColor Blue
        Write-Host ""
        Write-Host "  2. Modify the relevant configuration values"
        Write-Host ""
        Write-Host "  3. After modification, start services:"
        Write-Host "     cd $(Get-Location); $script:COMPOSE_CMD up -d" -ForegroundColor Blue
        Write-Host ""
        Log-Info "Or, if you need a fresh deployment, delete old volumes first:"
        Write-Host "     docker volume ls" -ForegroundColor Blue
        Write-Host "     docker volume rm <volume_name>" -ForegroundColor Blue
        Write-Host "     Remove-Item -Recurse -Force $(Get-Location)" -ForegroundColor Blue
        Write-Host "     Then re-run the deployment script"
        Write-Host ""
        Pop-Location
        exit 0
    }

    # Pull Docker images
    Log-Step "Pulling Docker images"
    Invoke-DockerCompose pull
    Log-Success "Image pull completed"

    # Start services
    Log-Step "Starting services"
    Invoke-DockerCompose up -d
    Log-Success "Service start command executed"

    # Wait for services to be ready
    Log-Step "Waiting for services to be ready"
    Start-Sleep -Seconds 5

    # Wait for database health check
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "2") {
        Log-Info "Waiting for Core database to be ready..."
        $maxAttempts = 30
        $attempt = 0
        $ready = $false
        while ($attempt -lt $maxAttempts) {
            try {
                $result = Invoke-DockerCompose exec -T postgres-core pg_isready -U peta -d peta_core_postgres 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Log-Success "Core database is ready"
                    $ready = $true
                    break
                }
            }
            catch {
                # Continue waiting
            }
            $attempt++
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 2
        }
        Write-Host ""

        if (-not $ready) {
            Log-Error "Core database startup timeout"
            Invoke-DockerCompose logs postgres-core
            Pop-Location
            exit 1
        }
    }

    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "3") {
        Log-Info "Waiting for Console database to be ready..."
        $maxAttempts = 30
        $attempt = 0
        $ready = $false
        while ($attempt -lt $maxAttempts) {
            try {
                $result = Invoke-DockerCompose exec -T postgres-console pg_isready -U peta -d peta_console_postgres 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Log-Success "Console database is ready"
                    $ready = $true
                    break
                }
            }
            catch {
                # Continue waiting
            }
            $attempt++
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 2
        }
        Write-Host ""

        if (-not $ready) {
            Log-Error "Console database startup timeout"
            Invoke-DockerCompose logs postgres-console
            Pop-Location
            exit 1
        }
    }

    # Wait for service health check
    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "2") {
        Log-Info "Waiting for Peta-Core to be ready..."
        if (Wait-ForHealth -Url "http://localhost:$BACKEND_PORT/health") {
            Log-Success "Peta-Core is ready"
        }
        else {
            Log-Error "Peta-Core startup failed"
            Invoke-DockerCompose logs peta-core
            Pop-Location
            exit 1
        }
    }

    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "3") {
        Log-Info "Waiting for Peta-Console to be ready..."
        if (Wait-ForHealth -Url "http://localhost:$CONSOLE_PORT") {
            Log-Success "Peta-Console is ready"
        }
        else {
            Log-Error "Peta-Console startup failed"
            Invoke-DockerCompose logs peta-console
            Pop-Location
            exit 1
        }
    }

    # Display deployment success message
    Write-Host ""
    Log-Step "Deployment completed!"
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Peta Services Deployed Successfully!" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Access Information:" -ForegroundColor Cyan

    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "2") {
        Write-Host "  Core API:        " -NoNewline
        Write-Host "http://localhost:$BACKEND_PORT" -ForegroundColor Blue
        Write-Host "  Core Health:     " -NoNewline
        Write-Host "http://localhost:$BACKEND_PORT/health" -ForegroundColor Blue
    }

    if ($script:PETA_AUTH_AUTOSTART -eq "true") {
        Write-Host "  Peta Auth:       " -NoNewline
        Write-Host "http://peta-auth:7788/healthz (internal-only)" -ForegroundColor Blue
    }

    if ($DEPLOY_MODE -eq "1" -or $DEPLOY_MODE -eq "3") {
        Write-Host "  Console Web:     " -NoNewline
        Write-Host "http://localhost:$CONSOLE_PORT" -ForegroundColor Blue
    }

    Write-Host ""
    Write-Host "Configuration Files:" -ForegroundColor Cyan
    Write-Host "  Deployment Dir:      " -NoNewline
    Write-Host "$(Get-Location)" -ForegroundColor Blue
    Write-Host "  docker-compose.yml:  " -NoNewline
    Write-Host "$(Get-Location)\docker-compose.yml" -ForegroundColor Blue
    Write-Host "  .env file:           " -NoNewline
    Write-Host "$(Get-Location)\.env" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Common Commands:" -ForegroundColor Cyan
    Write-Host "  View logs:      " -NoNewline
    Write-Host "$script:COMPOSE_CMD logs -f" -ForegroundColor Blue
    Write-Host "  View status:    " -NoNewline
    Write-Host "$script:COMPOSE_CMD ps" -ForegroundColor Blue
    Write-Host "  Stop services:  " -NoNewline
    Write-Host "$script:COMPOSE_CMD down" -ForegroundColor Blue
    Write-Host "  Restart:        " -NoNewline
    Write-Host "$script:COMPOSE_CMD restart" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Important Notes:" -ForegroundColor Yellow
    $noteNum = 1
    Write-Host "  $noteNum. Please keep the .env file secure, it contains sensitive password information"
    $noteNum++
    Write-Host "  $noteNum. It is recommended to change default passwords in production"
    $noteNum++
    if ($script:PETA_AUTH_AUTOSTART -eq "true") {
        Write-Host "  $noteNum. Peta Auth is internal-only; no host port is exposed. Check status via $script:COMPOSE_CMD ps"
        $noteNum++
    }
    if ($DEPLOY_MODE -eq "3") {
        Write-Host "  $noteNum. Please ensure Core service is accessible at " -NoNewline
        Write-Host "http://localhost:$BACKEND_PORT" -ForegroundColor Blue
        $noteNum++
        Write-Host "  $noteNum. To modify Core address, edit MCP_GATEWAY_URL in the .env file"
        $noteNum++
    }
    Write-Host ""

    Pop-Location
}

# ================== Entry Point ==================

try {
    Main
}
catch {
    Log-Error "Error occurred during deployment: $_"
    Log-Error $_.ScriptStackTrace
    exit 1
}

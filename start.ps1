<#
.SYNOPSIS
    Voice_AI_Engine - Script de Inicio Automatizado Multiplataforma para Windows
.DESCRIPTION
    Detecta automaticamente las especificaciones del hardware (CPU, RAM del host,
    RAM de Docker/WSL2, presencia de GPU NVIDIA y memoria VRAM disponible).
    Determina de forma inteligente el perfil optimo y recomendado (GPU vs CPU)
    para evitar fallos por falta de memoria (CUDA OOM o OOMKilled), informa
    al usuario las decisiones tomadas y levanta el subsistema de IA completo.
.PARAMETER Cpu
    Fuerza manualmente la ejecucion en perfil 100% CPU.
.PARAMETER ForceGpu
    Fuerza el uso de GPU incluso si la VRAM detectada es menor a la recomendada (6 GB).
.PARAMETER DryRun
    Realiza la deteccion de hardware y muestra el diagnostico sin iniciar contenedores.
#>

[CmdletBinding()]
param (
    [switch]$Cpu,
    [switch]$ForceGpu,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "         Voice AI Engine - Iniciador Inteligente para Windows   " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Verificar Docker y Docker Compose
try {
    $dockerVer = docker version --format "{{.Server.Version}}" 2>$null
    if (-not $dockerVer) {
        throw "El daemon de Docker no responde."
    }
    $null = docker compose version
} catch {
    Write-Host "`n[ERROR] Docker o Docker Compose v2 no estan disponibles o el servicio esta detenido." -ForegroundColor Red
    Write-Host "Inicie Docker Desktop y verifique que la integracion WSL2 este activa." -ForegroundColor Yellow
    exit 1
}

# 2. Configurar .env si no existe
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Write-Host "[INFO] Archivo .env no detectado. Creando plantilla desde .env.example..." -ForegroundColor Yellow
        Copy-Item ".env.example" ".env"
    } else {
        Write-Host "[WARN] No se encontro .env ni .env.example. Se utilizaran valores por defecto." -ForegroundColor Yellow
    }
}

# 3. Verificar o generar certificados SSL para Nginx si faltan
if (-not (Test-Path "nginx\certs\server.crt") -or -not (Test-Path "nginx\certs\server.key")) {
    Write-Host "[INFO] Certificados TLS no encontrados. Generando certificados autofirmados..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path "nginx\certs" | Out-Null
    docker run --rm -v "${PWD}/nginx/certs:/certs" alpine/openssl req -x509 -nodes -days 3650 -newkey rsa:2048 `
        -keyout /certs/server.key -out /certs/server.crt `
        -subj "/CN=voice-ai.local/O=Voice AI Engine/OU=AI Security" 2>$null
    Write-Host "[OK] Certificados generados correctamente." -ForegroundColor Green
}

# 4. Deteccion Exhaustiva de Hardware y Recursos
Write-Host "`n[INFO] Analizando arquitectura y especificaciones del equipo..." -ForegroundColor Cyan

# A. Memoria RAM Fisica del Host
$hostRamGb = 0
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs -and $cs.TotalPhysicalMemory) {
        $hostRamGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    }
} catch {}

# B. Recursos asignados a Docker / WSL2
$dockerRamGb = 0
$dockerCpus = 0
try {
    $memBytes = docker info --format "{{.MemTotal}}" 2>$null
    if ($memBytes) {
        $dockerRamGb = [math]::Round([int64]$memBytes / 1GB, 1)
    }
    $dockerCpus = [int](docker info --format "{{.NCPU}}" 2>$null)
} catch {}

# C. Deteccion de GPU NVIDIA y Memoria VRAM
$gpuDetected = $false
$gpuName = "Ninguna GPU NVIDIA compatible detectada"
$vramMb = 0
$vramGb = 0
$hasNvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue

if ($null -ne $hasNvidiaSmi) {
    try {
        $smiOutput = nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null
        if ($smiOutput) {
            $firstLine = if ($smiOutput -is [array]) { $smiOutput[0] } else { $smiOutput }
            $gpuParts = $firstLine -split ','
            if ($gpuParts.Length -ge 2) {
                $gpuName = $gpuParts[0].Trim()
                $vramMb = [int]($gpuParts[1].Trim())
                $vramGb = [math]::Round($vramMb / 1024, 1)
                $gpuDetected = $true
            }
        }
    } catch {}
}

# D. Verificacion de Soporte GPU en Docker
$dockerNvidiaSupport = $false
try {
    $dockerInfoStr = docker info 2>$null | Out-String
    if ($dockerInfoStr -match "nvidia" -or $dockerInfoStr -match "cdi: docker.com/gpu") {
        $dockerNvidiaSupport = $true
    }
} catch {}

$dockerGpuStatus = if ($dockerNvidiaSupport) { "Activo / Compatible" } else { "No disponible en Docker" }

# 5. Matriz Inteligente de Decision y Recomendacion
# Para correr Whisper Large-v3-turbo (CUDA float16 ~3.5GB) + Llama 3.1 8B (~4.7GB) en GPU simultaneamente se requieren >= 6 GB VRAM.
$MIN_VRAM_GB = 6.0
$useCpu = $false
$decisionReason = ""
$recommendationDetails = ""

if ($Cpu) {
    $useCpu = $true
    $decisionReason = "Modo forzado manualmente por el usuario mediante parametro -Cpu."
    $recommendationDetails = "Ejecucion 100% CPU."
} elseif (-not $gpuDetected) {
    $useCpu = $true
    $decisionReason = "No se detecto GPU NVIDIA compatible en el sistema host."
    $recommendationDetails = "Perfil universal CPU (int8) activado automaticamente."
} elseif (-not $dockerNvidiaSupport) {
    $useCpu = $true
    $decisionReason = "GPU ($gpuName) detectada en host, pero Docker Desktop no tiene configurado el runtime de NVIDIA."
    $recommendationDetails = "Perfil seguro CPU activado para evitar excepciones en el daemon Docker."
} elseif ($vramGb -lt $MIN_VRAM_GB) {
    if ($ForceGpu) {
        $useCpu = $false
        $decisionReason = "GPU forzada por parametro -ForceGpu a pesar de contar con $vramGb GB VRAM."
        $recommendationDetails = "ADVERTENCIA: Podrian ocurrir desbordamientos de memoria VRAM (CUDA OOM) con modelos grandes."
    } else {
        $useCpu = $true
        $decisionReason = "GPU detectada ($gpuName) dispone de $vramGb GB VRAM (Minimo recomendado: $MIN_VRAM_GB GB)."
        $recommendationDetails = "Para evitar caidas por falta de memoria de video (CUDA OOM) al cargar Whisper Large y Llama 3.1 8B, se recomienda y activa automaticamente el perfil 100% CPU optimizado (int8)."
    }
} else {
    $useCpu = $false
    $decisionReason = "GPU NVIDIA ($gpuName) con $vramGb GB VRAM y soporte Docker verificado."
    $recommendationDetails = "Aceleracion completa por GPU (CUDA/cuDNN) activada."
}

# 6. Panel Visual Informativo
Write-Host ""
Write-Host "+------------------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "|                DIAGNOSTICO AUTOMATICO DE HARDWARE                      |" -ForegroundColor Cyan
Write-Host "+------------------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  * Memoria RAM Host:        $hostRamGb GB" -ForegroundColor White
Write-Host "  * Recursos Docker/WSL2:    $dockerRamGb GB RAM | $dockerCpus vCPUs" -ForegroundColor White
if ($gpuDetected) {
    Write-Host "  * GPU Detectada:           $gpuName" -ForegroundColor White
    Write-Host "  * Memoria VRAM GPU:        $vramGb GB ($vramMb MB)" -ForegroundColor White
    Write-Host "  * Soporte Docker GPU:      $dockerGpuStatus" -ForegroundColor White
} else {
    Write-Host "  * GPU Detectada:           Ninguna GPU NVIDIA compatible" -ForegroundColor White
}
Write-Host "+------------------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "|                PERFIL SELECCIONADO Y RECOMENDACION                     |" -ForegroundColor Cyan
Write-Host "+------------------------------------------------------------------------+" -ForegroundColor Cyan
if ($useCpu) {
    Write-Host "  * MODO SELECCIONADO:       [ PERFIL 100% CPU OPTIMIZADO ]" -ForegroundColor Yellow
} else {
    Write-Host "  * MODO SELECCIONADO:       [ PERFIL ACELERACION GPU (CUDA) ]" -ForegroundColor Green
}
Write-Host "  * Causa / Diagnostico:     $decisionReason" -ForegroundColor Gray
Write-Host "  * Recomendacion Tecnica:   $recommendationDetails" -ForegroundColor Gray
Write-Host "+------------------------------------------------------------------------+" -ForegroundColor Cyan

# 7. Ejecucion del Despliegue con Docker Compose
if ($useCpu) {
    $composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.cpu.yml", "up", "-d", "--build")
} else {
    $composeArgs = @("-f", "docker-compose.yml", "up", "-d", "--build")
}

if ($DryRun) {
    Write-Host "`n[DRY RUN] Diagnostico finalizado sin iniciar contenedores." -ForegroundColor Cyan
    Write-Host "Comando resultante que se ejecutara:" -ForegroundColor White
    Write-Host "  docker compose $($composeArgs -join ' ')" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[INFO] Construyendo e iniciando contenedores en segundo plano..." -ForegroundColor Cyan
Write-Host "docker compose $($composeArgs -join ' ')" -ForegroundColor Yellow
Write-Host ""

& docker compose @composeArgs

# 8. Resumen de Servicios
Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "         Voice AI Engine iniciado exitosamente                  " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "* Puerta de Enlace Segura (HTTPS): https://localhost:8443" -ForegroundColor White
Write-Host "* Modulo RAG & Ingesta Documental: https://localhost:8443/rag/ui" -ForegroundColor White
Write-Host "* Healthcheck General:             https://localhost:8443/proxy-health" -ForegroundColor White
Write-Host "* Panel Bastionado Portainer:      https://localhost:9443" -ForegroundColor White
Write-Host "* Red de Contenedores Interna:     voice-ai-net (Aislamiento Total)" -ForegroundColor White
Write-Host "`nPara consultar logs en tiempo real:"
Write-Host "  docker compose $($composeArgs[0..($composeArgs.Length-4)] -join ' ') logs -f`n" -ForegroundColor Yellow

<#
.SYNOPSIS
    Voice_AI_Engine - Script de Inicio Automatizado para Windows
.DESCRIPTION
    Detecta automáticamente presencia de aceleración NVIDIA GPU o entorno CPU/WSL2,
    gestiona certificados TLS y variables de entorno, y levanta el subsistema de IA completo.
.PARAMETER Cpu
    Fuerza la ejecución en perfil 100% CPU sin requerir GPU NVIDIA.
#>

[CmdletBinding()]
param (
    [switch]$Cpu
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "         Voice AI Engine - Iniciador para Windows               " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Verificar Docker y Docker Compose
try {
    $null = docker --version
    $null = docker compose version
} catch {
    Write-Host "[ERROR] Docker o Docker Compose v2 no están disponibles en el PATH." -ForegroundColor Red
    Write-Host "Inicie Docker Desktop y verifique que la integración WSL2 esté activa."
    exit 1
}

# 2. Configurar .env si no existe
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Write-Host "[INFO] Archivo .env no detectado. Creando plantilla desde .env.example..." -ForegroundColor Yellow
        Copy-Item ".env.example" ".env"
    } else {
        Write-Host "[WARN] No se encontró .env ni .env.example. Se utilizarán valores por defecto." -ForegroundColor Yellow
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

# 4. Detección de Aceleración NVIDIA GPU vs CPU
$useCpu = $false

if ($Cpu) {
    Write-Host "[CONFIG] Modo forzado por parámetro: Ejecución 100% CPU." -ForegroundColor Yellow
    $useCpu = $true
} else {
    $hasNvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($null -eq $hasNvidiaSmi) {
        Write-Host "[INFO] No se detectó GPU NVIDIA ni utilitario nvidia-smi en el sistema." -ForegroundColor Yellow
        Write-Host "[INFO] Activando perfil optimizado 100% CPU." -ForegroundColor Yellow
        $useCpu = $true
    } else {
        Write-Host "[INFO] GPU NVIDIA detectada en el host Windows." -ForegroundColor Green
        Write-Host "[INFO] Activando perfil de aceleración por GPU (CUDA/cuDNN)." -ForegroundColor Green
    }
}

# 5. Ejecución del Despliegue con Docker Compose
if ($useCpu) {
    $composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.cpu.yml", "up", "-d", "--build")
} else {
    $composeArgs = @("-f", "docker-compose.yml", "up", "-d", "--build")
}

Write-Host "`n[INFO] Construyendo e iniciando contenedores en segundo plano..." -ForegroundColor Cyan
Write-Host "docker compose $($composeArgs -join ' ')" -ForegroundColor Yellow
Write-Host ""

& docker compose @composeArgs

# 6. Resumen de Servicios
Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "         Voice AI Engine iniciado exitosamente                  " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "• Puerta de Enlace Segura (HTTPS): https://localhost:8443" -ForegroundColor White
Write-Host "• Módulo RAG & Ingesta Documental: https://localhost:8443/rag/ui" -ForegroundColor White
Write-Host "• Healthcheck General:             https://localhost:8443/proxy-health" -ForegroundColor White
Write-Host "• Panel Bastionado Portainer:      https://localhost:9443" -ForegroundColor White
Write-Host "• Red de Contenedores Interna:     voice-ai-net (Aislamiento Total)" -ForegroundColor White
Write-Host "`nPara consultar logs en tiempo real:"
Write-Host "  docker compose $($composeArgs[0..($composeArgs.Length-4)] -join ' ') logs -f`n" -ForegroundColor Yellow

# Guía de Despliegue en Render.com (Entorno Estándar 100% CPU)

**Proyecto:** Voice AI Engine (TalitaKum AI Engine)  
**Objetivo:** Despliegue, optimización y operación en la nube [Render.com](https://render.com/) sobre instancias estándar sin GPU dedicada.  
**Fecha:** Octubre 2026  
**Versión:** 1.0.0  

---

## 1. Visión General de la Arquitectura en Render

En entornos de nube como Render.com, las instancias estándar funcionan exclusivamente sobre **CPU x86_64** sin acceso a aceleración por hardware NVIDIA CUDA. Para garantizar que el subsistema de transcripción fonética y estructuración clínica opere con alta disponibilidad, baja latencia y sin caídas por falta de memoria (Out-Of-Memory / OOM), se ha optimizado la pila completa:

1. **Inferencia Whisper por CPU:** Cuantización `int8` forzada (`WHISPER_COMPUTE_TYPE=int8`), conmutador `WHISPER_DEVICE=cpu` y selección de modelos ligeros (`tiny`, `base` o `small`).
2. **Inferencia Ollama en CPU:** Inferencia confinada a memoria del sistema (`OLLAMA_NUM_GPU=0`) con modelos de escala adaptada (1B a 7B parámetros) cuantizados en formato `q4_K_M`.
3. **Persistencia de Modelos:** Montaje de discos persistentes (*Render Persistent Disks*) para evitar descargas reiteradas de modelos durante reinicios de contenedores o despliegues automáticos.
4. **Auto-diagnóstico de Requerimientos:** Script instalador con verificaciones previas y auto-generación de dependencias.

---

## 2. Matriz de Selección de Modelos según Hardware (Tiers)

El instalador `install_render.sh` clasifica los recursos según la memoria RAM disponible o el plan contratado en Render:

| Tier | Plan Render Recomendado | Recursos Disponibles | Modelo Whisper (int8) | Modelo LLM (Ollama) | Consumo Estimado de RAM |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1 (Ultra-Ligero)** | Free / Starter | 512 MB – 2 GB RAM / 0.5 – 1 vCPU | `tiny` o `base` | `llama3.2:1b` o `qwen2.5:1.5b` | ~1.2 GB a 1.8 GB |
| **Tier 2 (Estándar Balanceado)** | Standard | 2 GB – 4 GB RAM / 1 – 2 vCPUs | `small` | `llama3.2:3b` o `qwen2.5:3b` | ~2.5 GB a 3.5 GB |
| **Tier 3 (Pro / Rendimiento)** | Pro / Pro Plus | 4 GB – 8 GB+ RAM / 2 – 4 vCPUs | `small` o `medium` | `llama3.1:8b-instruct-q4_K_M` o `qwen2.5:7b` | ~5.0 GB a 7.5 GB |

> [!IMPORTANT]
> En instancias Free o Starter de Render (512 MB a 1 GB), se recomienda **Tier 1** (`llama3.2:1b` + Whisper `tiny`). Modelos de 8B parámetros en este tipo de instancias ocasionarán la terminación inmediata del proceso por límite de memoria (OOM Killer de Linux).

---

## 3. Métodos de Despliegue

Dispones de dos alternativas para poner en marcha el subsistema en Render:

### Método A: Despliegue Automático mediante Render Blueprint (`render.yaml`)

El archivo [render.yaml](file:///c:/Users/Juan%20Carlos/Documents/Antigravity%20projects/TalitaKum_AI_Engine/render.yaml) define la infraestructura completa como código (IaC) para Render:

1. Ingresa a tu panel en [dashboard.render.com](https://dashboard.render.com/).
2. Haz clic en **New +** y selecciona **Blueprint**.
3. Conecta el repositorio de GitHub de este proyecto (`Voice_AI_Engine`).
4. Render leerá automáticamente [render.yaml](file:///c:/Users/Juan%20Carlos/Documents/Antigravity%20projects/TalitaKum_AI_Engine/render.yaml) y provisionará cuatro microservicios:
   - `voice-ai-gateway`: Web Service público expuesto por HTTPS (puerto `8080`), con healthcheck en `/health`.
   - `voice-ollama-service`: Private Service con disco persistente de 20 GB montado en `/home/ollama/.ollama`.
   - `voice-whisper-service`: Private Service con disco persistente de 10 GB montado en `/models`.
   - `voice-rag-service`: Private Service con disco persistente de 10 GB montado en `/app/data`.
5. Confirma la creación del Blueprint. Render construirá las imágenes Docker y arrancará los servicios.

### Método B: Despliegue con el Instalador Inteligente (`install_render.sh`)

Si ejecutas una máquina virtual Linux, servidor local sin GPU o el shell de depuración de Render:

#### 1. Verificación previa de requerimientos (Check-Only)
Inspecciona si el entorno cumple los requerimientos de CPU, RAM, disco y paquetes:
```bash
chmod +x install_render.sh
./install_render.sh --check-only
```

Si el archivo `requirements-render.txt` no existe en la raíz, el instalador lo creará automáticamente con las versiones verificadas.

#### 2. Modo Interactivo con Menú Guiado
Ejecuta el asistente para elegir visualmente el Tier y los modelos según tu presupuesto de RAM:
```bash
./install_render.sh
```

El script mostrará:
```text
================================================================
   Voice AI Engine - Render & Standard CPU Environment Setup    
================================================================

[INFO] Analyzing system hardware specifications...
Hardware Overview:
  - Architecture:     x86_64
  - System Memory:    3.8 GB RAM
  - CPU Cores:        2 vCPUs
  - Available Disk:   45.2 GB

Please choose a hardware profile tier:
1) Tier 1: Free / Starter (512MB - 2GB RAM) -> Whisper tiny/base + LLM 1B/1.5B
2) Tier 2: Standard (2GB - 4GB RAM)         -> Whisper small + LLM 3B
3) Tier 3: Pro / Dedicated (4GB - 8GB+ RAM) -> Whisper small/med + LLM 7B/8B
```

#### 3. Modo Automatizado / No Interactivo (CI/CD)
Puedes automatizar el despliegue con argumentos de línea de comandos:
```bash
# Despliegue directo Tier 2 iniciando contenedores:
./install_render.sh --tier 2 --start

# Despliegue directo Tier 1 con modelos específicos:
./install_render.sh --tier 1 --model llama3.2:1b --whisper tiny --start

# Generación de configuración en modo simulación (Dry Run):
./install_render.sh --tier 2 --dry-run
```

---

## 4. Archivo de Requerimientos (`requirements-render.txt`)

Para instalaciones locales sin Docker, pruebas automatizadas o entornos Python en Render, se dispone de [requirements-render.txt](file:///c:/Users/Juan%20Carlos/Documents/Antigravity%20projects/TalitaKum_AI_Engine/requirements-render.txt) con dependencias fijadas:

```text
fastapi>=0.110.0,<0.116.0
uvicorn[standard]>=0.28.0,<0.33.0
python-multipart>=0.0.9,<0.0.20
pydantic>=2.6.0,<2.11.0
pydantic-settings>=2.2.0,<2.8.0
faster-whisper>=1.0.0,<1.2.0
requests>=2.31.0,<3.0.0
httpx>=0.27.0,<0.29.0
pypdf>=4.0.0,<5.5.0
python-docx>=1.1.0,<1.2.0
pytest>=8.0.0,<9.0.0
pytest-asyncio>=0.23.0,<0.26.0
```

Instalación rápida:
```bash
python3 -m pip install -r requirements-render.txt
```

---

## 5. Variables de Entorno Clave para CPU en Render

Asegúrate de que las siguientes variables estén definidas en el `.env` o en la sección `envVars` de Render:

```ini
# Configuración Estricta CPU
HARDWARE_PROFILE=cpu

# Whisper en CPU con cuantización int8
WHISPER_DEVICE=cpu
WHISPER_COMPUTE_TYPE=int8
WHISPER_CPU_FALLBACK=true
WHISPER_MODEL=small

# Ollama en CPU
OLLAMA_NUM_GPU=0
OLLAMA_KEEP_ALIVE=24h
MODEL_NAME=llama3.2:3b
LLM_MODEL=llama3.2:3b

# Memoria de audio volátil
AUDIO_RAM_DIR=/tmp/audio_ram
MAX_AUDIO_SIZE_MB=25
```

---

## 6. Pruebas y Validación Post-Despliegue

Una vez completado el despliegue en Render:

1. **Healthcheck del API Gateway:**
   ```bash
   curl -s https://<tu-servicio-render>.onrender.com/health
   ```
   *Respuesta esperada:* `{"status": "healthy"}`

2. **Prueba de Inferencia Clínica con Fallback RAG:**
   ```bash
   curl -X POST "https://<tu-servicio-render>.onrender.com/api/v1/process-text" \
     -H "Content-Type: application/json" \
     -d '{
       "texto": "Usuario asistió a sesión individual refiriendo control de impulsos.",
       "anonimizar": true,
       "usar_rag": false
     }'
   ```

3. **Ejecución de la Suite de Pruebas Unitaria:**
   ```bash
   python3 -m unittest test_engine.py
   ```

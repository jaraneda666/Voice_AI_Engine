# Voice_AI_Engine

**Subsistema Local On-Premise de Inteligencia Artificial para Salud Mental y Adicciones**  
*Private & Autonomous Clinical Speech & Medical NLP Subsystem*  

[![Docker](https://img.shields.io/badge/Docker-Compose_v2-2496ED?logo=docker&logoColor=white)](#)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)](#)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white)](#)
[![Faster-Whisper](https://img.shields.io/badge/Whisper-large--v3--turbo-orange)](#)
[![Ollama](https://img.shields.io/badge/Ollama-Llama_3.1_8B-black?logo=ollama&logoColor=white)](#)
[![Security](https://img.shields.io/badge/Security-TLS_1.3_|_CIS_Docker_v1.6-red)](#)
[![Compliance](https://img.shields.io/badge/Compliance-Ley_21.719_|_Ley_20.584-green)](#)

---

## 1. Descripción del Proyecto

`Voice_AI_Engine` es una plataforma desacoplada y bastinada de Inteligencia Artificial local diseñada para procesar registros clínicos y sesiones terapéuticas mediante audio o texto. Su diseño garantiza privacidad absoluta, confidencialidad médica y ausencia de persistencia en disco de datos biométricos de voz.

### Capacidades Centrales

1. **Transcripción Fonética Volátil:** Procesa archivos de audio en memoria RAM volátil (`tmpfs` en `/tmp/audio_ram`) mediante `faster-whisper` (`large-v3-turbo`) y ejecuta destrucción física irreversible tras la transcripción (Ley N° 21.719).
2. **Pasarela de Anonimización Perimetral Reversible:** Tokeniza identidades sensibles (RUTs chilenos, nombres de pacientes y profesionales) bajo las Leyes N° 19.628 y 20.584 antes de cualquier inferencia analítica.
3. **Estructuración Clínica con LLM Local:** Homologa relatos terapéuticos en tres campos normalizados (`objetivo`, `intervencion`, `acciones_a_seguir`) con Ollama (`llama3.1:8b-instruct-q4_K_M`) y mitigación de inyección de prompts bajo OWASP LLM 2025.
4. **Motor RAG e Ingesta Documental:** Panel web seguro para cargar manuales clínicos (PDF, DOCX, TXT), convertirlos a Markdown, destruir de forma criptográfica el original e indexar fragmentos semánticos para inyectar como contexto al LLM.
5. **Perímetro Cifrado y Aislamiento de Red:** Nginx con TLS 1.3 y lista blanca de IPs autorizadas como única puerta de enlace. Cero puertos de motores de IA expuestos al host.
6. **Portabilidad de Hardware:** Configurable para operar con aceleración GPU (NVIDIA CUDA / Tensor Cores) o conmutar a 100% CPU puro con cuantización `int8`.
7. **Guardrails y Mitigación de Red Team (OWASP LLM 2025):** Aislamiento XML estricto de contexto RAG (`<trusted_rag_context>`) contra suplantación (*Context Spoofing*), guardrail post-inferencia que neutraliza comandos SQL o código ejecutable en campos clínicos, y esquemas Pydantic resilientes contra DoS con certificación pericial.

---

## 2. Arquitectura y Topología de Red

El sistema opera mediante seis microservicios aislados en la red privada interna `voice-ai-net`:

```text
[Cliente Externo / Terapeuta / PWA]
                 │
                 │ HTTPS (TLS 1.3 / Puerto 8443)
                 ▼
      ┌─────────────────────┐
      │   voice-nginx-proxy   │ (Terminación SSL, Rate-Limiting, Whitelist IPs)
      └──────────┬──────────┘
                 │
  Red Privada Interna (voice-ai-net) - Cero puertos de IA expuestos al host
  ───────────────┬────────────────────────────────────────────────────────
                 ├──────────────────────────────┐
                 ▼                              ▼
      ┌─────────────────────┐        ┌─────────────────────┐
      │   voice-ai-gateway    │        │   voice-rag-service   │ (Puerto 8090)
      │   (FastAPI / 8080)  │◄───────┤ (Dashboard Web /    │
      └──────────┬──────────┘        │  Markdown e Index)  │
                 │                   └─────────────────────┘
        ┌────────┴────────┐
        ▼                 ▼
 ┌───────────────────────┐ ┌───────────────────────┐        ┌─────────────────────┐
 │ voice-whisper-service │ │ voice-ollama-service  │        │    voice-portainer    │
 │     (Puerto 8000)     │ │    (Puerto 11434)     │        │ (HTTPS Puerto 9443) │
 └───────────────────────┘ └───────────────────────┘        └─────────────────────┘
```

---

## 3. Matriz de Puertos y Servicios

| Contenedor | Imagen | Puerto Interno | Puerto Host | Protocolo y Seguridad |
| :--- | :--- | :--- | :--- | :--- |
| **`voice-nginx-proxy`** | `nginx:1.27-alpine` | `8443` | `127.0.0.1:8443` | HTTPS / TLS 1.3 / Whitelist de IPs |
| **`voice-portainer`** | `portainer/portainer-ce:2.21.5` | `9443` | `127.0.0.1:9443` | HTTPS Seguro (Certificado SSL) |
| **`voice-rag-service`** | `voice-rag-service:1.0.0` | `8090` | *Sin exposición* | Aislado en red privada `voice-ai-net` |
| **`voice-ai-gateway`** | `voice-ai-gateway:1.0.0` | `8080` | *Sin exposición* | Aislado en red privada `voice-ai-net` |
| **`voice-whisper-service`** | `voice-whisper-service:1.0.0` | `8000` | *Sin exposición* | Aislado en red privada `voice-ai-net` |
| **`voice-ollama-service`** | `voice-ollama-service:1.0.0` | `11434` | *Sin exposición* | Aislado en red privada `voice-ai-net` |

---

## 4. Requisitos y Portabilidad de Hardware

### Perfil con Aceleración GPU (NVIDIA CUDA)
- **Tarjeta Gráfica:** NVIDIA con arquitectura Pascal, Turing, Ampere, Ada Lovelace o superior (**mínimo 6 GB a 8 GB de VRAM** para ejecutar simultáneamente Whisper Large y Llama 3.1 8B).
- **Software:** NVIDIA Container Toolkit instalado y operativo en el daemon de Docker.
- **Configuración:** `WHISPER_DEVICE=cuda`, `WHISPER_COMPUTE_TYPE=float16`, `OLLAMA_NUM_GPU=99`.
- **Comando de inicio:**
  ```bash
  docker compose up -d --build
  ```

### Perfil Universal por CPU (Sin GPU NVIDIA o GPUs con VRAM < 6 GB)
- **Procesador:** CPU x86_64 o ARM64 con soporte de instrucciones AVX2 (8 hilos recomendados).
- **Memoria RAM:** 8 GB a 16 GB asignados al motor Docker / WSL2.
- **Ajuste Automático:** Equipos con GPU dedicada pero con VRAM inferior a 6 GB (como la GTX 1650 de 4 GB) son conmutados automáticamente a este perfil por el iniciador para prevenir caídas críticas por *CUDA Out of Memory*.
- **Configuración:** Inferencia con cuantización `int8` en Whisper y ejecución en RAM para Ollama (`OLLAMA_NUM_GPU=0`, límite seguro calibrado a 6 GB).
- **Comando de inicio:**
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d --build
  ```

### Despliegue en la Nube / Render.com (Instancias Estándar sin GPU)
- **Instancias Soportadas:** Render Free, Starter, Standard o Pro.
- **Optimización de Modelos por RAM:**
  - **Tier 1 (512 MB - 2 GB RAM):** Whisper `tiny`/`base` (int8) + `llama3.2:1b` / `qwen2.5:1.5b`.
  - **Tier 2 (2 GB - 4 GB RAM):** Whisper `small` (int8) + `llama3.2:3b` / `qwen2.5:3b`.
  - **Tier 3 (4 GB - 8 GB+ RAM):** Whisper `small`/`medium` (int8) + `llama3.1:8b-instruct-q4_K_M` / `qwen2.5:7b`.
- **Despliegue IaC:** Utiliza el Blueprint [render.yaml](render.yaml) o el instalador interactivo [install_render.sh](install_render.sh).
- **Guía Completa:** Ver [docs/despliegue-render-cpu.md](docs/despliegue-render-cpu.md).

---

## 5. Guía Rápida de Despliegue (Quickstart)

### 1. Clonar el Repositorio
```bash
git clone https://github.com/jaraneda666/Voice_AI_Engine.git
cd Voice_AI_Engine
```

### 2. Inicio Automático con Detección Inteligente de Hardware (Recomendado)

El repositorio incluye iniciadores inteligentes que inspeccionan en tiempo real la arquitectura, la RAM física, los vCPUs de Docker, la presencia de GPU NVIDIA y la memoria VRAM disponible (`nvidia-smi`), seleccionando y justificando de forma automática el perfil óptimo (GPU o CPU):

- **Linux / macOS:**
  ```bash
  chmod +x start.sh
  ./start.sh
  ```
  *Banderas disponibles:*
  * `./start.sh --dry-run` : Ejecuta diagnóstico de hardware y muestra el perfil recomendado sin iniciar contenedores.
  * `./start.sh --cpu` : Fuerza el modo 100% CPU.
  * `./start.sh --force-gpu` : Fuerza el uso de GPU incluso si la VRAM es inferior a 6 GB.

- **Windows (PowerShell):**
  ```powershell
  .\start.ps1
  ```
  *Banderas disponibles:*
  * `.\start.ps1 -DryRun` : Diagnóstico e informe en consola sin desplegar contenedores.
  * `.\start.ps1 -Cpu` : Fuerza el perfil 100% CPU optimizado.
  * `.\start.ps1 -ForceGpu` : Fuerza el uso de GPU en tarjetas con VRAM reducida.

### 3. Despliegue en Render.com o Servidores Estándar CPU

Para desplegar en la nube sin GPU dedicada ([Render.com](https://render.com/) o Linux CPU):

- **Instalador automatizado con menú interactivo según RAM:**
  ```bash
  chmod +x install_render.sh
  ./install_render.sh
  ```
  *Banderas disponibles:*
  * `./install_render.sh --check-only` : Diagnóstico de requisitos (RAM, CPU, disco, Docker, Python).
  * `./install_render.sh --tier 1|2|3` : Selección directa de modelo según plan de hardware.
  * `./install_render.sh --dry-run` : Genera y valida la configuración sin iniciar servicios.
  * `./install_render.sh --tier 2 --start` : Configura e inicia los contenedores directamente.

- **Despliegue Infrastructure as Code (Render Blueprint):**
  Conecte este repositorio en el Dashboard de Render y seleccione `Blueprint` para aprovisionar automáticamente el stack usando [render.yaml](render.yaml).

### 4. Opcional: Inicio Manual con Docker Compose

Si prefiere iniciar manualmente:
```bash
cp .env.example .env

# Perfil Acelerado por GPU NVIDIA (CUDA):
docker compose up -d --build

# Perfil Universal 100% CPU (macOS, Linux o Windows sin GPU):
docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d --build
```

### 4. Verificar Estado de Salud
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```
Los seis contenedores deben figurar con estado `Up` y `(healthy)`.

---

## 6. Uso del Módulo RAG e Ingesta Documental

Ingrese a la consola web segura desde su navegador:

```text
https://127.0.0.1:8443/rag/
```

1. **Subir Documento:** Seleccione o arrastre un archivo en formato **PDF**, **DOCX** o **TXT** (manuales de adicciones, protocolos de crisis, pautas clínicas).
2. **Transformación:** El microservicio extrae la estructura textual y la convierte a Markdown (`.md`).
3. **Destrucción Criptográfica del Original:** El archivo subido se sobrescribe con bytes cero y aleatorios mediante `fsync` y se purga con `unlink`. El original desaparece físicamente sin remanencia en disco.
4. **Indexación y Consulta:** El documento se particiona en fragmentos vectorizados mediante similitud de coseno, quedando listo para inyectarse en los prompts de Ollama.

---

## 7. Integración de la API REST

Todas las llamadas deben emitirse por HTTPS hacia el puerto **8443**.

### 7.1. Estructuración de Texto Clínico con RAG

**Endpoint:** `POST https://127.0.0.1:8443/api/v1/process-text`  
**Content-Type:** `application/json`  

#### Ejemplo con cURL:
```bash
curl -k -X POST "https://127.0.0.1:8443/api/v1/process-text" \
  -H "Content-Type: application/json" \
  -d '{
    "texto": "El paciente Juan Perez presenta episodio agudo de craving tras conflicto familiar. Se muestra ansioso y pide abandonar la comunidad.",
    "anonimizar": true,
    "usar_rag": true,
    "paciente_nombre": "Juan Perez",
    "paciente_rut": "12.345.678-5"
  }'
```

#### Respuesta de la API (HTTP 200 OK):
```json
{
  "status": "success",
  "transcripcion_original": "El paciente Juan Perez presenta episodio agudo de craving...",
  "anonimizacion_aplicada": true,
  "rag_consultado": true,
  "fragmentos_rag": [
    {
      "score": 0.6902,
      "title": "Protocolo Craving Clinico",
      "text": "## Intervencion en Crisis de Deseo Intenso (Craving) 1. Detener actividad del usuario..."
    }
  ],
  "entidades_detectadas": 2,
  "estructura_clinica": {
    "objetivo": "Gestionar el episodio agudo de craving y prevenir el abandono del tratamiento",
    "intervencion": "Aplicacion de tecnica de respiracion 4-7-8, hidratacion con sales y contencion por terapeuta par segun protocolo institucional",
    "acciones_a_seguir": "Monitoreo continuo de ansiedad, seguimiento en asamblea comunitaria y evaluacion medica si craving supera 8/10"
  },
  "normativa_cumplida": [
    "Ley N° 21.719 (Datos Biometricos y Personales)",
    "Ley N° 20.584 (Ficha Clinica y Salud Mental)",
    "Ley N° 19.628 (Vida Privada)",
    "OWASP Top 10 for LLM Applications 2025",
    "CIS Docker Benchmark v1.6.0"
  ]
}
```

### 7.2. Transcripción de Audio Volátil y Estructuración

**Endpoint:** `POST https://127.0.0.1:8443/api/v1/process-audio`  
**Content-Type:** `multipart/form-data`  

```bash
curl -k -X POST "https://127.0.0.1:8443/api/v1/process-audio" \
  -F "file=@sesion_clinica.webm;type=audio/webm" \
  -F "anonimizar=true" \
  -F "usar_rag=true" \
  -F "paciente_nombre=Juan Perez" \
  -F "paciente_rut=12.345.678-5"
```

El audio se procesa en el volumen volátil `/tmp/audio_ram` y es eliminado inmediatamente después de la inferencia fonética.

---

## 8. Estructura del Repositorio

```text
Voice_AI_Engine/
├── core/                       # Núcleo analítico: pipeline, anonimizador y API REST
├── gateway-service/            # Dockerfile y contexto del orquestador interno (8080)
├── whisper-service/            # Motor Faster-Whisper con destrucción de audio en RAM
├── ollama-service/             # Motor Ollama no-root con modelo Llama 3.1 8B
├── rag-service/                # Ingesta documental, shredding, Markdown y búsqueda vectorial
│   ├── app/                    # Código de servicio FastAPI y Dashboard Web HTML/JS
│   └── data/                   # Volumen persistente para archivos Markdown (.md) e índices
├── nginx/                      # Configuración de proxy inverso TLS 1.3 y certificados
├── docs/                       # Documentación técnica, manuales y especificaciones
│   ├── manual-de-uso-e-integracion.md
│   ├── manual-de-arquitectura-e-integracion.pdf # Manual integral unificado en PDF (14 págs.)
│   ├── arquitectura-rag-portabilidad.md
│   ├── arquitectura_motor.md
│   ├── reporte-de-pruebas-y-validacion.md  # Certificación de pruebas empíricas
│   ├── despliegue-render-cpu.md            # Guía completa de despliegue en Render (CPU)
│   └── reporte-pericial-pentesting-y-saneacion.md # Auditoría Red Team y certificación de saneamiento
├── output/                     # Entregables procesados y consolidados
│   └── manual-de-arquitectura-e-integracion.pdf # Documento PDF oficial de arquitectura e integración
├── tools/                      # Herramientas de soporte y automatización
│   └── build_integrated_pdf.py # Compilador automatizado de PDF con Playwright Chromium
├── test_engine.py              # Suite de pruebas unitarias y de integración
├── test_rag.py                 # Script de prueba integral del motor RAG
├── docker-compose.yml          # Orquestación de contenedores (Perfil GPU)
├── docker-compose.cpu.yml      # Override de portabilidad para entornos 100% CPU
├── render.yaml                 # Blueprint IaC para Render.com (Estándar CPU)
├── install_render.sh           # Instalador inteligente y menú para Render / Linux CPU
├── requirements-render.txt     # Dependencias consolidadas para Render y pruebas CPU
├── start.sh                    # Lanzador inteligente para Linux y macOS (GPU/CPU auto)
├── start.ps1                   # Lanzador inteligente para Windows PowerShell (GPU/CPU auto)
├── .gitattributes              # Normalización estricta de saltos de línea LF
├── .env.example                # Plantilla de variables de entorno
└── .gitignore                  # Exclusiones de seguridad (secretos, certs y temporales)
```

---

## 9. Monitoreo y Administración

- **Consola Portainer CE:** Ingrese a `https://127.0.0.1:9443` para supervisar el uso de CPU, memoria RAM y registros de depuración de cada microservicio.
- **Reporte Certificado de Pruebas Operativas:** Consulte [docs/reporte-de-pruebas-y-validacion.md](docs/reporte-de-pruebas-y-validacion.md) para ver la validación funcional de los 6 microservicios.
- **Auditoría Red Team y Saneamiento:** Consulte [docs/reporte-pericial-pentesting-y-saneacion.md](docs/reporte-pericial-pentesting-y-saneacion.md) para ver la matriz pericial CVSS v4.0, PoCs y evidencias fotográficas de re-test.
- **Verificación de Salud de APIs:**
  ```bash
  python test_engine.py
  ```

---

## 10. Resolución Rápida de Problemas (Troubleshooting)

| Problema / Síntoma | Causa Frecuente | Solución Inmediata |
| :--- | :--- | :--- |
| `ERROR: additional privileges requested: network.host` | BuildKit bloqueando acceso a red de host en Docker Desktop | Resuelto: Se eliminó `network: host` de los bloques `build:`. Las dependencias usan espejos duales |
| `Conflict. The container name "/voice-..." is already in use` | Contenedores creados previamente en otra ruta con diferente nombre de proyecto | Resuelto: `docker-compose.yml` fija `name: voice_ai_engine` para unificar el espacio de nombres |
| `pull access denied` en clon limpio | Intentar ejecutar `docker compose up -d` sin construir localmente | Usar `./start.sh` (o `.\start.ps1`) o agregar `--build`: `docker compose up -d --build` |
| `bash\r: No such file or directory` | Scripts shell con saltos de línea CRLF de Windows | Se previene con `.gitattributes`. Si editó manualmente, convierta con `dos2unix` o Python a LF |
| `could not select device driver ""` | Falta de GPU NVIDIA o Docker en macOS | Ejecutar con perfil CPU: `./start.sh --cpu` o `docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d --build` |
| `CUDA out of memory` en GPUs de 4 GB | Whisper Large y Llama 8B superan la VRAM de la GPU | El iniciador conmuta automáticamente a CPU. O ejecute manualmente con `-Cpu` |
| Error 403 Forbidden en Nginx | IP de cliente fuera de la lista blanca | Modificar bloque `allow` en `nginx/nginx.conf` y reiniciar: `docker compose restart nginx-proxy` |
| Alertas SSL en navegador o cURL | Certificados TLS autofirmados locales | Usar `-k` en cURL o `verify=False` en scripts de prueba. En producción reemplace por Let's Encrypt |

Consulte la [Guía Completa de Troubleshooting](docs/manual-de-uso-e-integracion.md#7-diagnóstico-y-resolución-de-problemas-troubleshooting) para detalles exhaustivos.

---

## 11. Licencia y Confidencialidad

Desarrollado para centros de salud mental y terapia especializada con fines de apoyo clínico bajo estrictos acuerdos de confidencialidad médica y protección de datos sensibles.

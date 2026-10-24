# Arquitectura del Microservicio RAG y Portabilidad de Hardware

**Proyecto:** Voice_AI_Engine (Centro de Salud Mental y Terapia Especializada)  
**Normativas de Cumplimiento:** Ley N° 21.719 (Chile) | Ley N° 20.584 | OWASP Top 10 API Security | OWASP Top 10 for LLM Applications 2025 | CIS Docker Benchmark v1.6.0  

---

## 1. Módulo RAG & Ingesta Documental (`voice-rag-service`)

### 1.1. Propósito y Flujo Operativo
El microservicio `rag-service` permite a terapeutas, psicólogos y coordinadores clínicos incorporar guías terapéuticas, manuales de adicciones, protocolos de craving y pautas institucionales para que el modelo local Ollama (`llama3.1:8b-instruct-q4_K_M`) fundamente su estructuración en el conocimiento validado de la Institución de Salud Especializada.

```text
[Cliente / Terapeuta]
         │ (HTTPS / TLS 1.3 - Puerto 8443)
         ▼
 ┌───────────────┐
 │  Nginx Proxy  │ (Terminación SSL, Whitelist de Hosts e IPs)
 └───────┬───────┘
         │ (Red Privada Aislada: voice-ai-net)
         ▼
 ┌──────────────────────────────────────────────────────────────┐
 │                    voice-rag-service (8090)                    │
 │ 1. Recepción en RAM volátil (/tmp/rag_uploads)               │
 │ 2. Transformación a Markdown estructurado (.md)              │
 │ 3. Destrucción Criptográfica del Original (PDF/DOCX/TXT)    │
 │ 4. Partición semántica (Chunks de 600 palabras)              │
 │ 5. Indexación Vectorial (Similitud de Coseno / Embeddings)   │
 └──────────────────────────────┬───────────────────────────────┘
                                │ Contexto Relevante Inyectado
                                ▼
 ┌──────────────────────────────────────────────────────────────┐
 │                   voice-ai-gateway (8080)                      │
 │ Inyecta fragmentos RAG en prompt delimitado OWASP LLM 2025   │
 └──────────────────────────────┬───────────────────────────────┘
                                │
                                ▼
 ┌──────────────────────────────────────────────────────────────┐
 │                  voice-ollama-service (11434)                  │
 │ Inferencia clínica estructurada con base institucional      │
 └──────────────────────────────────────────────────────────────┘
```

---

### 1.2. Política Estricta de Destrucción Física del Archivo Original (Ley N° 21.719)
Para garantizar la privacidad y prevenir cualquier filtración de documentos que contengan datos personales o identificatorios, el sistema implementa la rutina `secure_shred_file()`:

1. **Paso 1 (Sobrescritura Cero):** El archivo original en `/tmp/rag_uploads` es reescrito en su totalidad con bytes `0x00`.
2. **Paso 2 (Sobrescritura Pseudoaleatoria):** Se sobrescribe con bytes criptográficos generados por `os.urandom(size)`.
3. **Paso 3 (Sincronización Física a Disco):** Se invoca `os.fsync(f.fileno())` para forzar la escritura en el almacenamiento físico, impidiendo que los bloques queden en memoria intermedia.
4. **Paso 4 (Purga del Enlace):** Se desvincula el inodo del archivo con `os.unlink()`.
5. **Persistencia Exclusiva:** Únicamente se almacena el archivo derivado en formato Markdown (`.md`) dentro del volumen seguro persistente `/app/data/markdown`.

---

## 2. Portabilidad de Hardware (CPU, GPU y RAM)

El subsistema fue concebido bajo el principio de **independencia de arquitectura**, permitiendo su despliegue tanto en servidores dedicados con tarjetas aceleradoras NVIDIA como en servidores convencionales, nodos NAS o laptops de profesionales que operan exclusivamente sobre CPU.

### 2.1. Matriz de Dimensionamiento de Recursos

| Componente | Perfil GPU (Acelerado) | Perfil CPU Puro (Universal) | Límite RAM Recomendado |
| :--- | :--- | :--- | :--- |
| **whisper-service** | CUDA (`float16`) | CPU (`int8`) con fallback automático | 4 GB a 8 GB |
| **ollama-service** | `OLLAMA_NUM_GPU=99` (VRAM) | `OLLAMA_NUM_GPU=0` (RAM de sistema) | 8 GB a 12 GB |
| **ai-gateway** | CPU (FastAPI Asíncrono) | CPU (FastAPI Asíncrono) | 1 GB |
| **rag-service** | CPU (Extracción y Coseno) | CPU (Extracción y Coseno) | 1 GB |
| **nginx-proxy** | CPU (Nginx Alpine) | CPU (Nginx Alpine) | 512 MB |
| **portainer** | CPU (Gestión) | CPU (Gestión) | 512 MB |

---

### 2.2. Modos de Despliegue

#### Modo A: Con Aceleración GPU NVIDIA (Por Defecto)
Aplica cuando el host dispone de tarjeta NVIDIA (RTX, GTX, Tesla, Quadro) con el NVIDIA Container Toolkit instalado.
- **Configuración en `.env`:**
  ```bash
  WHISPER_DEVICE=cuda
  WHISPER_COMPUTE_TYPE=float16
  OLLAMA_NUM_GPU=99
  HARDWARE_PROFILE=gpu
  ```
- **Comando de inicio:**
  ```bash
  docker compose up -d
  ```

#### Modo B: Con Aceleración 100% CPU (Portabilidad Total)
Aplica en máquinas sin GPU, entornos cloud básicos o equipos portátiles. Utiliza el archivo `docker-compose.cpu.yml`, que elimina automáticamente las solicitudes de dispositivos NVIDIA y conmuta la inferencia de Whisper a cuantización `int8` optimizada para CPU.
- **Configuración en `.env`:**
  ```bash
  WHISPER_DEVICE=cpu
  WHISPER_COMPUTE_TYPE=int8
  OLLAMA_NUM_GPU=0
  HARDWARE_PROFILE=cpu
  ```
- **Comando de inicio universal:**
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d
  ```

---

## 3. Endpoints de Acceso y Puertos

| Servicio | URL Externa (Host) | Protocolo / Seguridad | Función |
| :--- | :--- | :--- | :--- |
| **API Inferencia IA** | `https://127.0.0.1:8443/api/v1/` | HTTPS / TLS 1.3 (Nginx) | Transcripción, Anonimización y Ollama con RAG |
| **Dashboard RAG** | `https://127.0.0.1:8443/rag/` | HTTPS / TLS 1.3 (Nginx) | Subida web de PDF/DOCX/TXT y búsqueda semántica |
| **Portainer CE** | `https://127.0.0.1:9443/` | HTTPS Seguro (Certificado SSL) | Monitoreo y administración visual de contenedores |
| **Whisper / Ollama / Gateway / RAG** | *Sin puertos en el host* | Red interna `voice-ai-net` | Aislamiento perimetral estricto (Zero Exposed Ports) |

---

## 4. Verificación de Integridad y Pruebas Empíricas

1. **Estado de Contenedores:**
   ```bash
   docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
   ```
2. **Prueba Integral Automatizada:**
   ```bash
   python test_rag.py
   ```
3. **Prueba de Endpoints de IA:**
   ```bash
   python test_engine.py
   ```

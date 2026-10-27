# Manual de Operación, Integración de API y Arquitectura del Sistema

**Proyecto:** Voice_AI_Engine  
**Institución:** Centro Terapéutico Residencial (Institución de Salud Especializada)  
**Versión del Sistema:** 1.0.0  
**Clasificación:** Documentación Técnica de Ingeniería y Guía de Integración  

---

## 1. Visión General del Sistema

Voice_AI_Engine es una plataforma de Inteligencia Artificial local (On-Premise) diseñada para procesar registros terapéuticos en entornos de salud mental y adicciones. El sistema opera de forma desacoplada y confinada en contenedores Docker bajo estrictas normativas de privacidad y seguridad perimetral.

### 1.1. Microservicios del Subsistema

El stack se compone de seis contenedores especializados que interactúan a través de una red interna bridge aislada (`voice-ai-net`):

1. **Proxy Inverso Nginx (`voice-nginx-proxy`):** Único punto de entrada perimetral expuesto en el host (puerto 8443). Gestiona cifrado TLS 1.3, mitigación de ataques con rate-limiting y control de acceso mediante lista blanca de direcciones IP y subredes autorizadas.
2. **Motor RAG e Ingesta Documental (`voice-rag-service`):** Gestiona la carga de documentos institucionales (PDF, DOCX, TXT), su conversión automática a Markdown estructurado, la partición semántica en fragmentos y la destrucción física irreversible del archivo original. Expone una interfaz web en `/rag/` y endpoints de consulta semántica en el puerto interno 8090.
3. **API Gateway de Orquestación (`voice-ai-gateway`):** Microservicio FastAPI interno (puerto 8080) que coordina el flujo completo: recibe peticiones, ejecuta la pasarela de anonimización reversible, recupera contexto relevante desde el servicio RAG e invoca a Ollama y Whisper.
4. **Servicio de Transcripción Fonética (`voice-whisper-service`):** Motor de inferencia basado en `faster-whisper` (CTranslate2) con el modelo `large-v3-turbo`. Procesa archivos de audio montados en memoria RAM volátil (`tmpfs` en `/tmp/audio_ram`) y destruye físicamente el contenido tras la transcripción.
5. **Servicio de Lenguaje Clínico (`voice-ollama-service`):** Instancia local de Ollama configurada con usuario no-root `10001:10001` y modelo `llama3.1:8b-instruct-q4_K_M`. Homologa narrativas clínicas en tres campos estructurados (`objetivo`, `intervencion`, `acciones_a_seguir`) aplicando delimitadores de texto pasivo bajo el estándar OWASP LLM 2025.
6. **Panel de Gestión Portainer CE (`voice-portainer`):** Interfaz gráfica de administración y telemetría de contenedores accesible mediante canal cifrado SSL en el puerto 9443.

### 1.2. Marco Normativo y Cumplimiento

- **Ley N° 21.719 (Chile):** Protección de datos biométricos de voz. Los audios se procesan en memoria volátil sin persistencia en disco duro.
- **Ley N° 20.584 y Ley N° 19.628:** Protección de la ficha clínica y datos sensibles mediante anonimización contextual automática de identificadores de pacientes (RUT, nombres, teléfonos).
- **OWASP Top 10 API Security 2023:** Validación estricta de esquemas con Pydantic, restricciones de tamaño de carga, cabeceras seguras (HSTS, CSP, nosniff, frame-options DENY) y filtrado por lista blanca de IPs.
- **OWASP Top 10 for LLM Applications 2025:** Aislamiento de prompt injection mediante delimitadores de narrativa pasiva y formateo JSON forzado.
- **CIS Docker Benchmark v1.6.0:** Contenedores ejecutados con usuario sin privilegios (`10001:10001`), sistemas de archivos en modo sólo lectura (`read_only: true`), desactivación de privilegios adicionales (`no-new-privileges: true`) y revocación total de capacidades del kernel (`cap_drop: ALL`).

### 1.3. Controles Defensivos Avanzados y Guardrails IA (OWASP LLM 2025)

El motor integra una capa defensiva activa validada mediante ejercicios de Red Team ofensivo:
1. **Aislamiento Criptográfico RAG vs Narrativa (LLM01 / LLM08):** El contexto documental legítimo se encapsula de manera exclusiva bajo etiquetas `<trusted_rag_context origin="system_rag_knowledge_base">`, mientras que el relato del usuario se confina en `<patient_clinical_narrative>`.
2. **Sanitizador Perimetral de Entrada:** Se purga cualquier intento del usuario de forzar etiquetas XML reservadas para prevenir suplantación de contexto (*Context Spoofing*). Las decisiones de alta médica o anulación de tratamiento requieren evaluación presencial y están bloqueadas desde relatos textuales.
3. **Guardrail Post-Inferencia contra Código y SQL (LLM05):** Filtro regex en tiempo real sobre `objetivo`, `intervencion` y `acciones_a_seguir` que detecta y neutraliza sentencias SQL (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `DROP`, `UNION`, `EXEC`), código markdown y llamadas a shell.
4. **Resiliencia de Esquemas ante DoS (LLM10):** Validadores Pydantic que transforman valores nulos o malformados en respuestas seguras neutrales, mitigando excepciones HTTP 500.
5. **Certificación Pericial:** Consulte el [Reporte Pericial de Pentesting y Saneamiento](reporte-pericial-pentesting-y-saneacion.md) con las evidencias fotográficas de re-test.

---

## 2. Requisitos del Sistema y Portabilidad de Hardware

El motor dispone de una arquitectura dual que permite operar con aceleración por hardware dedicada o conmutar a procesamiento 100% en CPU.

### 2.1. Matriz de Requisitos Técnicos

| Componente | Perfil Acelerado por GPU | Perfil Universal por CPU |
| :--- | :--- | :--- |
| **Sistema Operativo** | Linux (Ubuntu 22.04+, Debian 12+) o Windows 11 con WSL2 | Cualquier distribución Linux x86_64, macOS o Windows |
| **Procesador** | CPU de 4 núcleos o superior | CPU de 8 núcleos con soporte AVX2 / FMA |
| **Memoria RAM** | 16 GB mínimo (24 GB recomendados) | 8 GB a 16 GB asignados al entorno Docker / WSL2 |
| **Tarjeta Gráfica** | NVIDIA con 6 GB a 8 GB VRAM o superior (RTX 3060+, RTX 4000, A100) | No requerida (o GPUs con VRAM < 6 GB como GTX 1650) |
| **Controlador** | NVIDIA Container Toolkit y driver NVIDIA v525+ | Drivers estándar del sistema operativo |
| **Almacenamiento** | 25 GB de espacio libre (modelos y capas base) | 25 GB de espacio libre |

### 2.2. Modos de Ejecución y Scripts de Puesta en Marcha

#### A. Inicio Automatizado Inteligente (Recomendado)
El repositorio incorpora iniciadores inteligentes que inspeccionan en tiempo real las especificaciones del host (RAM física, vCPUs y memoria de Docker/WSL2, tarjeta GPU y VRAM real vía `nvidia-smi`). Si la GPU dispone de menos de 6 GB de VRAM (como tarjetas de 4 GB), conmuta automáticamente a perfil CPU informando la razón para prevenir bloqueos por *CUDA Out of Memory*:

- **En Linux o macOS:**
  ```bash
  chmod +x start.sh
  ./start.sh
  ```
  *Banderas disponibles:*
  * `./start.sh --dry-run` : Diagnóstico de hardware y perfil recomendado sin levantar contenedores.
  * `./start.sh --cpu` : Fuerza el modo 100% CPU optimizado.
  * `./start.sh --force-gpu` : Fuerza GPU en hardware con VRAM inferior a 6 GB.

- **En Windows (PowerShell):**
  ```powershell
  .\start.ps1
  ```
  *Banderas disponibles:*
  * `.\start.ps1 -DryRun` : Diagnóstico e informe en consola sin desplegar contenedores.
  * `.\start.ps1 -Cpu` : Fuerza la ejecución en CPU.
  * `.\start.ps1 -ForceGpu` : Fuerza el uso de GPU en tarjetas con memoria reducida.

#### B. Despliegue Manual con Aceleración GPU (NVIDIA CUDA)
Construye las imágenes independientes desde cero y levanta todo el subsistema aprovechando la GPU NVIDIA para Whisper (`float16`) y Ollama:

```bash
docker compose up -d --build
```

#### C. Despliegue Manual en CPU Pura (macOS, Linux o Windows)
Diseñado para macOS (Apple Silicon o Intel), servidores cloud estándar sin GPU, o entornos de prueba. Utiliza el archivo complementario `docker-compose.cpu.yml`:

```bash
docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d --build
```

Este comando anula las reservas de hardware NVIDIA, conmuta Whisper a cuantización `int8` y configura a Ollama para operar sin delegación de VRAM (`OLLAMA_NUM_GPU=0`).

> [!NOTE]
> Todos los microservicios (`whisper-service`, `ai-gateway`, `rag-service` y `ollama-service`) cuentan con Dockerfiles multi-stage completamente desacoplados. Ningún microservicio depende de imágenes locales previas ni de carpetas de wheels externas, garantizando un despliegue limpio y portable en cualquier sistema operativo.

---

## 3. Guía de Puesta en Marcha

### 3.1. Configuración de Variables de Entorno (`.env`)

Cree o ajuste el archivo `.env` en la raíz del proyecto según las características de su infraestructura:

```env
# Transcripción Fonética
WHISPER_MODEL=large-v3-turbo
WHISPER_DEVICE=cuda
WHISPER_COMPUTE_TYPE=float16
WHISPER_CPU_FALLBACK=true
AUDIO_RAM_DIR=/tmp/audio_ram
MAX_AUDIO_SIZE_MB=50

# Estructuración Clínica LLM
LLM_MODEL=llama3.1:8b-instruct-q4_K_M
OLLAMA_KEEP_ALIVE=24h
OLLAMA_NUM_PARALLEL=2
OLLAMA_NUM_GPU=99

# Microservicio RAG
RAG_PORT=8090
RAG_URL=http://rag-service:8090
RAG_DATA_DIR=/app/data
EMBED_MODEL=llama3.1:8b-instruct-q4_K_M

# Parámetros de Bastionado
PUID=10001
PGID=10001
TMPFS_AUDIO_SIZE=512M
TMPFS_TMP_SIZE=1G
NVIDIA_VISIBLE_DEVICES=all
```

### 3.2. Arranque del Stack

Ejecute la inicialización de los servicios:

```bash
# Para host con GPU NVIDIA:
docker compose up -d

# Para host con CPU:
docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d
```

Verifique que los seis contenedores alcancen el estado saludable:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

---

## 4. Manual de Uso del Módulo RAG e Ingesta Documental

El microservicio RAG permite cargar documentos técnicos o protocolos clínicos para enriquecer el contexto del modelo de lenguaje sin alterar sus pesos internos.

### 4.1. Acceso a la Interfaz Web

Abra un navegador web e ingrese a la dirección segura:

```text
https://127.0.0.1:8443/rag/
```

*Nota sobre certificados:* Si utiliza certificados autofirmados de desarrollo, confirme la excepción de seguridad en su navegador.

### 4.2. Procedimiento de Carga y Destrucción Criptográfica

1. Arrastre o seleccione un archivo en formato **PDF**, **DOCX** o **TXT** dentro de la zona de carga.
2. Haga clic en el botón **Transformar e Indexar**.
3. El sistema ejecuta las siguientes acciones automáticas:
   - Almacena el archivo temporalmente en `/tmp/rag_uploads`.
   - Convierte el texto y las tablas a formato Markdown estructurado (`.md`).
   - Aplica la rutina `secure_shred_file()`: sobrescribe el archivo original con bytes `0x00`, luego con bytes pseudoaleatorios, ejecuta `fsync` a nivel de disco físico y elimina el enlace con `unlink`.
   - Divide el contenido en bloques semánticos de 600 palabras con traslape de 100 palabras.
   - Genera los vectores de indexación y los registra en el índice persistente.
4. El documento original queda destruido sin remanencia física. El archivo Markdown resultante se visualiza en la lista de documentos y queda disponible para inyección contextual.

### 4.3. Búsqueda y Validación Semántica

En la columna derecha del panel RAG puede ingresar consultas de prueba (por ejemplo: *"protocolo de manejo de crisis de craving"*). El buscador devolverá los fragmentos coincidentes ordenados por similitud de coseno junto con su puntaje de relevancia (*score*).

---

## 5. Especificación Completa de la API REST (Guía de Integración)

Todas las solicitudes externas deben dirigirse al puerto **8443** mediante HTTPS (TLS 1.2 o TLS 1.3). El proxy inverso rechaza cualquier intento de conexión en texto plano por HTTP.

### 5.1. Resumen de Endpoints Disponibles

| Método | Endpoint | Descripción | Acceso |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/process-audio` | Transcribe audio volátil, anonimiza y estructura registro clínico con RAG | HTTPS / Proxy |
| `POST` | `/api/v1/process-text` | Anonimiza relato en texto, consulta RAG y estructura registro con Ollama | HTTPS / Proxy |
| `POST` | `/rag/api/v1/upload` | Carga documento (PDF/DOCX/TXT), destruye original y crea índice Markdown | HTTPS / Proxy |
| `POST` | `/rag/api/v1/query` | Realiza búsqueda semántica en la base de documentos Markdown | HTTPS / Proxy |
| `GET` | `/rag/api/v1/documents` | Lista metadatos de documentos indexados en el motor RAG | HTTPS / Proxy |
| `GET` | `/health` | Estado de salud y conectividad de los microservicios internos | HTTPS / Proxy |
| `GET` | `/proxy-health` | Estado de disponibilidad del proxy perimetral Nginx | HTTPS / Proxy |

---

### 5.2. Procesamiento de Texto Clínico (`POST /api/v1/process-text`)

Recibe la narrativa de una sesión terapéutica en texto plano, aplica la pasarela perimetral de anonimización (sustituyendo RUTs y nombres reales por identificadores opacos), recupera los protocolos pertinentes desde el motor RAG y genera la estructuración formal mediante Ollama.

#### Parámetros del Cuerpo de la Petición (JSON):

| Campo | Tipo | Obligatorio | Descripción |
| :--- | :--- | :--- | :--- |
| `texto` | String | Sí | Narrativa clínica (longitud entre 10 y 10.000 caracteres) |
| `anonimizar` | Boolean | No | Activa la anonimización de datos sensibles (por defecto: `true`) |
| `usar_rag` | Boolean | No | Recupera e inyecta contexto institucional desde el RAG (por defecto: `true`) |
| `paciente_nombre` | String | No | Nombre del paciente para tokenización contextual exacta |
| `paciente_rut` | String | No | Identificador RUT chileno del paciente |

#### Ejemplo de Petición con cURL:

```bash
curl -k -X POST "https://127.0.0.1:8443/api/v1/process-text" \
  -H "Content-Type: application/json" \
  -d '{
    "texto": "El paciente Juan Perez presenta episodio agudo de craving y deseo de consumo tras discusion familiar. Se muestra ansioso y solicita abandonar la comunidad.",
    "anonimizar": true,
    "usar_rag": true,
    "paciente_nombre": "Juan Perez",
    "paciente_rut": "12.345.678-5"
  }'
```

#### Ejemplo de Petición en JavaScript (Fetch API / Node.js):

```javascript
const https = require('https');

const agent = new https.Agent({ rejectUnauthorized: false }); // Usar solo en desarrollo local

async function estructurarTextoClinico() {
  const payload = {
    texto: "El usuario Juan Perez relata dificultades para conciliar el sueno e irritabilidad ante limites normativos.",
    anonimizar: true,
    usar_rag: true,
    paciente_nombre: "Juan Perez",
    paciente_rut: "12.345.678-5"
  };

  const response = await fetch("https://127.0.0.1:8443/api/v1/process-text", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
    agent: agent
  });

  const data = await response.json();
  console.log("Estructura clínica generada:", data.estructura_clinica);
}

estructurarTextoClinico();
```

#### Ejemplo de Petición en Python:

```python
import requests

url = "https://127.0.0.1:8443/api/v1/process-text"
payload = {
    "texto": "El paciente Juan Perez manifiesta angustia y temores asociados a su proceso de reinsercion laboral.",
    "anonimizar": True,
    "usar_rag": True,
    "paciente_nombre": "Juan Perez",
    "paciente_rut": "12.345.678-5"
}

response = requests.post(url, json=payload, verify=False)
resultado = response.json()

print(f"Estado: {resultado['status']}")
print(f"RAG inyectado: {resultado['rag_consultado']}")
print("Objetivo:", resultado['estructura_clinica']['objetivo'])
print("Intervencion:", resultado['estructura_clinica']['intervencion'])
print("Acciones a Seguir:", resultado['estructura_clinica']['acciones_a_seguir'])
```

#### Respuesta Exitosa (HTTP 200 OK):

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
      "text": "## Intervencion en Crisis de Deseo Intenso (Craving) 1. Detener de inmediato la actividad del usuario...",
      "doc_id": "28ca89de511a"
    }
  ],
  "entidades_detectadas": 2,
  "estructura_clinica": {
    "objetivo": "Gestionar el episodio agudo de craving y deseo de consumo del paciente",
    "intervencion": "Aplicacion de la tecnica de respiracion diafragmatica (4-7-8) durante 15 minutos en compania de terapeuta par y reorientacion cognitiva hacia metas de recuperacion segun protocolo institucional",
    "acciones_a_seguir": "Compromiso de permanencia en la comunidad, monitoreo continuo de signos de ansiedad y evaluacion medica si la escala de craving supera 8/10"
  },
  "metadata_audio": {},
  "normativa_cumplida": [
    "Ley N° 21.719 (Datos Biometricos y Personales)",
    "Ley N° 20.584 (Ficha Clinica y Salud Mental)",
    "Ley N° 19.628 (Vida Privada)",
    "OWASP Top 10 for LLM Applications 2025",
    "CIS Docker Benchmark v1.6.0"
  ]
}
```

---

### 5.3. Procesamiento de Audio Terapéutico (`POST /api/v1/process-audio`)

Recibe una grabación de voz generada por el terapeuta, transcribe el contenido mediante Faster-Whisper en memoria volátil (`tmpfs`), purga físicamente el buffer de audio, anonimiza y genera la ficha clínica con apoyo de Ollama y el RAG.

#### Parámetros del Formulario (`multipart/form-data`):

| Campo | Tipo | Obligatorio | Descripción |
| :--- | :--- | :--- | :--- |
| `file` | Archivo Binario | Sí | Grabación de voz en formato `.wav`, `.webm`, `.mp3`, `.ogg` o `.m4a` (máximo 50 MB) |
| `anonimizar` | Boolean | No | Activa la anonimización perimetral (por defecto: `true`) |
| `usar_rag` | Boolean | No | Inyecta contexto RAG institucional (por defecto: `true`) |
| `paciente_nombre` | String | No | Nombre del usuario atendido para desanonimización final |
| `paciente_rut` | String | No | RUT chileno del usuario |

#### Ejemplo con cURL:

```bash
curl -k -X POST "https://127.0.0.1:8443/api/v1/process-audio" \
  -F "file=@sesion_terapeutica.webm;type=audio/webm" \
  -F "anonimizar=true" \
  -F "usar_rag=true" \
  -F "paciente_nombre=Juan Perez" \
  -F "paciente_rut=12.345.678-5"
```

#### Respuesta Exitosa (HTTP 200 OK):

Devuelve la misma estructura JSON que `/api/v1/process-text`, incorporando en `metadata_audio` la duración de la grabación, el idioma detectado y el tiempo de inferencia fonética.

---

### 5.4. Consulta de Contexto RAG (`POST /rag/api/v1/query`)

Permite a aplicaciones externas o al propio API Gateway buscar fragmentos relevantes en los documentos Markdown indexados.

#### Parámetros JSON:

| Campo | Tipo | Obligatorio | Descripción |
| :--- | :--- | :--- | :--- |
| `query` | String | Sí | Texto de búsqueda o frase clínica (mínimo 3 caracteres) |
| `top_k` | Integer | No | Cantidad de fragmentos a recuperar (entre 1 y 10, valor por defecto: 3) |

#### Ejemplo con cURL:

```bash
curl -k -X POST "https://127.0.0.1:8443/rag/api/v1/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "tecnicas de contencion de ansiedad y craving",
    "top_k": 2
  }'
```

---

## 6. Administración con Portainer CE

Portainer CE permite monitorear el consumo de recursos, inspeccionar registros de depuración y gestionar el ciclo de vida de los contenedores.

- **Dirección de Acceso:** `https://127.0.0.1:9443`
- **Configuración Inicial:** En el primer inicio, defina una contraseña para el usuario administrador `admin` (mínimo 12 caracteres).
- **Entorno Conectado:** Seleccione el entorno local (`local`) para acceder a la visualización de los contenedores, redes y volúmenes de `Voice_AI_Engine`.
- **Monitoreo de Recursos:** Verifique que `voice-whisper-service` y `voice-ollama-service` no excedan los límites de memoria RAM definidos en `docker-compose.yml`.

---

## 7. Diagnóstico y Resolución de Problemas (Troubleshooting)

### 7.1. Error: "pull access denied" o Imágenes No Encontradas en Clon Limpio
- **Síntoma:** Al ejecutar `docker compose up -d`, Docker intenta descargar imágenes locales (como `voice-whisper-service:1.0.0`) desde Docker Hub y falla con `pull access denied`.
- **Causa:** Las imágenes de los microservicios se compilan localmente y no residen en registros públicos. Ejecutar `docker compose up -d` sin construir previamente omite la compilación.
- **Solución:**
  1. Utilice siempre la bandera `--build`:
     ```bash
     docker compose up -d --build
     ```
  2. O ejecute los scripts inteligentes de inicio incluidos:
     - En Linux / macOS: `./start.sh`
     - En Windows (PowerShell): `.\start.ps1`

### 7.2. Error: "file not found in build context: wheels/" o Dependencias Faltantes
- **Síntoma:** La compilación del contenedor se interrumpe buscando carpetas de binarios locales.
- **Causa:** Versiones previas dependían de una carpeta local `wheels/` ignorada por control de versiones.
- **Solución:** Los Dockerfiles actuales de todos los microservicios son multi-stage independientes. Instalan sus librerías directamente desde PyPI sin requerir carpetas locales. Si clonó recientemente, ejecute una compilación limpia sin caché:
  ```bash
  docker compose build --no-cache
  ```

### 7.3. Error de Privilegios de Red en BuildKit ("ERROR: additional privileges requested: network.host")
- **Síntoma:** Al compilar con Docker Desktop o Buildx, la tarea se aborta con `ERROR: additional privileges requested: Running build containers that can access host network. Pass "--allow=network.host" to grant requested privileges. failed to execute bake: exit status 1`.
- **Causa:** El archivo `docker-compose.yml` contenía la directiva `network: host` en los bloques `build:`. BuildKit bloquea por seguridad el acceso a la interfaz de red del host durante la construcción, y `docker compose` no admite la bandera `--allow=network.host`.
- **Solución:**
  - Se eliminó `network: host` de las directivas `build:`.
  - La descarga de paquetes en entornos con bloqueadores DNS o proxies se garantiza mediante la configuración de doble índice presente en los Dockerfiles (`--index-url https://pypi.org/simple` y `--extra-index-url https://mirrors.aliyun.com/pypi/simple/`).

### 7.4. Error: "/usr/bin/env: 'bash\r': No such file or directory" en Linux o macOS
- **Síntoma:** Al arrancar `voice-ollama-service` o ejecutar `./start.sh`, el proceso finaliza de inmediato con error de intérprete `bash\r`.
- **Causa:** Los archivos fueron clonados o editados en Windows con saltos de línea CRLF (`\r\n`) en vez de LF (`\n`).
- **Solución:**
  - El repositorio incorpora el archivo `.gitattributes` para forzar automáticamente terminaciones LF en scripts `.sh` y Dockerfiles.
  - Si editó manualmente un script en Windows, conviértalo a formato Unix con `dos2unix` o mediante Python:
    ```bash
    python -c "for p in ['start.sh', 'ollama-service/entrypoint.sh']: data = open(p,'rb').read().replace(b'\r\n', b'\n'); open(p,'wb').write(data)"
    ```

### 7.5. Falla de Detección de GPU NVIDIA al Iniciar o Error de Driver
- **Síntoma:** Docker Compose arroja el error `could not select device driver "" with capabilities: [[gpu]]`.
- **Causa:** El host no dispone de tarjeta gráfica NVIDIA, está en macOS (donde Docker Desktop no tiene acceso a hardware NVIDIA) o falta el paquete `nvidia-container-toolkit`.
- **Solución:**
  - Utilice el iniciador automático: `./start.sh` (detecta el entorno y conmuta automáticamente a CPU) o `.\start.ps1`.
  - O fuerce manualmente el perfil CPU universal:
    ```bash
    docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d --build
    ```

### 7.6. Contenedor voice-ollama-service en Estado Unhealthy
- **Síntoma:** El gateway no inicia porque `voice-ollama-service` no pasa su comprobación de salud.
- **Causa:** En el primer arranque, el script `entrypoint.sh` descarga el modelo LLM (`llama3.1:8b-instruct-q4_K_M`, aproximadamente 4.7 GB). Si la conexión a internet es lenta, el periodo de gracia puede expirar antes de concluir la descarga.
- **Solución:**
  1. Revise los registros de descarga en tiempo real:
     ```bash
     docker logs -f voice-ollama-service
     ```
  2. Si requiere precalentar el modelo manualmente dentro del contenedor:
     ```bash
     docker exec -it voice-ollama-service ollama pull llama3.1:8b-instruct-q4_K_M
     ```

### 7.7. Error 403 Forbidden al Realizar Peticiones a Nginx
- **Síntoma:** Las llamadas a `https://127.0.0.1:8443/` devuelven código HTTP 403.
- **Causa:** La IP del cliente no coincide con la lista blanca definida en `nginx/nginx.conf`.
- **Solución:** Agregue la IP o subred de su cliente en la sección `allow` del bloque `server` en `nginx/nginx.conf` y reinicie el proxy:
  ```bash
  docker compose restart nginx-proxy
  ```

### 7.8. Advertencias de Certificados TLS Autofirmados en Navegadores y APIs
- **Síntoma:** Los navegadores o bibliotecas HTTP emiten alertas por certificado no confiable (`CERT_AUTHORITY_INVALID` o `SSL: CERTIFICATE_VERIFY_FAILED`).
- **Causa:** Los certificados provistos en `nginx/certs/` son autofirmados para uso interno y de desarrollo local (`CN=voice-ai.local`).
- **Solución:**
  - En pruebas locales con cURL: use `-k` o `--insecure`.
  - En Python: configure `verify=False` o un contexto SSL con `check_hostname = False`.
  - En producción: reemplace `nginx/certs/server.crt` y `nginx/certs/server.key` por certificados firmados por una entidad certificadora reconocida (CA) o Let's Encrypt.

### 7.9. Conflicto de Nombres de Contenedor ("The container name ... is already in use")
- **Síntoma:** Docker Compose falla indicando `Conflict. The container name "/voice-rag-service" is already in use by container...`.
- **Causa:** Ocurre cuando se ejecuta Docker Compose desde carpetas con diferentes nombres (por ejemplo `Voice_AI_Engine` y `TalitaKum_AI_Engine`), lo que provoca que Docker Compose infiera nombres de proyecto distintos para contenedores que tienen nombres fijos (`container_name: ...`).
- **Solución:** `docker-compose.yml` define de forma explícita la clave raíz `name: voice_ai_engine`, asegurando un espacio de nombres único y predecible independientemente del nombre del directorio de trabajo.

### 7.10. Verificación Integral Automatizada y Reporte Certificado
Para verificar que todos los servicios y conexiones internas operen según los estándares de diseño, ejecute los scripts de validación:
```bash
# Prueba integral del motor RAG, ingesta, shredding y consulta:
python test_rag.py

# Prueba de anonimización perimetral, pipeline clínico y mitigación OWASP:
python test_engine.py
```

Para consultar el registro completo de pruebas empíricas, diagnósticos de hardware y evidencias de ejecución, consulte el documento:
* 📄 **[Reporte Técnico de Pruebas y Validación Operativa](reporte-de-pruebas-y-validacion.md)**

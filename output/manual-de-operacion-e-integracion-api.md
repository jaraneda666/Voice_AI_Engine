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

---

## 2. Requisitos del Sistema y Portabilidad de Hardware

El motor dispone de una arquitectura dual que permite operar con aceleración por hardware dedicada o conmutar a procesamiento 100% en CPU.

### 2.1. Matriz de Requisitos Técnicos

| Componente | Perfil Acelerado por GPU | Perfil Universal por CPU |
| :--- | :--- | :--- |
| **Sistema Operativo** | Linux (Ubuntu 22.04+, Debian 12+) o Windows 11 con WSL2 | Cualquier distribución Linux x86_64, macOS o Windows |
| **Procesador** | CPU de 4 núcleos o superior | CPU de 8 núcleos con soporte AVX2 / FMA |
| **Memoria RAM** | 16 GB mínimo (24 GB recomendados) | 16 GB mínimo asignados al entorno Docker |
| **Tarjeta Gráfica** | NVIDIA con 8 GB VRAM o superior (RTX 3060+, RTX 4000, A100) | No requerida |
| **Controlador** | NVIDIA Container Toolkit y driver NVIDIA v525+ | Drivers estándar del sistema operativo |
| **Almacenamiento** | 25 GB de espacio libre (modelos y capas base) | 25 GB de espacio libre |

### 2.2. Modos de Ejecución

#### A. Despliegue con Aceleración GPU (Predeterminado)
Aprovecha la tarjeta gráfica NVIDIA para ejecutar Whisper en precisión `float16` y delegar las capas de Ollama a la memoria VRAM:

```bash
docker compose up -d
```

#### B. Despliegue en CPU Pura (Máxima Portabilidad)
Diseñado para servidores convencionales, máquinas virtuales sin passthrough o equipos portátiles. Utiliza el archivo complementario `docker-compose.cpu.yml`:

```bash
docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d
```

Este comando anula los requerimientos de drivers NVIDIA, conmuta Whisper a cuantización `int8` y configura a Ollama para operar sin delegación de VRAM (`OLLAMA_NUM_GPU=0`).

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

## 7. Diagnóstico y Resolución de Problemas

### 7.1. Error 403 Forbidden al Realizar Peticiones a Nginx
- **Causa:** La dirección IP del cliente no pertenece a la lista blanca autorizada en `nginx/nginx.conf`.
- **Solución:** Agregue la IP o subred de su cliente en la sección `allow` del bloque `server` en `nginx/nginx.conf` y reinicie el proxy con `docker compose restart nginx-proxy`.

### 7.2. Falla de Detección de GPU NVIDIA al Iniciar
- **Causa:** El host no dispone de tarjeta gráfica NVIDIA o el paquete `nvidia-container-toolkit` no está instalado.
- **Solución:** Utilice el modo de compatibilidad CPU universal:
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d
  ```

### 7.3. Certificados TLS Autofirmados
- **Causa:** Los certificados generados en `nginx/certs/server.crt` son autofirmados para uso interno y de desarrollo.
- **Solución:** Al realizar llamadas mediante bibliotecas HTTP (cURL, Python Requests, Axios), utilice la opción de omitir verificación SSL (`verify=False` en Python, `-k` en cURL), o instale el certificado en el almacén de entidades de confianza de su sistema operativo.

### 7.4. Verificación Automatizada del Sistema
Para validar de forma integral el correcto funcionamiento de todos los componentes, ejecute el script de prueba integrado:

```bash
python test_rag.py
```

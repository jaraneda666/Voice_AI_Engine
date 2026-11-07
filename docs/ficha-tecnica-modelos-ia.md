# Ficha Técnica de Modelos de Inteligencia Artificial y Transcripción Fonética
**Proyecto:** Voice_AI_Engine (TalitaKum AI Engine)  
**Autor / Responsable Técnico:** Juan Carlos Araneda M.  
**Destinatario:** Patricio Muñoz / Equipo de Infraestructura y Operaciones (BrainLOF)  
**Fecha de Emisión:** 07 de Noviembre de 2026  
**Clasificación:** Especificación Técnica de Ingeniería e Infraestructura  
**Estado:** Documento Oficial de Dimensionamiento para Incorporación en BrainLOF  

---

## 1. Propósito del Documento

En respuesta al levantamiento técnico de integración formulado por la plataforma BrainLOF (Punto 6: *IA y transcripción incluidas en el software*), este documento detalla las especificaciones de arquitectura, licencias, consumo de memoria y requerimientos de cómputo de los motores locales que operan dentro del módulo CAT:

1. **Faster-Whisper (`large-v3-turbo`):** Motor de transcripción fonética automática (STT) sobre memoria volátil.
2. **Ollama (`llama3.1:8b-instruct-q4_K_M`):** Modelo de lenguaje local (LLM) para estructuración de registros clínicos en las cuatro secciones de la ficha Kimün (`objetivo`, `descripcion`, `resultados`, `observaciones`).

Ambos motores se ejecutan estrictamente dentro del perímetro de la infraestructura institucional sin dependencias externas, servicios en la nube pública ni transferencia de datos fuera del servidor, en cumplimiento estricto con la Ley N° 21.719 de Protección de Datos Personales y Datos Biométricos de Salud.

---

## 2. Ficha Técnica de los Modelos

### 2.1. Motor de Transcripción Fonética (Whisper)

| Parámetro | Especificación Técnica |
| :--- | :--- |
| **Nombre del Componente** | Faster-Whisper (Implementación basada en CTranslate2) |
| **Modelo Base** | OpenAI Whisper `large-v3-turbo` |
| **Licencia de Software** | MIT License (Código abierto, permisiva para uso comercial e institucional) |
| **Tamaño de Pesos en Disco** | ~1.6 GB (Pesos binarios convertidos a formato CTranslate2) |
| **Arquitectura de Red Neuronal** | Transformer Encoder-Decoder acústico optimizado |
| **Tasa de Muestreo de Audio** | 16.000 Hz, canal mono (PCM float32) |
| **Modo de Cuantización Soportado** | `float16` (para GPU NVIDIA) / `int8` (para CPU x86_64 con AVX2) |
| **Gestión de Memoria y Privacidad** | Montaje temporal `tmpfs` en RAM (`/tmp/audio_ram`, máx. 512 MB). El archivo de audio se destruye inmediatamente tras generar la transcripción mediante `os.unlink`. |
| **Latencia Típica (Audio de 3 min)** | - **GPU (CUDA float16):** 1.8 a 3.2 segundos.<br>- **CPU (AVX2 int8, 4 cores):** 12 a 22 segundos. |

### 2.2. Motor de Lenguaje y Estructuración Clínica (LLM)

| Parámetro | Especificación Técnica |
| :--- | :--- |
| **Nombre del Componente** | Ollama Engine (Servidor de inferencia confinado en contenedor) |
| **Modelo Base** | Meta Llama 3.1 8B Instruct |
| **Etiqueta y Cuantización** | `llama3.1:8b-instruct-q4_K_M` (Cuantización simétrica en 4 bits) |
| **Licencia de Software** | Meta Llama 3.1 Community License (Permisiva para uso empresarial y asistencial) |
| **Tamaño de Pesos en Disco** | 4.92 GB |
| **Context Window Configurada** | 8.192 tokens |
| **Formato de Salida Forzado** | Esquema JSON estructurado estricto conforme al estándar Kimün: `objetivo`, `descripcion`, `resultados`, `observaciones` |
| **Controles de Ciberseguridad** | Aislamiento XML de contexto RAG, guardrails post-inferencia contra sentencias SQL o scripts ejecutables (OWASP LLM 2025). |
| **Velocidad de Inferencia** | - **GPU (RTX 3070/4070, CUDA):** 55 - 75 tokens/segundo (~3 a 5 segundos por ficha).<br>- **CPU (4 vCPUs modernos):** 10 - 16 tokens/segundo (~12 a 18 segundos por ficha). |

---

## 3. Matriz de Requerimientos de Hardware y Dimensionamiento

De acuerdo con las directrices de dimensionamiento de BrainLOF, se presentan los escenarios de infraestructura requeridos según el volumen de profesionales atendiendo en forma simultánea:

### Escenario A: Despliegue con Aceleración GPU (Recomendado para Máxima Fluidez)

| Concurrencia Simultánea | GPU Recomendada | VRAM Dedicada | Memoria RAM Sistema | vCPUs | Almacenamiento NVMe |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **1 a 5 profesionales** | 1x NVIDIA RTX 3060 / 4060 Ti | 8 GB - 12 GB | 16 GB | 4 núcleos | 50 GB |
| **6 a 15 profesionales** | 1x NVIDIA RTX 4080 / A4000 / A5000 | 16 GB | 32 GB | 8 núcleos | 80 GB |
| **16 a 30 profesionales** | 1x NVIDIA RTX 4090 / A5500 / L40S | 24 GB | 64 GB | 16 núcleos | 120 GB |

> **Nota de Arquitectura:** En entornos con GPU, tanto Whisper (`float16`) como Ollama (`q4_K_M`) se cargan en la memoria VRAM compartida. Un profesional promedio dicta entre 1 y 2 minutos; el tiempo de procesamiento en GPU toma menos de 4 segundos, por lo que una única GPU de 12 GB atiende de forma interactiva y sin colas a un equipo de 10 a 15 terapeutas en jornada activa.

### Escenario B: Despliegue 100% CPU (Entornos Cloud, VPS o Servidores sin GPU)

| Concurrencia Simultánea | Perfil de Modelos | Memoria RAM Sistema | vCPUs Mínimos | Almacenamiento |
| :---: | :--- | :---: | :---: | :---: |
| **1 a 3 profesionales** | Whisper `small` (int8) + Llama `3.2:3b` | 8 GB RAM | 4 vCPUs | 30 GB |
| **4 a 8 profesionales** | Whisper `large-v3-turbo` (int8) + Llama `3.1:8b` (q4_K_M) | 16 GB RAM | 8 vCPUs | 50 GB |
| **9 a 20 profesionales** | Whisper `large-v3-turbo` (int8) + Llama `3.1:8b` (q4_K_M) | 32 GB RAM | 16 vCPUs | 80 GB |

---

## 4. Conectividad y Políticas de Red para BrainLOF

1. **Protocolo y Puertos:** Toda la interacción del módulo se realiza a través de Nginx en el puerto seguro HTTPS **443** (o **8443** en desarrollo local).
2. **Dominios Autorizados:** Únicamente los dominios institucionales de BrainLOF (`brainlof.com` en producción y `lofbrain.com` en laboratorio).
3. **Cero Salida a Internet:** Los microservicios de IA (`voice-ai-gateway`, `voice-whisper-service`, `voice-ollama-service`, `voice-rag-service`) no requieren salida a la red pública durante su operación productiva; todas las dependencias y pesos binarios quedan pre-empaquetados en las imágenes Docker.
4. **Punto Único de Invocación:** El backend de CAT interactúa con el motor a través de la función aislada `procesar_atencion()`, permitiendo a BrainLOF registrar métricas de uso y aplicar las políticas de consumo establecidas para la institución.

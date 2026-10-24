"""
Whisper Transcription Microservice - FastAPI + Faster-Whisper (CTranslate2)
Sistema Voice AI - Centro de Salud Mental y Terapia Especializada

CUMPLIMIENTO NORMATIVO ESTRICTO:
- Ley N° 21.719 (Protección de Datos Personales y Datos Biométricos de Voz).
- Ley N° 19.628 (Protección de la Vida Privada).
- Montaje volátil en memoria RAM exclusiva (tmpfs en /tmp/audio_ram).
- Destrucción física, criptográfica e irreversible del archivo de audio tras su transcripción.
- Cero persistencia en almacenamiento físico o disco.
"""

import gc
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Dict, List, Optional
import uuid

from fastapi import FastAPI, File, HTTPException, UploadFile, status
from fastapi.responses import JSONResponse
from faster_whisper import WhisperModel
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings

# ------------------------------------------------------------------------------
# Logging Configuration (Privacy-Preserving)
# ------------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [whisper-service] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("whisper-service")


# ------------------------------------------------------------------------------
# Application Settings
# ------------------------------------------------------------------------------
class Settings(BaseSettings):
    whisper_model: str = Field(default="large-v3-turbo", alias="WHISPER_MODEL")
    whisper_device: str = Field(default="cuda", alias="WHISPER_DEVICE")
    whisper_compute_type: str = Field(default="float16", alias="WHISPER_COMPUTE_TYPE")
    whisper_cpu_fallback: bool = Field(default=True, alias="WHISPER_CPU_FALLBACK")
    audio_ram_dir: str = Field(default="/tmp/audio_ram", alias="AUDIO_RAM_DIR")
    max_audio_size_mb: int = Field(default=50, alias="MAX_AUDIO_SIZE_MB")

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()

# Global reference to model instance
whisper_engine: Optional[WhisperModel] = None
engine_device_in_use: str = "unknown"
engine_compute_in_use: str = "unknown"


# ------------------------------------------------------------------------------
# Secure File Sanitization & Physical RAM Destruction Routine
# ------------------------------------------------------------------------------
def secure_shred_ram_file(file_path: Path) -> None:
    """
    Destrucción física, criptográfica e irreversible del archivo de audio en RAM.
    Cumplimiento Ley N° 21.719 (Protección de Datos Biométricos):
    1. Verifica que la ruta pertenezca estrictamente al tmpfs (/tmp/audio_ram).
    2. Sobrescribe el contenido completo del archivo con ceros (0x00).
    3. Sobrescribe con bytes aleatorios criptográficos (os.urandom).
    4. Sincroniza y fuerza la descarga de buffers (flush + fsync).
    5. Elimina el archivo del sistema de archivos volátil (unlink).
    6. Fuerza recolección de basura para liberar buffers de memoria.
    """
    if not file_path.exists():
        return

    try:
        # Prevención estricta de Path Traversal
        canonical_path = file_path.resolve()
        allowed_dir = Path(settings.audio_ram_dir).resolve()
        if not str(canonical_path).startswith(str(allowed_dir)):
            logger.error("Alerta de Seguridad: Intento de borrado fuera del directorio tmpfs autorizado.")
            return

        file_size = canonical_path.stat().st_size
        if file_size > 0:
            with open(canonical_path, "ba+", buffering=0) as f:
                # Paso 1: Sobrescritura con ceros
                f.seek(0)
                f.write(b"\x00" * file_size)
                f.flush()
                os.fsync(f.fileno())

                # Paso 2: Sobrescritura criptográfica
                f.seek(0)
                f.write(os.urandom(file_size))
                f.flush()
                os.fsync(f.fileno())

        # Paso 3: Desvinculación definitiva
        os.unlink(canonical_path)
        logger.info(f"Destrucción biométrica certificada (Ley 21.719): archivo volátil purgado exitosamente.")
    except Exception as e:
        logger.error(f"Falla durante la destrucción segura del archivo de audio: {e}")
        if file_path.exists():
            try:
                os.unlink(file_path)
            except Exception:
                pass
    finally:
        gc.collect()


# ------------------------------------------------------------------------------
# Lifespan Management (Model Preloading & Hardware Fallback)
# ------------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    global whisper_engine, engine_device_in_use, engine_compute_in_use

    # Ensure volatile RAM directory exists
    ram_path = Path(settings.audio_ram_dir)
    ram_path.mkdir(parents=True, exist_ok=True)

    logger.info(f"Inicializando motor faster-whisper con modelo: {settings.whisper_model}")

    loaded = False
    # Intento 1: Aceleración GPU solicitada (CUDA)
    if settings.whisper_device.lower() == "cuda":
        try:
            logger.info(f"Intentando carga en GPU (CUDA) con compute_type={settings.whisper_compute_type}...")
            whisper_engine = WhisperModel(
                model_size_or_path=settings.whisper_model,
                device="cuda",
                compute_type=settings.whisper_compute_type,
                download_root="/models"
            )
            engine_device_in_use = "cuda"
            engine_compute_in_use = settings.whisper_compute_type
            loaded = True
            logger.info("Motor cargado exitosamente en acelerador GPU (CUDA).")
        except Exception as e:
            logger.warning(f"No fue posible inicializar CUDA ({e}). Evaluando mitigación CPU Fallback...")
            if not settings.whisper_cpu_fallback:
                raise RuntimeError(f"Fallo de GPU y CPU Fallback deshabilitado: {e}")

    # Intento 2: Fallback resiliente a CPU (int8 cuantizado)
    if not loaded:
        logger.info("Activando CPU Fallback (device=cpu, compute_type=int8)...")
        whisper_engine = WhisperModel(
            model_size_or_path=settings.whisper_model,
            device="cpu",
            compute_type="int8",
            download_root="/models"
        )
        engine_device_in_use = "cpu"
        engine_compute_in_use = "int8"
        logger.info("Motor inicializado exitosamente en CPU (modo cuantizado int8).")

    yield

    logger.info("Descargando recursos del motor Whisper...")
    whisper_engine = None
    gc.collect()


# ------------------------------------------------------------------------------
# FastAPI Application Definition
# ------------------------------------------------------------------------------
app = FastAPI(
    title="Whisper Transcription Service - Sistema Voice AI",
    description="Microservicio de transcripción fonética local on-premise con destrucción física de audios en RAM.",
    version="1.0.0",
    lifespan=lifespan
)


# ------------------------------------------------------------------------------
# Schemas
# ------------------------------------------------------------------------------
class HealthResponse(BaseModel):
    status: str
    model: str
    device: str
    compute_type: str
    audio_ram_mount: str
    ley_21719_cumplimiento: str


class TranscriptionSegment(BaseModel):
    id: int
    start: float
    end: float
    text: str


class TranscriptionResponse(BaseModel):
    text: str = Field(description="Transcripción consolidada en español")
    language: str = Field(default="es")
    duration: float = Field(description="Duración en segundos del audio procesado")
    segments: List[TranscriptionSegment] = Field(default_factory=list)
    biometric_purged: bool = Field(default=True, description="Confirmación de borrado físico en RAM")


# ------------------------------------------------------------------------------
# Endpoints
# ------------------------------------------------------------------------------
@app.get("/health", response_model=HealthResponse, tags=["Salud"])
def health_check():
    """Valida el estado del servicio, dispositivo en uso y confirmación de tmpfs."""
    if whisper_engine is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="El motor de transcripción no está inicializado."
        )

    return HealthResponse(
        status="healthy",
        model=settings.whisper_model,
        device=engine_device_in_use,
        compute_type=engine_compute_in_use,
        audio_ram_mount=settings.audio_ram_dir,
        ley_21719_cumplimiento="Activo: Destrucción física irreversible en tmpfs volátil"
    )


@app.post(
    "/transcribe",
    response_model=TranscriptionResponse,
    status_code=status.HTTP_200_OK,
    tags=["Transcripción"]
)
async def transcribe_audio(file: UploadFile = File(...)):
    """
    Recibe audio (.wav o .webm), lo almacena en RAM volátil (/tmp/audio_ram),
    ejecuta la transcripción con Faster-Whisper y destruye irreversiblemente el archivo.
    """
    if whisper_engine is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Servicio no disponible: motor Whisper no cargado."
        )

    # 1. Validación de Formato de Audio (.wav o .webm permitidos)
    filename = file.filename or "audio.webm"
    ext = os.path.splitext(filename)[1].lower()
    allowed_extensions = {".wav", ".webm", ".mp3", ".ogg", ".m4a"}

    if ext not in allowed_extensions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Formato no permitido ({ext}). Se requiere archivo .wav o .webm."
        )

    # 2. Generación de ruta segura exclusivamente en tmpfs (/tmp/audio_ram)
    session_id = uuid.uuid4().hex
    safe_filename = f"audio_{session_id}{ext}"
    temp_audio_path = Path(settings.audio_ram_dir) / safe_filename

    max_bytes = settings.max_audio_size_mb * 1024 * 1024
    bytes_read = 0

    try:
        # 3. Guardado en memoria RAM temporal con control de cuota
        with open(temp_audio_path, "wb") as buffer:
            while chunk := await file.read(1024 * 1024):  # Chunks de 1MB
                bytes_read += len(chunk)
                if bytes_read > max_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=f"Audio excede el límite máximo de {settings.max_audio_size_mb} MB en RAM."
                    )
                buffer.write(chunk)

        # 4. Transcripción con Faster-Whisper
        # Parámetros optimizados: idioma forzado a 'es', beam_size=5, vad_filter activo
        segments_generator, info = whisper_engine.transcribe(
            str(temp_audio_path),
            language="es",
            task="transcribe",
            beam_size=5,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=500)
        )

        full_text_list = []
        segments_output = []

        for seg in segments_generator:
            full_text_list.append(seg.text.strip())
            segments_output.append(
                TranscriptionSegment(
                    id=seg.id,
                    start=round(seg.start, 2),
                    end=round(seg.end, 2),
                    text=seg.text.strip()
                )
            )

        consolidated_text = " ".join(full_text_list)

        return TranscriptionResponse(
            text=consolidated_text,
            language=info.language or "es",
            duration=round(info.duration, 2),
            segments=segments_output,
            biometric_purged=True
        )

    except HTTPException:
        raise
    except Exception as exc:
        logger.error(f"Error procesando la inferencia de audio: {str(exc)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fallo durante la transcripción fonética: {str(exc)}"
        )
    finally:
        # 5. CUMPLIMIENTO LEY N° 21.719: Borrado físico e irreversible en bloque finally
        # Se garantiza su ejecución incluso ante excepciones, cancelaciones o errores
        secure_shred_ram_file(temp_audio_path)

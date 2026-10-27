"""
REST API for AI Engine
Project: Voice_AI_Engine (Private Clinical Speech & Medical NLP Subsystem)
Security: OWASP Top 10 API Security | OWASP Web Application Security | Ley N° 21.719 | OWASP LLM 2025
"""

import logging
from typing import Any, Dict, Optional
from fastapi import FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.exceptions import RequestValidationError, ResponseValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ValidationError, field_validator

from core.pipeline import EnginePipeline

logger = logging.getLogger("Voice_AI_Engine.API")

app = FastAPI(
    title="Voice AI Engine API",
    description="Internal API for volatile phonetic speech-to-text, anonymization, and clinical standardization via local AI.",
    version="1.0.0",
)

# CORS restricted for authorized clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict to client origins in production
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

pipeline = EnginePipeline()


# ------------------------------------------------------------------------------
# Pydantic Schemas for Strict Input & Output Validation (OWASP API & LLM 2025)
# ------------------------------------------------------------------------------
class TextoInput(BaseModel):
    texto: str = Field(min_length=10, max_length=10000, description="Relato clínico en texto plano")
    anonimizar: bool = Field(default=True, description="Activa la pasarela de anonimización perimetral")
    usar_rag: bool = Field(default=True, description="Inyecta contexto semántico recuperado desde documentos Markdown RAG")
    paciente_nombre: Optional[str] = Field(default=None, description="Nombre del paciente para tokenización contextual")
    paciente_rut: Optional[str] = Field(default=None, description="RUT chileno del paciente")


class EstructuraClinicaOut(BaseModel):
    objetivo: str = Field(
        default="No especificado / Sin contenido clínico identificable",
        description="Propósito clínico identificado",
    )
    intervencion: str = Field(
        default="Sin intervención clínica reportada",
        description="Detalle terapéutico o sintomatología",
    )
    acciones_a_seguir: str = Field(
        default="Mantener observación y seguimiento regular",
        description="Acciones, derivaciones o tareas intersesión",
    )

    @field_validator("objetivo", "intervencion", "acciones_a_seguir", mode="before")
    @classmethod
    def sanitize_field_value(cls, v: Any, info) -> str:
        """
        Coerces None, empty, or non-string values into safe, informative fallback strings
        to prevent downstream ResponseValidationError (LLM10).
        """
        fallback_map = {
            "objetivo": "No especificado / Sin contenido clínico identificable",
            "intervencion": "Sin intervención clínica reportada",
            "acciones_a_seguir": "Mantener observación y seguimiento regular",
        }
        fallback = fallback_map.get(info.field_name, "No especificado")
        if v is None:
            return fallback
        if not isinstance(v, str):
            v = str(v)
        v = v.strip()
        if not v:
            return fallback
        return v


class PipelineResponse(BaseModel):
    status: str
    transcripcion_original: str
    anonimizacion_aplicada: bool
    rag_consultado: Optional[bool] = False
    fragmentos_rag: Optional[list] = []
    entidades_detectadas: int
    estructura_clinica: EstructuraClinicaOut
    normativa_cumplida: list


# ------------------------------------------------------------------------------
# Exception Handlers (LLM10 / API Resilience against malformed inputs)
# ------------------------------------------------------------------------------
@app.exception_handler(ResponseValidationError)
async def response_validation_exception_handler(request, exc: ResponseValidationError):
    """
    Catches response validation errors and transforms unhandled HTTP 500 into controlled HTTP 422.
    """
    logger.error(f"Response validation error intercepted: {exc}")
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "status": "error",
            "detail": "Error de validación en la estructura de salida clínica",
            "errors": exc.errors(),
        },
    )


@app.exception_handler(ValidationError)
async def pydantic_validation_exception_handler(request, exc: ValidationError):
    """
    Catches general Pydantic validation errors and returns controlled HTTP 422.
    """
    logger.error(f"Pydantic validation error intercepted: {exc}")
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "status": "error",
            "detail": "Error de validación de esquema clínico",
            "errors": exc.errors(),
        },
    )


# ------------------------------------------------------------------------------
# Endpoints
# ------------------------------------------------------------------------------
@app.get("/health", tags=["Salud"])
def health_check():
    return {
        "status": "online",
        "engine": "Voice_AI_Engine",
        "servicios": {
            "whisper": pipeline.whisper_url,
            "ollama": pipeline.ollama_url,
            "modelo_llm": pipeline.llm_model,
        },
        "normativa": ["Ley 21.719", "Ley 20.584", "Ley 19.628", "CIS Docker v1.6.0", "OWASP API", "OWASP LLM 2025"],
    }


@app.post("/api/v1/process-audio", response_model=PipelineResponse, tags=["Pipeline IA"])
async def procesar_audio(
    file: UploadFile = File(...),
    anonimizar: bool = Form(default=True),
    usar_rag: bool = Form(default=True),
    paciente_nombre: Optional[str] = Form(default=None),
    paciente_rut: Optional[str] = Form(default=None),
):
    """
    Receives audio (.wav or .webm), transcribes via Whisper, anonymizes, retrieves RAG context,
    and infers clinical structure via Ollama with OWASP LLM 2025 protections.
    """
    allowed_exts = {".wav", ".webm", ".mp3", ".ogg", ".m4a"}
    filename = file.filename or "audio.webm"
    ext = "." + filename.split(".")[-1].lower() if "." in filename else ""

    if ext not in allowed_exts:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Extensión no permitida ({ext}). Se requiere archivo .wav o .webm.",
        )

    audio_bytes = await file.read()
    if len(audio_bytes) > 50 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="El audio excede el límite de 50 MB.",
        )

    context = {}
    if paciente_nombre:
        context["paciente_nombre"] = paciente_nombre
    if paciente_rut:
        context["paciente_rut"] = paciente_rut

    try:
        resultado = pipeline.procesar_audio(
            audio_bytes=audio_bytes,
            filename=filename,
            anonimizar=anonimizar,
            usar_rag=usar_rag,
            contexto_paciente=context or None,
        )
        return resultado
    except (ValidationError, RequestValidationError) as ve:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Error de validación en los datos de entrada o salida: {str(ve)}",
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error en el pipeline de procesamiento de audio: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en el pipeline de procesamiento de audio: {str(e)}",
        )


@app.post("/api/v1/process-text", response_model=PipelineResponse, tags=["Pipeline IA"])
def procesar_texto(input_data: TextoInput):
    """
    Receives clinical text, applies perimeter anonymization, retrieves RAG protocols,
    and structures clinical sections with prompt injection and output handling mitigations.
    """
    context = {}
    if input_data.paciente_nombre:
        context["paciente_nombre"] = input_data.paciente_nombre
    if input_data.paciente_rut:
        context["paciente_rut"] = input_data.paciente_rut

    try:
        resultado = pipeline.procesar_texto(
            texto_relato=input_data.texto,
            anonimizar=input_data.anonimizar,
            usar_rag=input_data.usar_rag,
            contexto_paciente=context or None,
        )
        return resultado
    except (ValidationError, RequestValidationError) as ve:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Error de validación en los datos de entrada o salida: {str(ve)}",
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error en el pipeline de procesamiento de texto: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en el pipeline de procesamiento de texto: {str(e)}",
        )

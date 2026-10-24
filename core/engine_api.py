"""
API REST del Motor de Inteligencia Artificial
Proyecto: Voice_AI_Engine - Centro de Salud Mental y Terapia Especializada
Seguridad: OWASP Top 10 API Security | OWASP Web Application Security | Ley N° 21.719
"""

from typing import Dict, Optional
from fastapi import FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from core.pipeline import EnginePipeline

app = FastAPI(
    title="Voice AI Engine API",
    description="API interna para transcripción fonética volátil, anonimización y estructuración clínica mediante IA local.",
    version="1.0.0"
)

# CORS restringido para clientes autorizados
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # En producción acotar a la IP o dominio de la PWA
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

pipeline = EnginePipeline()


# ------------------------------------------------------------------------------
# Esquemas Pydantic para Validación Estricta (OWASP API Security)
# ------------------------------------------------------------------------------
class TextoInput(BaseModel):
    texto: str = Field(min_length=10, max_length=10000, description="Relato clínico en texto plano")
    anonimizar: bool = Field(default=True, description="Activa la pasarela de anonimización perimetral")
    usar_rag: bool = Field(default=True, description="Inyecta contexto semántico recuperado desde documentos Markdown RAG")
    paciente_nombre: Optional[str] = Field(default=None, description="Nombre del paciente para tokenización contextual")
    paciente_rut: Optional[str] = Field(default=None, description="RUT chileno del paciente")


class EstructuraClinicaOut(BaseModel):
    objetivo: str
    intervencion: str
    acciones_a_seguir: str


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
            "modelo_llm": pipeline.llm_model
        },
        "normativa": ["Ley 21.719", "Ley 20.584", "Ley 19.628", "CIS Docker v1.6.0", "OWASP API"]
    }


@app.post("/api/v1/process-audio", response_model=PipelineResponse, tags=["Pipeline IA"])
async def procesar_audio(
    file: UploadFile = File(...),
    anonimizar: bool = Form(default=True),
    usar_rag: bool = Form(default=True),
    paciente_nombre: Optional[str] = Form(default=None),
    paciente_rut: Optional[str] = Form(default=None)
):
    """
    Recibe audio (.wav o .webm), ejecuta la transcripción con destrucción en RAM,
    anonimiza opcionalmente, recupera contexto RAG y estructura el registro clínico con Ollama.
    """
    allowed_exts = {".wav", ".webm", ".mp3", ".ogg", ".m4a"}
    filename = file.filename or "audio.webm"
    ext = "." + filename.split(".")[-1].lower() if "." in filename else ""

    if ext not in allowed_exts:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Extensión no permitida ({ext}). Se requiere archivo .wav o .webm."
        )

    audio_bytes = await file.read()
    if len(audio_bytes) > 50 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="El audio excede el límite de 50 MB."
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
            contexto_paciente=context or None
        )
        return resultado
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en el pipeline de procesamiento de audio: {str(e)}"
        )


@app.post("/api/v1/process-text", response_model=PipelineResponse, tags=["Pipeline IA"])
def procesar_texto(input_data: TextoInput):
    """
    Recibe un texto clínico, aplica anonimización perimetral opcional,
    recupera contexto RAG institucional y estructura los 3 campos mediante Ollama con mitigación OWASP LLM 2025.
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
            contexto_paciente=context or None
        )
        return resultado
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en el pipeline de procesamiento de texto: {str(e)}"
        )

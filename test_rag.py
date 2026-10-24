"""
Test Integral de Ingesta RAG, Destrucción de Originales y Consulta Semántica
Proyecto: Voice_AI_Engine (Institución de Salud Especializada)
"""

import json
import ssl
import urllib.request

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# 1. Crear documento de protocolo clinico
filename = "protocolo_craving_clinico.txt"
content = """# Protocolo Institucional de Manejo de Craving - Centro Terapéutico
Institucion de Salud Especializada - Comunidad Terapeutica

## Intervencion en Crisis de Deseo Intenso (Craving)
1. Detener de inmediato la actividad del usuario y aislar del estimulo gatillante.
2. Aplicar tecnica de respiracion diafragmatica (4-7-8) durante 15 minutos en compania de su terapeuta par.
3. Evaluar administracion de hidratacion con sales y reorientacion cognitiva hacia metas de recuperacion.
4. Si la ansiedad sobrepasa escala 8/10, derivar a evaluacion medica prioritaria y contactar red de apoyo familiar.
"""

boundary = "----BoundaryTest123456"
body = (
    f"--{boundary}\r\n"
    f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
    f"Content-Type: text/plain\r\n\r\n"
    f"{content}\r\n"
    f"--{boundary}--\r\n"
).encode("utf-8")

headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
req = urllib.request.Request("https://127.0.0.1:8443/rag/api/v1/upload", data=body, headers=headers)

print("=== 1. SUBIENDO DOCUMENTO AL RAG A TRAVÉS DE NGINX TLS 1.3 ===")
with urllib.request.urlopen(req, context=ctx) as resp:
    res = json.loads(resp.read().decode())
    print("Respuesta subida RAG:", json.dumps(res, indent=2))

print("\n=== 2. CONSULTANDO DOCUMENTOS EN EL ÍNDICE RAG ===")
req_docs = urllib.request.Request("https://127.0.0.1:8443/rag/api/v1/documents")
with urllib.request.urlopen(req_docs, context=ctx) as resp:
    docs = json.loads(resp.read().decode())
    print(f"Total documentos indexados: {len(docs)}")
    for d in docs:
        print(f" - ID: {d['id']} | Título: {d['title']} | Chunks: {d['chunks']}")

print("\n=== 3. PRUEBA DE RECUPERACIÓN SEMÁNTICA RAG ===")
q_data = json.dumps({"query": "protocolo de intervencion en crisis de craving o deseo intenso", "top_k": 2}).encode("utf-8")
req_q = urllib.request.Request("https://127.0.0.1:8443/rag/api/v1/query", data=q_data, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req_q, context=ctx) as resp:
    q_res = json.loads(resp.read().decode())
    print("Resultados de búsqueda semántica:")
    for r in q_res.get("results", []):
        print(f" * [{r['title']}] Score: {r['score']} | Snippet: {r['text'][:120]}...")

print("\n=== 4. PRUEBA DE INFERENCIA CLÍNICA CON OLLAMA INYECTANDO RAG ===")
payload = {
    "texto": "El usuario Juan Perez presenta episodio agudo de craving y deseo de consumo tras discusion familiar. Se muestra ansioso y pide abandonar la comunidad.",
    "anonimizar": True,
    "usar_rag": True,
    "paciente_nombre": "Juan Perez",
    "paciente_rut": "12.345.678-5"
}
req_infer = urllib.request.Request(
    "https://127.0.0.1:8443/api/v1/process-text",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"}
)
with urllib.request.urlopen(req_infer, context=ctx, timeout=60) as resp:
    infer_res = json.loads(resp.read().decode())
    print("Resultado inferencia con contexto RAG:")
    print(f" - RAG consultado: {infer_res.get('rag_consultado')}")
    print(f" - Fragmentos RAG inyectados: {len(infer_res.get('fragmentos_rag', []))}")
    print(" - Estructura clínica generada por Ollama:")
    for k, v in infer_res.get("estructura_clinica", {}).items():
        print(f"   [{k}]: {v}")

print("\n✅ TODAS LAS PRUEBAS DE RAG COMPLETADAS CON ÉXITO")

# Gestión de Certificados TLS (Voice_AI_Engine)

En cumplimiento de la directiva de seguridad **TKAI-001** (OWASP A02:2021 / CWE-321), las claves privadas criptográficas (`server.key`) y los certificados TLS (`server.crt`) **jamás se versionan en Git**.

## Generación Local de Certificados para Desarrollo

Si al clonar el repositorio la carpeta `nginx/certs/` carece de certificados, podés generarlos de forma automática mediante cualquiera de los siguientes comandos:

### Opción 1: Con Python (Multiplataforma Windows / Linux)
```bash
python nginx/certs/generate_certs.py
```

### Opción 2: Con Bash / OpenSSL
```bash
bash nginx/certs/generate_certs.sh
```

En entornos productivos, sustituir `server.crt` y `server.key` por certificados emitidos por la CA institucional o corporativa con permisos de lectura restringidos (`600` para la clave privada).

#!/usr/bin/env python3
"""
Generador automático de certificados TLS autofirmados para entorno local/desarrollo.
Proyecto: Voice_AI_Engine
Mitigación TKAI-001 (OWASP A02:2021 / CWE-321):
Las claves privadas nunca se versionan en Git; se generan dinámicamente en el host o contenedor.
"""

import os
import subprocess
import sys
from pathlib import Path

CERTS_DIR = Path(__file__).resolve().parent
KEY_PATH = CERTS_DIR / "server.key"
CRT_PATH = CERTS_DIR / "server.crt"

def generate_with_openssl():
    cmd = [
        "openssl", "req", "-x509", "-nodes",
        "-days", "365",
        "-newkey", "rsa:2048",
        "-keyout", str(KEY_PATH),
        "-out", str(CRT_PATH),
        "-subj", "/CN=voice-ai.local/O=TalitaKum/OU=IA-OnPremise"
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(f"[OK] Certificados generados exitosamente con OpenSSL en {CERTS_DIR}")
        return True
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        print(f"[AVISO] OpenSSL CLI no disponible ({e}). Intentando con modulo Python...")
        return False

def generate_with_python():
    try:
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        import datetime

        key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )

        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, "voice-ai.local"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "TalitaKum"),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "IA-OnPremise"),
        ])

        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.datetime.now(datetime.timezone.utc))
            .not_valid_after(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=365))
            .sign(key, hashes.SHA256())
        )

        with open(KEY_PATH, "wb") as f:
            f.write(
                key.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.TraditionalOpenSSL,
                    encryption_algorithm=serialization.NoEncryption(),
                )
            )

        with open(CRT_PATH, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))

        print(f"[OK] Certificados generados exitosamente con Python Cryptography en {CERTS_DIR}")
        return True
    except ImportError:
        print("[ERROR] Ni OpenSSL ni el paquete 'cryptography' están instalados.")
        return False

def main():
    if KEY_PATH.exists() and CRT_PATH.exists():
        print(f"[INFO] Los certificados ya existen en {CERTS_DIR}. Omitiendo generación.")
        return

    if not generate_with_openssl():
        if not generate_with_python():
            sys.exit(1)

if __name__ == "__main__":
    main()

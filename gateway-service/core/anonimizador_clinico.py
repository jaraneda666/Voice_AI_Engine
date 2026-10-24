"""
Sistema Voice AI - Sistema Inteligente de Registros Clínicos
Módulo de Anonimización y Seudonimización Clínica Perimetral (Privacy Gateway)
Cumplimiento: Ley 19.628 y Ley 21.719 (Chile)
"""

import re
from typing import Dict, List, Optional, Tuple


class AnonimizadorClinico:
    """
    Pasarela de anonimización perimetral encargada de detectar y enmascarar
    datos personales e identificatorios (PII) antes de cualquier procesamiento
    con modelos de lenguaje (LLMs), y restaurar las entidades legítimas tras la inferencia.
    """

    PATRON_RUT = re.compile(r"\b\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\b|\b\d{7,8}-[\dkK]\b", re.IGNORECASE)
    PATRON_TELEFONO = re.compile(r"\b(\+?56\s?)?(\d{9}|\d{8})\b")
    PATRON_EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b")

    def __init__(self):
        pass

    def anonimizar(self, texto: str, context: Optional[Dict[str, str]] = None) -> Tuple[str, Dict[str, str]]:
        """
        Reemplaza entidades sensibles en el texto por tokens seudonimizados.
        Retorna el texto sanitizado y el diccionario reversible de mapeo.
        """
        if not texto:
            return "", {}

        texto_procesado = texto
        mapping: Dict[str, str] = {}
        reverse_mapping: Dict[str, str] = {}

        # 1. Si hay contexto explícito (Nombre de paciente, RUT, Terapeuta)
        if context:
            paciente_nombre = context.get("paciente_nombre")
            if paciente_nombre and len(paciente_nombre.strip()) > 3:
                token_paciente = "[PACIENTE_NOMBRE]"
                # Reemplazo de nombre completo
                texto_procesado = re.sub(re.escape(paciente_nombre), token_paciente, texto_procesado, flags=re.IGNORECASE)
                mapping[token_paciente] = paciente_nombre
                reverse_mapping[paciente_nombre.lower()] = token_paciente

                # Reemplazo de palabras individuales del nombre si son significativas
                for parte in paciente_nombre.split():
                    if len(parte) > 3 and parte.lower() not in ["maria", "juan", "jose", "luis"]:
                        token_sub = f"[PACIENTE_{parte.upper()}]"
                        if parte.lower() not in reverse_mapping:
                            texto_procesado = re.sub(r"\b" + re.escape(parte) + r"\b", token_sub, texto_procesado, flags=re.IGNORECASE)
                            mapping[token_sub] = parte

            paciente_rut = context.get("paciente_rut")
            if paciente_rut:
                token_rut = "[PACIENTE_RUT]"
                # Reemplazar con puntos y sin puntos
                rut_limpio = paciente_rut.replace(".", "").upper()
                texto_procesado = re.sub(re.escape(paciente_rut), token_rut, texto_procesado, flags=re.IGNORECASE)
                texto_procesado = re.sub(re.escape(rut_limpio), token_rut, texto_procesado, flags=re.IGNORECASE)
                mapping[token_rut] = paciente_rut

        # 2. Detección y tokenización de cualquier otro RUT en el relato
        ruts_encontrados = self.PATRON_RUT.findall(texto_procesado)
        for i, rut_match in enumerate(set(ruts_encontrados)):
            token = f"[RUT_DETECTADO_{i+1}]"
            texto_procesado = texto_procesado.replace(rut_match, token)
            mapping[token] = rut_match

        # 3. Detección y tokenización de números telefónicos
        telefonos = self.PATRON_TELEFONO.findall(texto_procesado)
        for i, tel in enumerate(set(telefonos)):
            # findall con grupos devuelve tuplas, tomamos la coincidencia completa
            tel_str = tel[0] if isinstance(tel, tuple) else tel
            if tel_str.strip():
                token = f"[TELEFONO_{i+1}]"
                texto_procesado = texto_procesado.replace(tel_str, token)
                mapping[token] = tel_str

        # 4. Detección de correos electrónicos
        emails = self.PATRON_EMAIL.findall(texto_procesado)
        for i, em in enumerate(set(emails)):
            token = f"[CORREO_{i+1}]"
            texto_procesado = texto_procesado.replace(em, token)
            mapping[token] = em

        return texto_procesado, mapping

    def desanonimizar(self, texto_anonimizado: str, mapping: Dict[str, str]) -> str:
        """
        Restaura las entidades sensibles originales a partir del diccionario de mapeo.
        Esta operación se ejecuta en la memoria interna de la aplicación antes de mostrar
        el borrador al terapeuta o persistirlo en la base de datos cifrada.
        """
        if not texto_anonimizado or not mapping:
            return texto_anonimizado

        texto_restaurado = texto_anonimizado
        for token, valor_original in mapping.items():
            texto_restaurado = texto_restaurado.replace(token, valor_original)

        return texto_restaurado

    def verificar_fuga_pii(self, texto: str) -> bool:
        """
        Verifica que el texto a enviar no contenga patrones evidentes de RUTs o correos.
        Retorna True si el texto es seguro (sin PII detectada), False si persisten datos expuestos.
        """
        if self.PATRON_RUT.search(texto) or self.PATRON_EMAIL.search(texto):
            return False
        return True

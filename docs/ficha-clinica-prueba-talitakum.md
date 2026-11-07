# Ficha Clínica de Pruebas y Validación Funcional (Datos Ficticios)

## Control de Documento
- **Responsable Técnico:** Juan Carlos Araneda M.
- **Proyecto Evaluado:** Proyecto CAT · Comunidad Terapéutica Talita Kum (Fundación Cristo Vive)
- **Subsistema:** Voice AI Engine / Módulo de Captura y Estructuración Clínica
- **Fecha de Emisión:** 07-11-2026
- **Clasificación:** Ficha de Prueba Controlada (Datos 100% Sintéticos / Anonimizados)
- **Marco Normativo:** Ley N° 21.719, Ley N° 20.584, Formato Canónico Kimün (SENDA)

---

## 1. Identificación y Metadatos de la Intervención

| Campo | Valor de Prueba Ficticio | Propósito de Validación |
| :--- | :--- | :--- |
| **Nombre Usuario** | Matías Ignacio Sepúlveda Castro | Verificación de anonimización perimetral |
| **RUT Ficticio** | 16.842.195-3 | Detección de identificador biométrico / personal |
| **Fecha de Atención** | 07 de noviembre de 2026 | Trazabilidad temporal |
| **Prestación** | Psicoterapia Individual (PI) | Clasificación de catálogo clínico Talita Kum |
| **Modalidad** | Presencial (Centro Talita Kum) | Ámbito de ejecución |
| **Duración Estándar** | 45 minutos | Validación de parámetros fijos de atención |
| **Instrumento Asociado** | Plan de Tratamiento Individual (PTI) / Evaluación Trimestral | Cruce con objetivos terapéuticos SENDA |
| **Profesional Responsable** | Ricardo Pérez (Psicólogo Clínico) | Asignación de rol y permisos RBAC |

---

## 2. Estructura Clínica en Formato Kimün

### A. Objetivo
Fortalecer estrategias de afrontamiento ante episodios de craving vespertino y reestructurar la rutina ocupacional semanal para consolidar la adherencia al Plan de Tratamiento Individual.

### B. Descripción
Se realiza sesión presencial de psicoterapia individual de 45 minutos en dependencias de la Comunidad Terapéutica Talita Kum. El usuario asiste puntual, orientado témporo-espacialmente y con adecuada presentación personal. Refiere que durante el fin de semana experimentó intensos deseos de consumo gatillados por discusiones en su grupo familiar primario; no obstante, logró aplicar la técnica de detención del pensamiento y acudió al espacio deportivo del centro en lugar de aislarse. Se revisa el registro conductual del PTI, identificando factores de riesgo en horarios nocturnos y se entrena reestructuración cognitiva frente a pensamientos permisivos de consumo.

### C. Resultados
Con Avances (C.A.). El usuario mantiene abstinencia sostenida durante los últimos dos meses, demuestra reconocimiento activo de estímulos condicionantes de riesgo y valida el uso de herramientas de autorregulación emocional aprendidas en talleres grupales. Manifiesta motivación favorable para sostener el compromiso terapéutico.

### D. Observaciones
Se acuerda mantener esquema de rutina diaria con registro de estados de ánimo y asistir a taller sociolaboral los días martes y jueves. Se coordina derivación a control médico con médico del centro para ajuste de higiene del sueño. Próxima sesión de control agendada para el viernes 14 de noviembre a las 10:00 horas.

---

## 3. Guion de Lectura en Voz Alta para Captura Fonética (Micrófono)

> **Instrucciones:** Leer el siguiente texto de corrido, a velocidad conversacional normal (duración aproximada: 20 a 25 segundos):

```text
"Sesión de psicoterapia individual con el usuario Matías Sepúlveda, RUT 16 millones 842 195 raya 3 en Centro Talita Kum. 
Objetivo: fortalecer afrontamiento de craving vespertino y reestructurar rutina ocupacional según PTI. 
Descripción: usuario refiere discusiones familiares que gatillaron deseos de consumo, pero logró aplicar detención del pensamiento y acudir a deportes evitando recaídas. Se analiza registro semanal y estímulos de riesgo. 
Resultados: usuario con avances, mantiene abstinencia de dos meses y buena adherencia al tratamiento. 
Observaciones: continuar con registro diario de ánimo, derivar a control de higiene del sueño y citar a nueva sesión el viernes 14 de noviembre."
```

---

## 4. Criterios de Aceptación Esperados en el Motor de IA

1. **Anonimización:** El RUT `16.842.195-3` y el nombre `Matías Sepúlveda` deben ser enmascarados o resguardados bajo tokens criptográficos en el log perimetral (Ley N° 21.719).
2. **Transcripción Whisper:** Fidelidad fonética sin omisión de terminología clínica (`craving`, `PTI`, `abstinencia`).
3. **Mapeo Kimün:** Respuesta en JSON estrictamente estructurada en las 4 claves:
   - `objetivo`
   - `descripcion`
   - `resultados`
   - `observaciones`
4. **Residuo Cero:** Purga física automática del archivo `.wav` en la partición volátil en RAM.


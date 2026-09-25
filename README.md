# Opus Lite

Audio, vídeo y documentos a texto. App nativa de macOS (Swift/SwiftUI), 100 % local, **~1,2 MB** sin dependencias.

## Qué hace

- **Biblioteca** en tres columnas: Todos, Recientes, Favoritos, En proceso, Papelera. Se guarda entre sesiones.
- **Importar**: arrastrar archivos o carpetas, *Importar…* (⌘O), *Abrir con → Opus Lite* desde Finder, o **grabar** con el micrófono (⇧⌘N).
- **Formatos**: notas de voz de WhatsApp (`.opus`), cualquier audio, vídeo (extrae la pista de audio), PDF (capa de texto u OCR) e imágenes (OCR).
- **Cola**: al importar se transcribe solo (configurable); progreso %, *En espera*, *Error* con reintento.
- **Transcripción** con marcas de tiempo por párrafo; clic en el tiempo para saltar al audio; el párrafo que suena se resalta.
- **Subtítulos**: vista por cues, exportables a SRT/VTT.
- **Reproductor** con forma de onda (clic/arrastre para buscar), ±15 s, velocidad y volumen.
- **Búsqueda** en nombres y texto, con coincidencias resaltadas.
- **Editar** el texto (menú ··· › Editar texto) sin perder los tiempos.
- **Exportar** (⌘E): TXT, DOCX, Markdown, SRT, VTT; varios archivos a una carpeta.
- **Opciones** (⌥⌘I): motor, idioma, marcas de tiempo, transcribir al importar.
- **Ajustes** (⌘,): apariencia (Sistema/Claro/Oscuro), modelos por idioma, privacidad, atajos.
- Switch sol/luna en la barra para modo claro/oscuro.

## Motores (todos en el Mac, modelos del sistema)

| Motor | Uso |
|---|---|
| SpeechAnalyzer | Por defecto. ~100× tiempo real. |
| Dictado | Modelo de dictado del sistema, buena puntuación. |
| SFSpeech clásico | Respaldo; más lento. |
| Vision (OCR) | PDF escaneados e imágenes. |

No hay identificación de hablantes ni detección automática de idioma: macOS no ofrece API nativa para ello.

## Compilar

```bash
./build.sh            # genera build/Opus Lite.app
```

Requiere macOS 26 y Xcode 26. El icono se regenera con `Tools/make_icon.sh`.
Datos: `~/Library/Application Support/OpusLite/` (biblioteca y grabaciones).

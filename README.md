# Vivo Subs

Subtítulos en vivo, en español, de lo que se dice en inglés. Corre en la Mac, sin mandar el audio a ningún servidor y sin síntesis de voz: solo texto.

Está pensado para seguir una reunión rápida en inglés de Estados Unidos (Zoom, Meet, Teams) o para transcribir lo que decís vos.

## Cómo funciona

Hay dos canales separados. No se mezclan.

| Canal | De dónde sale | Cómo se ve |
| --- | --- | --- |
| Audio | Lo que reproduce la Mac | Texto blanco, medidor verde |
| Mi voz | El micrófono | Texto amarillo, medidor amarillo |

Podés dejar uno, el otro, o los dos. Si no tenés auriculares, dejá **Mi voz** apagado: los parlantes se cuelan en el micrófono y la app no intenta “limpiar” ese eco, porque eso bajaba el volumen del sistema.

El camino de cada frase es este:

1. **Captura.** El audio de la Mac entra por un process tap de Core Audio (permiso *System Audio Recording Only*, no grabación de pantalla). El micrófono entra por `AVAudioEngine`, aparte.
2. **Transcripción.** Cada canal tiene su propio `SpeechTranscriber` en inglés de Estados Unidos (`en-US`), on-device, con resultados parciales.
3. **Traducción.** Cuando una frase se cierra, `TranslationSession` la pasa de inglés a español en el dispositivo. Manda también hasta dos frases anteriores **del mismo canal**, para que pronombres y respuestas cortas (*it*, *that*, *yeah*, *right*) no se traduzcan sueltas. Si no se puede recortar bien el español, se traduce solo esa frase.
4. **Ventana.** Los subtítulos flotan encima de las demás apps sin robar el foco.

## Uso

La app vive en la barra de menú.

- **Iniciar / Detener** arranca o corta la sesión.
- **Audio** transcribe lo que suena en la Mac.
- **Mi voz** transcribe el micrófono. Conviene usarlo con auriculares.
- **Inglés** muestra el original debajo del español.
- **⌘⇧H** muestra u oculta la ventana.
- **Limpiar** borra el historial.

Los dos checkboxes se pueden cambiar con la sesión andando y quedan guardados.

La primera vez macOS pide:

- **Micrófono**, solo si activás Mi voz.
- **Audio del sistema** (*Screen & System Audio Recording → System Audio Recording Only*). No hace falta grabación de pantalla.
- El **pack de traducción inglés → español**, si todavía no está instalado. La app avisa y abre Ajustes.

## Requisitos

- Mac con Apple silicon
- macOS 26 o posterior
- Xcode con el SDK de macOS 26

La transcripción y la traducción usan los modelos de Apple que ya vienen (o se descargan) en el sistema. No hay API key.

## Compilar

Abrí `VivoSubs.xcodeproj` y corré el scheme **VivoSubs**, o desde la terminal:

```bash
xcodebuild -project VivoSubs.xcodeproj -scheme VivoSubs -configuration Release CODE_SIGN_IDENTITY="-"
```

El producto queda en DerivedData como `VivoSubs.app`. La firma es ad hoc: cada rebuild puede volver a pedir permisos de micrófono y de audio del sistema.

El sandbox está desactivado a propósito. El process tap de Core Audio no funciona dentro del sandbox de la App Store.

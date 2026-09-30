# Vivo Subs

Subtítulos en vivo para cuando hablás en inglés con gente de Estados Unidos. Escucha la reunión (o tu micrófono), transcribe en inglés y muestra el español en una ventana que queda flotando encima de Zoom, Meet o Teams.

Todo pasa en la Mac. El audio no sale de la computadora y la app no habla: solo escribe.

## Qué ves

Hay dos fuentes, y cada una se puede prender o apagar sola.

- **Audio** es lo que suena en la Mac: la otra persona en la call, un video, lo que sea. Sale en blanco, con un medidor verde.
- **Mi voz** es tu micrófono. Sale en amarillo, con un medidor amarillo.

Para una reunión con parlantes, dejá **Mi voz** apagado. El micrófono también escucha los parlantes, y si los dos canales están activos vas a ver la misma frase dos veces. Con auriculares no pasa.

Si solo querés practicar o dictar, apagá **Audio** y dejá **Mi voz**.

Mientras la frase todavía se está armando, el texto de abajo es provisorio. Cuando la persona termina de hablar, esa línea queda fija y aparece la traducción.

## Cómo traduce

Traduce cada frase al cerrarse, no palabra por palabra. Para no perder el hilo (*it*, *that*, *yeah*, *right*), le pasa también las dos frases anteriores de ese mismo canal. El audio de la reunión y tu voz no se mezclan en esa traducción.

El inglés que reconoce es el de Estados Unidos.

## Cómo se usa

Vivo Subs queda en la barra de menú.

- **Iniciar** y **Detener** prenden o cortan la escucha.
- **Audio** y **Mi voz** eligen qué se transcribe. Se pueden cambiar en medio de una sesión y la app recuerda la elección.
- **Inglés** muestra el original debajo del español.
- **⌘⇧H** muestra u oculta la ventana. La ventana no le roba el foco a la reunión.
- **Limpiar** borra lo que ya se escribió.

La primera vez, macOS pide permiso. El micrófono solo si activás **Mi voz**. El audio de la Mac está en Ajustes → Privacidad → Screen & System Audio Recording, en la sección **System Audio Recording Only**. No pide grabar la pantalla. Si falta el pack de traducción inglés → español, la app lo dice y abre Ajustes.

## Requisitos

- Mac con Apple silicon
- macOS 26 o posterior

Usa los modelos de transcripción y traducción de Apple. No hace falta una API key.

## Tecnología

Es una app nativa de macOS 26, en Swift y SwiftUI. No usa Whisper, un modelo de lenguaje ni ningún servicio en la nube.

**Audio del sistema.** Core Audio crea un *process tap* global estéreo (`CATapDescription` + `AudioHardwareCreateProcessTap`) y lo enchufa a un dispositivo agregado privado, atado a la salida de audio. Eso escucha lo que la Mac está reproduciendo. El permiso de macOS es *System Audio Recording Only*. El tap queda en *unmuted*, así que la app no baja el volumen de los parlantes.

**Micrófono.** `AVAudioEngine` toma el `inputNode` y entrega PCM en un canal aparte. El procesamiento de voz del sistema (la cancelación de eco) queda apagado: al activarlo, macOS atenuaba el audio de la reunión.

**Transcripción.** Cada fuente tiene su propio `SpeechAnalyzer` con un `SpeechTranscriber` en `en-US`. Pide resultados parciales y rápidos (`.volatileResults` y `.fastResults`). El modelo de voz se reserva con `AssetInventory` mientras la sesión está abierta y se suelta al detenerla. El texto de abajo es el resultado volátil; cuando el reconocedor cierra la frase, esa línea pasa a definitiva.

**Traducción.** `TranslationSession` traduce de inglés a español en el dispositivo, a través de `.translationTask`. A la frase nueva se le anteponen hasta dos frases ya cerradas del mismo canal, numeradas, para que el modelo vea el contexto. Del resultado se queda solo con el tramo de la frase actual. Si ese recorte no sale limpio, traduce esa frase sola.

**Interfaz.** El control está en un `MenuBarExtra`. Los subtítulos van en un `NSPanel` flotante (`.nonactivatingPanel`) que puede estar en todos los espacios y en pantalla completa sin convertirse en la ventana principal. **⌘⇧H** es un atajo global registrado con Carbon.

**Sandbox.** Está desactivado. El process tap de Core Audio no funciona dentro del sandbox de la App Store. La app se firma ad hoc.

## Compilar

Abrí `VivoSubs.xcodeproj` en Xcode y corré el scheme **VivoSubs**. Desde la terminal:

```bash
xcodebuild -project VivoSubs.xcodeproj -scheme VivoSubs -configuration Release CODE_SIGN_IDENTITY="-"
```

Eso genera `VivoSubs.app`. Como la firma es ad hoc, después de recompilar macOS puede volver a pedir los permisos.

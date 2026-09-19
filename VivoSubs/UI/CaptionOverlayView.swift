import SwiftUI
import Translation

struct CaptionOverlayView: View {
    @Environment(CaptionController.self) private var controller

    var body: some View {
        @Bindable var controller = controller

        VStack(alignment: .leading, spacing: 12) {
            controlBar
            Divider().opacity(0.35)
            captionList
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 220)
        .background(.ultraThinMaterial)
        .translationTask(controller.translationConfiguration) { session in
            await controller.attachTranslationSession(session)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button(controller.isRunning ? "Detener" : "Iniciar") {
                controller.toggleRunning()
            }
            .keyboardShortcut(.space, modifiers: [.command])
            .controlSize(.large)

            AudioMeter(level: controller.audioLevel)
                .frame(width: 72, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.status.label)
                    .font(.callout)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                if let hint = controller.translationHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer()

            Toggle("Inglés", isOn: Binding(
                get: { controller.showEnglish },
                set: { controller.showEnglish = $0 }
            ))
            .toggleStyle(.checkbox)

            Button("Limpiar") {
                controller.clearHistory()
            }
            .disabled(controller.lines.isEmpty && controller.liveEnglish.isEmpty)
        }
        .font(.system(.body, design: .rounded))
    }

    private var captionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.lines) { line in
                        captionRow(spanish: line.spanish, english: line.english, translating: line.isTranslating)
                            .id(line.id)
                    }

                    if !controller.liveEnglish.isEmpty {
                        captionRow(
                            spanish: controller.liveEnglish,
                            english: controller.liveEnglish,
                            translating: true,
                            isLive: true
                        )
                        .id("live")
                    }

                    if controller.lines.isEmpty && controller.liveEnglish.isEmpty {
                        emptyState
                    }
                }
                .padding(.trailing, 4)
            }
            .onChange(of: controller.lines.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: controller.liveEnglish) {
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtítulos en español")
                .font(.title2.weight(.semibold))
            Text("Tocá Iniciar, concedé Grabación de pantalla y poné audio de una reunión. El atajo ⌘⇧H muestra u oculta esta ventana sin robar el foco.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsPermissionHelp {
                HStack {
                    Button("Abrir permiso de pantalla") {
                        controller.openScreenRecordingSettings()
                    }
                    Button("Packs de traducción") {
                        controller.openTranslationSettings()
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func captionRow(
        spanish: String,
        english: String,
        translating: Bool,
        isLive: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(spanish.isEmpty ? "…" : spanish)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(isLive ? Color.primary.opacity(0.72) : Color.primary)
                .textSelection(.enabled)

            if controller.showEnglish {
                Text(english)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if translating && !isLive {
                Text("Traduciendo…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsPermissionHelp: Bool {
        if case .error = controller.status { return true }
        return controller.status == .idle
    }

    private var statusColor: Color {
        switch controller.status {
        case .listening:
            return .green
        case .error:
            return .orange
        case .starting, .downloadingSpeech:
            return .secondary
        case .idle:
            return .secondary
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                if !controller.liveEnglish.isEmpty {
                    proxy.scrollTo("live", anchor: .bottom)
                } else if let last = controller.lines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

struct AudioMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(level > Float(index) / 5 ? Color.green.opacity(0.9) : Color.secondary.opacity(0.25))
                    .frame(width: 8)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityLabel("Nivel de audio")
    }
}

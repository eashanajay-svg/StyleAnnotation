import Combine
import PDFKit
import PencilKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

private enum AnnotationMode: String, CaseIterable {
    case highlight = "Highlight"
    case handwriting = "Handwriting"
    case note = "Note"

    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
        case .handwriting: return "pencil.tip"
        case .note: return "note.text"
        }
    }
}

private enum AnnotationColor: String, CaseIterable, Identifiable {
    case yellow
    case pink
    case blue
    case green
    case purple

    var id: String { rawValue }

    // More saturated colors remain visible beneath the translucent marker ink.
    var color: Color {
        switch self {
        case .yellow: return Color(red: 0.96, green: 0.72, blue: 0.08)
        case .pink: return Color(red: 0.86, green: 0.25, blue: 0.43)
        case .blue: return Color(red: 0.16, green: 0.43, blue: 0.78)
        case .green: return Color(red: 0.12, green: 0.55, blue: 0.32)
        case .purple: return Color(red: 0.48, green: 0.32, blue: 0.77)
        }
    }
}

private struct StickyNote: Identifiable {
    let id = UUID()
    var text = ""
    var drawing = PKDrawing()
    var handwritingEnabled = false
    var offset = CGSize.zero
    var size = CGSize(width: 210, height: 190)
}

private final class CanvasController: ObservableObject {
    weak var canvasView: PKCanvasView?

    func undo() {
        canvasView?.undoManager?.undo()
    }

    func redo() {
        canvasView?.undoManager?.redo()
    }

    func clear() {
        canvasView?.drawing = PKDrawing()
    }
}

/// A document surface with PDF/TXT import, Apple Pencil annotation, and sticky notes.
struct PencilAnnotationView<Content: View>: View {
    private let content: Content
    private let pageHeight: CGFloat

    @State private var drawing = PKDrawing()
    @State private var mode: AnnotationMode = .highlight
    @State private var selectedColor: AnnotationColor = .yellow
    @State private var stickyNotes: [StickyNote] = []
    @State private var importedDocumentText: String?
    @State private var importedDocumentName: String?
    @State private var isImporterPresented = false
    @State private var importError: String?
    @StateObject private var canvasController = CanvasController()

    init(
        pageHeight: CGFloat = 1100,
        @ViewBuilder content: () -> Content
    ) {
        self.pageHeight = pageHeight
        self.content = content()
    }

    private var canvasHeight: CGFloat {
        guard let text = importedDocumentText else { return pageHeight }
        // Reserve a little extra space so the imported text and its annotation canvas
        // share a single, scrollable document surface.
        let estimatedLines = ceil(Double(max(text.count, 1)) / 54.0)
        return max(pageHeight, CGFloat(estimatedLines * 27.0 + 220.0))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView {
                ZStack(alignment: .topLeading) {
                    displayedContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(36)

                    PencilCanvas(
                        drawing: $drawing,
                        mode: mode,
                        color: selectedColor.color,
                        controller: canvasController
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: canvasHeight)

                    ForEach($stickyNotes) { $note in
                        StickyNoteCard(note: $note) {
                            let noteID = note.id
                            stickyNotes.removeAll { $0.id == noteID }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: canvasHeight)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importDocument(at: url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Unable to import document", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "Please choose a readable PDF or TXT file.")
        }
    }

    @ViewBuilder
    private var displayedContent: some View {
        if let text = importedDocumentText {
            VStack(alignment: .leading, spacing: 18) {
                Text(importedDocumentName ?? "Imported document")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)

                Text(text)
                    .font(.system(size: 18, design: .serif))
                    .lineSpacing(8)
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } else {
            content
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            Button {
                isImporterPresented = true
            } label: {
                Label(importedDocumentName == nil ? "Open PDF/TXT" : "Replace document", systemImage: "doc.badge.plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Choose a PDF or plain text document to display and annotate")

            HStack(spacing: 4) {
                ForEach(AnnotationMode.allCases, id: \.self) { tool in
                    Button {
                        mode = tool
                    } label: {
                        Label(tool.rawValue, systemImage: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background {
                                if mode == tool {
                                    Capsule().fill(Color.accentColor.opacity(0.13))
                                }
                            }
                            .foregroundStyle(mode == tool ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == tool ? .isSelected : [])
                }
            }

            if mode == .highlight {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 24)

                HStack(spacing: 8) {
                    ForEach(AnnotationColor.allCases) { choice in
                        Button {
                            selectedColor = choice
                        } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                                }
                                .padding(3)
                                .overlay {
                                    Circle().strokeBorder(
                                        selectedColor == choice ? Color.primary.opacity(0.65) : .clear,
                                        lineWidth: 1.5
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(choice.rawValue) highlighter")
                        .accessibilityAddTraits(selectedColor == choice ? .isSelected : [])
                    }
                }
            } else if mode == .note {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stickyNotes.append(StickyNote())
                    }
                } label: {
                    Label("Add sticky note", systemImage: "note.text.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Adds a movable, resizable note with typing and handwriting options")
            } else {
                Label("Thin black pencil · write anywhere", systemImage: "pencil.tip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Handwriting mode. Write anywhere on the page with a thin black pencil.")
            }

            Spacer(minLength: 4)

            Button(action: canvasController.undo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .accessibilityLabel("Undo")

            Button(action: canvasController.redo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .accessibilityLabel("Redo")

            Button {
                canvasController.clear()
                stickyNotes.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Clear annotations and sticky notes")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func importDocument(at url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let text: String
            if url.pathExtension.lowercased() == "pdf" {
                text = try extractText(fromPDFAt: url)
            } else {
                let data = try Data(contentsOf: url)
                guard let decoded = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .utf16)
                        ?? String(data: data, encoding: .isoLatin1) else {
                    throw DocumentImportError.unsupportedTextEncoding
                }
                text = decoded
            }

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentImportError.noReadableText
            }
            importedDocumentText = text
            importedDocumentName = url.deletingPathExtension().lastPathComponent
            drawing = PKDrawing()
            stickyNotes.removeAll()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func extractText(fromPDFAt url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentImportError.invalidPDF
        }

        var pageTexts: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pageText = embeddedText.isEmpty ? try recognizeText(on: page) : embeddedText
            if !pageText.isEmpty {
                pageTexts.append(pageText)
            }
        }
        guard !pageTexts.isEmpty else { throw DocumentImportError.noReadableText }
        return pageTexts.enumerated().map { index, text in
            "Page \(index + 1)\n\n\(text)"
        }.joined(separator: "\n\n")
    }

    /// OCR makes image-only/scanned PDF pages importable as well as text PDFs.
    private func recognizeText(on page: PDFPage) throws -> String {
        let image = page.thumbnail(of: CGSize(width: 1500, height: 2000), for: .mediaBox)
        guard let cgImage = image.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

private enum DocumentImportError: LocalizedError {
    case invalidPDF
    case noReadableText
    case unsupportedTextEncoding

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "The selected PDF could not be opened."
        case .noReadableText:
            return "No readable text was found in the selected document."
        case .unsupportedTextEncoding:
            return "The text file uses an unsupported character encoding."
        }
    }
}

private struct StickyNoteCard: View {
    @Binding var note: StickyNote
    let onDelete: () -> Void
    @State private var dragStart = CGSize.zero
    @State private var resizeStart: CGSize?

    private let noteColor = Color(red: 1.0, green: 0.91, blue: 0.43)

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("NOTE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.black.opacity(0.55))

                Spacer()

                Button {
                    note.handwritingEnabled.toggle()
                } label: {
                    Image(systemName: note.handwritingEnabled ? "keyboard" : "pencil.tip.crop.circle")
                        .foregroundStyle(.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.handwritingEnabled ? "Switch to typing" : "Switch to handwriting")

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.black.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete sticky note")
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        note.offset = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragStart = note.offset
                    }
            )

            if note.handwritingEnabled {
                PencilCanvas(
                    drawing: $note.drawing,
                    mode: .handwriting,
                    color: .black,
                    controller: nil
                )
                .background(Color.white.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityLabel("Handwriting area for sticky note")
            } else {
                TextEditor(text: $note.text)
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundColor(.black)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .accessibilityLabel("Sticky note text")
            }

            HStack {
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let start = resizeStart ?? note.size
                                resizeStart = start
                                note.size = CGSize(
                                    width: max(150, start.width + value.translation.width),
                                    height: max(120, start.height + value.translation.height)
                                )
                            }
                            .onEnded { _ in
                                resizeStart = nil
                            }
                    )
                    .accessibilityLabel("Resize sticky note")
            }
        }
        .padding(12)
        .frame(width: note.size.width, height: note.size.height)
        .background(noteColor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 2, y: 4)
        .offset(x: 48 + note.offset.width, y: 120 + note.offset.height)
    }
}

private struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let mode: AnnotationMode
    let color: Color
    let controller: CanvasController?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        controller?.canvasView = canvas
        updateTool(on: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        controller?.canvasView = canvas
        updateTool(on: canvas)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func updateTool(on canvas: PKCanvasView) {
        canvas.isUserInteractionEnabled = mode != .note
        switch mode {
        case .highlight:
            let ink = UIColor(color)
            canvas.tool = PKInkingTool(.marker, color: ink.withAlphaComponent(0.52), width: 20)
        case .handwriting:
            canvas.tool = PKInkingTool(.pencil, color: UIColor.black.withAlphaComponent(0.88), width: 2.2)
        case .note:
            break
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas

        init(_ parent: PencilCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

struct PencilAnnotationView_Previews: PreviewProvider {
    static var previews: some View {
        PencilAnnotationView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Import a document to get started")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text("Choose Open PDF/TXT above to bring in a PDF or plain-text file. Text-based PDFs are extracted directly, and scanned PDFs are converted with on-device text recognition. Then highlight passages, write with Apple Pencil, or add notes.")
                    .font(.system(size: 18, design: .serif))
                    .lineSpacing(8)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

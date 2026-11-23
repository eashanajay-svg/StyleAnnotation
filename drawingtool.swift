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
    case yellow, pink, blue, green, purple
    var id: String { rawValue }
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
    var id = UUID()
    var text = ""
    var drawing = PKDrawing()
    var handwritingEnabled = true
    var offset = CGSize.zero
    var size = CGSize(width: 210, height: 190)

    init(saved: SavedStickyNote) {
        id = saved.id
        text = saved.text
        drawing = (try? PKDrawing(data: saved.drawingData)) ?? PKDrawing()
        handwritingEnabled = saved.handwritingEnabled
        offset = CGSize(width: saved.offsetX, height: saved.offsetY)
        size = CGSize(width: saved.width, height: saved.height)
    }

    init() { }

    var saved: SavedStickyNote {
        SavedStickyNote(id: id, text: text, drawingData: drawing.dataRepresentation(),
                        handwritingEnabled: handwritingEnabled, offsetX: offset.width,
                        offsetY: offset.height, width: size.width, height: size.height)
    }
}

private final class CanvasController: ObservableObject {
    weak var canvasView: PKCanvasView?
    func undo() { canvasView?.undoManager?.undo() }
    func redo() { canvasView?.undoManager?.redo() }
    func clear() { canvasView?.drawing = PKDrawing() }
}

struct PencilAnnotationView: View {
    let file: WorkspaceFile
    let onSave: (Data, [SavedStickyNote]) -> Void

    @State private var drawing: PKDrawing
    @State private var mode: AnnotationMode = .highlight
    @State private var selectedColor: AnnotationColor = .yellow
    @State private var stickyNotes: [StickyNote]
    @State private var importError: String?
    @StateObject private var canvasController = CanvasController()
    @State private var autosaveTask: Task<Void, Never>?

    private let pageHeight: CGFloat = 1400

    init(file: WorkspaceFile, onSave: @escaping (Data, [SavedStickyNote]) -> Void) {
        self.file = file
        self.onSave = onSave
        _drawing = State(initialValue: (try? PKDrawing(data: file.drawingData)) ?? PKDrawing())
        _stickyNotes = State(initialValue: file.notes.map(StickyNote.init(saved:)))
    }

    private var canvasHeight: CGFloat { max(pageHeight, CGFloat(max(file.name.count, 1)) * 30 + 1400) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                ZStack(alignment: .topLeading) {
                    documentContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(36)
                    PencilCanvas(drawing: $drawing, mode: mode, color: selectedColor.color, controller: canvasController)
                        .frame(maxWidth: .infinity)
                        .frame(height: canvasHeight)
                    ForEach($stickyNotes) { $note in
                        StickyNoteCard(note: $note) {
                            let id = note.id
                            stickyNotes.removeAll { $0.id == id }
                            scheduleAutosave()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: canvasHeight)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1) }
                .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: drawing) { _ in scheduleAutosave() }
        .onChange(of: stickyNotes) { _ in scheduleAutosave() }
        .onDisappear { saveNow() }
        .alert("Unable to read document", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "The selected document could not be read.") }
    }

    @ViewBuilder
    private var documentContent: some View {
        if file.isPDF, let document = PDFDocument(url: file.fileURL) {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    if let page = document.page(at: index) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Page \(index + 1)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            if let source = page.attributedString(), !source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(AttributedString(source))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            } else {
                                Text((try? recognizeText(on: page)) ?? "")
                                    .font(.system(size: 18, design: .serif))
                                    .lineSpacing(6)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color(uiColor: .secondarySystemBackground).opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        } else if let text = try? String(contentsOf: file.fileURL, encoding: .utf8) {
            VStack(alignment: .leading, spacing: 18) {
                Text(file.name).font(.system(size: 28, weight: .bold, design: .serif))
                Text(text).font(.system(size: 18, design: .serif)).lineSpacing(8).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "doc.text.viewfinder").font(.largeTitle).foregroundStyle(.tint)
                Text(file.name).font(.title2.bold())
                Text("This file could not be displayed. Try removing it and adding a readable PDF or text file.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    ForEach(AnnotationMode.allCases, id: \.self) { tool in
                        Button { mode = tool } label: {
                            Label(tool.rawValue, symbol: tool.symbol)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        autosaveTask?.cancel()
        onSave(drawing.dataRepresentation(), stickyNotes.map(\.saved))
    }

    private func recognizeText(on page: PDFPage) throws -> String {
        let image = page.thumbnail(of: CGSize(width: 1500, height: 2000), for: .mediaBox)
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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
                Text("NOTE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.black.opacity(0.55))
                Spacer()
                Button { note.handwritingEnabled.toggle() } label: {
                    Image(systemName: note.handwritingEnabled ? "keyboard" : "pencil.tip.crop.circle").foregroundStyle(.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.handwritingEnabled ? "Switch to typing" : "Switch to handwriting")
                Button(action: onDelete) { Image(systemName: "xmark.circle.fill").foregroundStyle(.black.opacity(0.45)) }
                    .buttonStyle(.plain).accessibilityLabel("Delete sticky note")
            }
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                note.offset = CGSize(width: dragStart.width + value.translation.width, height: dragStart.height + value.translation.height)
            }.onEnded { _ in dragStart = note.offset })

            if note.handwritingEnabled {
                PencilCanvas(drawing: $note.drawing, mode: .handwriting, color: .black, controller: nil)
                    .background(Color.white.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 3))
                    .accessibilityLabel("Handwriting area for sticky note")
            } else {
                TextEditor(text: $note.text).font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundColor(.black).scrollContentBackground(.hidden).background(Color.clear)
                    .accessibilityLabel("Sticky note text")
            }
            HStack {
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55)).frame(width: 24, height: 24).contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        let start = resizeStart ?? note.size
                        resizeStart = start
                        note.size = CGSize(width: max(150, start.width + value.translation.width), height: max(120, start.height + value.translation.height))
                    }.onEnded { _ in resizeStart = nil })
                    .accessibilityLabel("Resize sticky note")
            }
        }
        .padding(12).frame(width: note.size.width, height: note.size.height).background(noteColor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1) }
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
        canvas.drawingPolicy = .pencilOnly
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        controller?.canvasView = canvas
        updateTool(on: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing { canvas.drawing = drawing }
        controller?.canvasView = canvas
        updateTool(on: canvas)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func updateTool(on canvas: PKCanvasView) {
        canvas.isUserInteractionEnabled = mode != .note
        switch mode {
        case .highlight: canvas.tool = PKInkingTool(.marker, color: UIColor(color).withAlphaComponent(0.52), width: 20)
        case .handwriting: canvas.tool = PKInkingTool(.pencil, color: UIColor.black.withAlphaComponent(0.88), width: 2.2)
        case .note: break
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        init(_ parent: PencilCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { parent.drawing = canvasView.drawing }
    }
}

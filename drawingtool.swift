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

private struct StickyNote: Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var drawing = PKDrawing()
    var handwritingEnabled = true
    var offset = CGSize.zero
    var size = CGSize(width: 210, height: 190)

    static func == (lhs: StickyNote, rhs: StickyNote) -> Bool {
        lhs.id == rhs.id
            && lhs.text == rhs.text
            && lhs.drawing.dataRepresentation() == rhs.drawing.dataRepresentation()
            && lhs.handwritingEnabled == rhs.handwritingEnabled
            && lhs.offset == rhs.offset
            && lhs.size == rhs.size
    }

    init(saved: SavedStickyNote) {
        id = saved.id
        text = saved.text
        drawing = (try? PKDrawing(data: saved.drawingData)) ?? PKDrawing()
        handwritingEnabled = saved.handwritingEnabled
        offset = CGSize(width: saved.offsetX, height: saved.offsetY)
        size = CGSize(width: saved.width, height: saved.height)
    }

    init() { }

    init(offset: CGSize) {
        self.offset = offset
    }

    var saved: SavedStickyNote {
        SavedStickyNote(
            id: id,
            text: text,
            drawingData: drawing.dataRepresentation(),
            handwritingEnabled: handwritingEnabled,
            offsetX: offset.width,
            offsetY: offset.height,
            width: size.width,
            height: size.height
        )
    }
}

private struct AnnotationSnapshot: Equatable {
    let drawing: PKDrawing
    let stickyNotes: [StickyNote]

    static func == (lhs: AnnotationSnapshot, rhs: AnnotationSnapshot) -> Bool {
        lhs.drawing.dataRepresentation() == rhs.drawing.dataRepresentation()
            && lhs.stickyNotes == rhs.stickyNotes
    }
}

private final class CanvasController: ObservableObject {
    weak var canvasView: PKCanvasView?
    var onDrawingBegan: (() -> Void)?
    var onDrawingEnded: (() -> Void)?
}

struct PencilAnnotationView: View {
    let file: WorkspaceFile
    let onSave: (Data, [SavedStickyNote]) -> Void

    @State private var drawing: PKDrawing
    @State private var mode: AnnotationMode = .highlight
    @State private var selectedColor: AnnotationColor = .yellow
    @State private var stickyNotes: [StickyNote]
    @State private var importError: String?
    @State private var isDeleteAllConfirmationPresented = false
    @State private var undoHistory: [AnnotationSnapshot] = []
    @State private var redoHistory: [AnnotationSnapshot] = []
    @State private var historySnapshot: AnnotationSnapshot
    @State private var drawingHistoryBaseline: AnnotationSnapshot?
    @StateObject private var canvasController = CanvasController()
    @State private var autosaveTask: Task<Void, Never>?

    private let pageHeight: CGFloat = 1400

    init(file: WorkspaceFile, onSave: @escaping (Data, [SavedStickyNote]) -> Void) {
        self.file = file
        self.onSave = onSave
        let initialDrawing = (try? PKDrawing(data: file.drawingData)) ?? PKDrawing()
        let initialStickyNotes = file.notes.map(StickyNote.init(saved:))
        _drawing = State(initialValue: initialDrawing)
        _stickyNotes = State(initialValue: initialStickyNotes)
        _historySnapshot = State(initialValue: AnnotationSnapshot(
            drawing: initialDrawing,
            stickyNotes: initialStickyNotes
        ))
    }

    private var canvasHeight: CGFloat {
        let nameHeight = CGFloat(max(file.name.count, 1)) * 30
        return max(pageHeight, nameHeight + 1400)
    }

    private var currentSnapshot: AnnotationSnapshot {
        AnnotationSnapshot(drawing: drawing, stickyNotes: stickyNotes)
    }

    private var hasAnnotations: Bool {
        !drawing.strokes.isEmpty || !stickyNotes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            annotationCanvas
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            canvasController.onDrawingBegan = { beginDrawingHistoryGroup() }
            canvasController.onDrawingEnded = { finishDrawingHistoryGroup() }
        }
        .onChange(of: drawing) { _ in
            recordHistoryChange()
            scheduleAutosave()
        }
        .onChange(of: stickyNotes) { _ in
            recordHistoryChange()
            scheduleAutosave()
        }
        .onDisappear { saveNow() }
        .confirmationDialog(
            "Delete all annotations?",
            isPresented: $isDeleteAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllAnnotations()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all drawings and sticky notes from this file.")
        }
        .alert(
            "Unable to read document",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "The selected document could not be read.")
        }
    }

    private var annotationCanvas: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                documentContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(36)

                PencilCanvas(
                    drawing: $drawing,
                    mode: mode,
                    color: selectedColor.color,
                    controller: canvasController
                )
                .frame(maxWidth: .infinity)
                .frame(height: canvasHeight)
                .allowsHitTesting(mode != .note)

                stickyNotesOverlay
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                addStickyNote(at: location)
            }
            .frame(maxWidth: .infinity)
            .frame(height: canvasHeight)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(canvasOverlay)
            .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var canvasOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
    }

    private var stickyNotesOverlay: some View {
        ForEach($stickyNotes) { $note in
            StickyNoteCard(note: $note) {
                removeStickyNote(note.id)
            }
        }
    }

    private func addStickyNote(at location: CGPoint) {
        guard mode == .note else { return }
        let offset = CGSize(
            width: location.x - 48 - 105,
            height: location.y - 120 - 95
        )
        stickyNotes.append(StickyNote(offset: offset))
        scheduleAutosave()
    }

    private func removeStickyNote(_ id: UUID) {
        stickyNotes.removeAll { $0.id == id }
        scheduleAutosave()
    }

    private func recordHistoryChange() {
        let snapshot = currentSnapshot
        guard snapshot != historySnapshot else { return }

        // PencilKit reports changes throughout a stroke. Group those callbacks
        // into one undo step, rather than making undo stop at partial strokes.
        if drawingHistoryBaseline != nil {
            historySnapshot = snapshot
            return
        }

        undoHistory.append(historySnapshot)
        redoHistory.removeAll()
        historySnapshot = snapshot
    }

    private func beginDrawingHistoryGroup() {
        guard drawingHistoryBaseline == nil else { return }
        let snapshot = currentSnapshot
        historySnapshot = snapshot
        drawingHistoryBaseline = snapshot
    }

    private func finishDrawingHistoryGroup() {
        guard let baseline = drawingHistoryBaseline else { return }
        drawingHistoryBaseline = nil
        let snapshot = currentSnapshot
        historySnapshot = snapshot
        guard snapshot != baseline else { return }
        undoHistory.append(baseline)
        redoHistory.removeAll()
    }

    private func undo() {
        guard drawingHistoryBaseline == nil, let previous = undoHistory.popLast() else { return }
        redoHistory.append(currentSnapshot)
        historySnapshot = previous
        drawing = previous.drawing
        stickyNotes = previous.stickyNotes
        scheduleAutosave()
    }

    private func redo() {
        guard drawingHistoryBaseline == nil, let next = redoHistory.popLast() else { return }
        undoHistory.append(currentSnapshot)
        historySnapshot = next
        drawing = next.drawing
        stickyNotes = next.stickyNotes
        scheduleAutosave()
    }

    private func deleteAllAnnotations() {
        guard drawingHistoryBaseline == nil, hasAnnotations else { return }
        let cleared = AnnotationSnapshot(drawing: PKDrawing(), stickyNotes: [])
        undoHistory.append(currentSnapshot)
        redoHistory.removeAll()
        historySnapshot = cleared
        drawing = cleared.drawing
        stickyNotes = cleared.stickyNotes
        scheduleAutosave()
    }

    @ViewBuilder
    private var documentContent: some View {
        if file.isPDF, let document = PDFDocument(url: file.fileURL) {
            pdfContent(document)
        } else if let text = try? String(contentsOf: file.fileURL, encoding: .utf8) {
            textContent(text)
        } else {
            unreadableDocumentContent
        }
    }

    private func pdfContent(_ document: PDFDocument) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(0..<document.pageCount, id: \.self) { index in
                if let page = document.page(at: index) {
                    PDFPageContent(page: page, pageNumber: index + 1, recognizeText: recognizeText)
                }
            }
        }
    }

    private func textContent(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(file.name)
                .font(.system(size: 28, weight: .bold, design: .serif))
            Text(text)
                .font(.system(size: 18, design: .serif))
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var unreadableDocumentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "doc.text.viewfinder")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(file.name)
                .font(.title2.bold())
            Text("This file could not be displayed. Try removing it and adding a readable PDF or text file.")
                .foregroundStyle(.secondary)
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                modeButtons
                if mode == .highlight {
                    colorButtons
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 24)
                historyButtons
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var historyButtons: some View {
        HStack(spacing: 8) {
            Button(action: undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(undoHistory.isEmpty || drawingHistoryBaseline != nil)
            .accessibilityHint("Undo the most recent drawing or sticky note change")

            Button(action: redo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(redoHistory.isEmpty || drawingHistoryBaseline != nil)
            .accessibilityHint("Redo the most recently undone change")

            Button {
                isDeleteAllConfirmationPresented = true
            } label: {
                Label("Delete All", systemImage: "trash")
            }
            .disabled(!hasAnnotations || drawingHistoryBaseline != nil)
            .tint(.red)
            .accessibilityHint("Delete all drawings and sticky notes in this file")
        }
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private var modeButtons: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationMode.allCases, id: \.self) { tool in
                modeButton(tool)
            }
        }
    }

    private func modeButton(_ tool: AnnotationMode) -> some View {
        Button {
            mode = tool
        } label: {
            modeButtonLabel(tool)
        }
        .buttonStyle(.plain)
    }

    private func modeButtonLabel(_ tool: AnnotationMode) -> some View {
        let isSelected = mode == tool
        return Label(tool.rawValue, systemImage: tool.symbol)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var colorButtons: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationColor.allCases) { annotationColor in
                colorButton(annotationColor)
            }
        }
    }

    private func colorButton(_ annotationColor: AnnotationColor) -> some View {
        Button {
            selectedColor = annotationColor
        } label: {
            colorButtonLabel(annotationColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(annotationColor.rawValue) highlight")
    }

    private func colorButtonLabel(_ annotationColor: AnnotationColor) -> some View {
        let isSelected = selectedColor == annotationColor
        let strokeOpacity = isSelected ? 0.8 : 0.15
        let strokeWidth: CGFloat = isSelected ? 2 : 1

        return Circle()
            .fill(annotationColor.color)
            .frame(width: 22, height: 22)
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(strokeOpacity), lineWidth: strokeWidth)
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
        let observations = request.results ?? []
        return observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.joined(separator: "\n")
    }
}

private struct PDFPageContent: View {
    let page: PDFPage
    let pageNumber: Int
    let recognizeText: (PDFPage) throws -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Page \(pageNumber)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if let source = page.attributedString,
               !source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                attributedText(source.string)
            } else {
                recognizedText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func attributedText(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var recognizedText: some View {
        Text((try? recognizeText(page)) ?? "")
            .font(.system(size: 18, design: .serif))
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
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
            noteHeader

            if note.handwritingEnabled {
                handwritingEditor
            } else {
                textEditor
            }

            resizeHandle
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

    private var noteHeader: some View {
        HStack {
            Text("NOTE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.55))
            Spacer()
            handwritingToggleButton
            deleteButton
        }
        .contentShape(Rectangle())
        .gesture(makeDragGesture())
    }

    private var handwritingToggleButton: some View {
        let iconName = note.handwritingEnabled
            ? "keyboard"
            : "pencil.tip.crop.circle"
        let accessibilityLabel = note.handwritingEnabled
            ? "Switch to typing"
            : "Switch to handwriting"

        return Button {
            note.handwritingEnabled.toggle()
        } label: {
            Image(systemName: iconName)
                .foregroundStyle(.black.opacity(0.65))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.black.opacity(0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete sticky note")
    }

    private func makeDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                updateDragOffset(value)
            }
            .onEnded { _ in
                dragStart = note.offset
            }
    }

    private func updateDragOffset(_ value: DragGesture.Value) {
        let width = dragStart.width + value.translation.width
        let height = dragStart.height + value.translation.height
        note.offset = CGSize(width: width, height: height)
    }

    private var handwritingEditor: some View {
        PencilCanvas(
            drawing: $note.drawing,
            mode: .handwriting,
            color: .black,
            controller: nil
        )
        .background(Color.white.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityLabel("Handwriting area for sticky note")
    }

    private var textEditor: some View {
        TextEditor(text: $note.text)
            .font(.system(size: 16, weight: .light, design: .rounded))
            .foregroundColor(.black)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .accessibilityLabel("Sticky note text")
    }

    private var resizeHandle: some View {
        HStack {
            Spacer()
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.55))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .gesture(makeResizeGesture())
                .accessibilityLabel("Resize sticky note")
        }
    }

    private func makeResizeGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                updateSize(value)
            }
            .onEnded { _ in
                resizeStart = nil
            }
    }

    private func updateSize(_ value: DragGesture.Value) {
        let start = resizeStart ?? note.size
        resizeStart = start

        let width = max(150, start.width + value.translation.width)
        let height = max(120, start.height + value.translation.height)
        note.size = CGSize(width: width, height: height)
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
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        controller?.canvasView = canvas
        updateTool(on: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing { canvas.drawing = drawing }
        canvas.isUserInteractionEnabled = mode != .note
        controller?.canvasView = canvas
        updateTool(on: canvas)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func updateTool(on canvas: PKCanvasView) {
        switch mode {
        case .highlight:
            canvas.tool = PKInkingTool(
                .marker,
                color: UIColor(color).withAlphaComponent(0.52),
                width: 24
            )
        case .handwriting:
            canvas.tool = PKInkingTool(
                .pencil,
                color: UIColor.black.withAlphaComponent(0.88),
                width: 2.2
            )
        case .note:
            break
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        init(_ parent: PencilCanvas) { self.parent = parent }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            parent.controller?.onDrawingBegan?()
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            parent.controller?.onDrawingEnded?()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

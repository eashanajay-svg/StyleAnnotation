import Combine
import PencilKit
import SwiftUI
import UIKit

private enum AnnotationMode: String, CaseIterable {
    case highlight = "Highlight"
    case note = "Note"

    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
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

    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.83, blue: 0.25)
        case .pink: return Color(red: 0.96, green: 0.48, blue: 0.62)
        case .blue: return Color(red: 0.35, green: 0.67, blue: 0.95)
        case .green: return Color(red: 0.32, green: 0.76, blue: 0.56)
        case .purple: return Color(red: 0.65, green: 0.52, blue: 0.91)
        }
    }
}

private struct StickyNote: Identifiable {
    let id = UUID()
    var text = ""
    var offset = CGSize.zero
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

/// A document surface with Apple Pencil highlighting and editable sticky notes.
struct PencilAnnotationView<Content: View>: View {
    private let content: Content
    private let pageHeight: CGFloat

    @State private var drawing = PKDrawing()
    @State private var mode: AnnotationMode = .highlight
    @State private var selectedColor: AnnotationColor = .yellow
    @State private var stickyNotes: [StickyNote] = []
    @StateObject private var canvasController = CanvasController()

    init(
        pageHeight: CGFloat = 1100,
        @ViewBuilder content: () -> Content
    ) {
        self.pageHeight = pageHeight
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView {
                ZStack(alignment: .topLeading) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(36)

                    PencilCanvas(
                        drawing: $drawing,
                        mode: mode,
                        color: selectedColor.color,
                        controller: canvasController
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: pageHeight)

                    ForEach($stickyNotes) { $note in
                        StickyNoteCard(note: $note) {
                            let noteID = note.id
                            stickyNotes.removeAll { $0.id == noteID }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: pageHeight)
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
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

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
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stickyNotes.append(StickyNote())
                    }
                } label: {
                    Label("Add sticky note", systemImage: "note.text.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Adds an editable yellow sticky note to the page")
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
}

private struct StickyNoteCard: View {
    @Binding var note: StickyNote
    let onDelete: () -> Void
    @State private var dragStart = CGSize.zero

    private let noteColor = Color(red: 1.0, green: 0.91, blue: 0.43)

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("NOTE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.black.opacity(0.55))

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.black.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete sticky note")
            }

            TextEditor(text: $note.text)
                .font(.system(size: 16, weight: .light, design: .rounded))
                .foregroundColor(.black)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .accessibilityLabel("Sticky note text")
        }
        .padding(12)
        .frame(width: 210, height: 190)
        .background(noteColor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 2, y: 4)
        .offset(x: 48 + note.offset.width, y: 120 + note.offset.height)
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
    }
}

private struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let mode: AnnotationMode
    let color: Color
    let controller: CanvasController

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        controller.canvasView = canvas
        updateTool(on: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        controller.canvasView = canvas
        updateTool(on: canvas)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func updateTool(on canvas: PKCanvasView) {
        canvas.isUserInteractionEnabled = mode == .highlight
        if mode == .highlight {
            let ink = UIColor(color)
            canvas.tool = PKInkingTool(.marker, color: ink.withAlphaComponent(0.4), width: 20)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: PencilCanvas

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
                Text("FIELD NOTES")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)

                Text("The art of noticing")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(Color.primary)

                Text("Small observations can change the way we understand a place.")
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundStyle(.secondary)

                Text("A careful walk is a kind of attention. It asks us to slow down, look beyond the obvious, and notice details that might otherwise pass without a name. The shape of a shadow can tell us where the sun has been, while a worn path hints at the choices people make every day. Try highlighting a sentence, or add a yellow sticky note with your own thought.")
                    .font(.system(size: 18, design: .serif))
                    .lineSpacing(9)
                    .foregroundStyle(Color.primary.opacity(0.85))

                Text("Look closely")
                    .font(.system(size: 23, weight: .semibold, design: .serif))
                    .padding(.top, 8)

                Text("Choose a phrase that stays with you. Use the Highlight tool to mark it. Switch to Note and choose Add sticky note to place a movable, editable note on the page.")
                    .font(.system(size: 18, design: .serif))
                    .lineSpacing(9)
                    .foregroundStyle(Color.primary.opacity(0.85))

                Spacer()
            }
        }
    }
}

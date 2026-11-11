import PencilKit
import SwiftUI
import UIKit

private enum AnnotationMode: String, CaseIterable {
    case highlight = "Highlight"
    case note = "Note"

    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
        case .note: return "pencil.tip"
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

/// A document surface with Apple Pencil highlighting and freehand note tools.
struct PencilAnnotationView<Content: View>: View {
    private let content: Content
    private let pageHeight: CGFloat

    @State private var drawing = PKDrawing()
    @State private var mode: AnnotationMode = .highlight
    @State private var selectedColor: AnnotationColor = .yellow
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
        HStack(spacing: 16) {
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
                            .padding(.horizontal, 12)
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

            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 24)

            HStack(spacing: 10) {
                ForEach(AnnotationColor.allCases) { choice in
                    Button {
                        selectedColor = choice
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 22, height: 22)
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
                    .accessibilityLabel("\(choice.rawValue) ink")
                    .accessibilityAddTraits(selectedColor == choice ? .isSelected : [])
                }
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

            Button(action: canvasController.clear) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Clear annotations")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
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
        let ink = UIColor(color)
        switch mode {
        case .highlight:
            canvas.tool = PKInkingTool(.marker, color: ink.withAlphaComponent(0.4), width: 20)
        case .note:
            canvas.tool = PKInkingTool(.pen, color: ink, width: 3)
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

                Text("A careful walk is a kind of attention. It asks us to slow down, to look beyond the obvious, and to notice the details that would otherwise pass without a name. The shape of a shadow can tell us where the sun has been, while a worn path hints at the choices people make every day.")
                    .font(.system(size: 18, design: .serif))
                    .lineSpacing(9)
                    .foregroundStyle(Color.primary.opacity(0.85))

                Text("Look closely")
                    .font(.system(size: 23, weight: .semibold, design: .serif))
                    .padding(.top, 8)

                Text("Choose a phrase that stays with you. Mark it with the highlighter, then switch to the pencil to add a thought in the margin.")
                    .font(.system(size: 18, design: .serif))
                    .lineSpacing(9)
                    .foregroundStyle(Color.primary.opacity(0.85))

                Spacer()
            }
        }
    }
}

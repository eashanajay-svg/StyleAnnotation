import SwiftUI

@main
struct StyleAnnotationApp: App {
    var body: some Scene {
        WindowGroup {
            PencilAnnotationView(pageHeight: 1400) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("FIELD NOTES  /  ISSUE 01")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.secondary)

                    Text("The art of noticing")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)

                    Text("A short guide to paying attention to the places we pass through every day.")
                        .font(.system(size: 19, weight: .medium, design: .serif))
                        .foregroundStyle(.secondary)

                    Text("A careful walk is a kind of attention. It asks us to slow down, look beyond the obvious, and notice details that might otherwise pass without a name. The shape of a shadow can tell us where the sun has been. A worn path hints at the choices people make every day. Even a small crack in a wall can hold a story about weather, time, and repair.")
                        .font(.system(size: 18, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(.primary.opacity(0.85))

                    Text("Look closely")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .padding(.top, 6)

                    Text("Choose a phrase that stays with you. Use the Highlight tool and a color swatch to mark a passage. Your marks are drawn directly over the page, so try highlighting a full sentence or just a few words.")
                        .font(.system(size: 18, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(.primary.opacity(0.85))

                    Text("A pause in the path")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .padding(.top, 6)

                    Text("At the corner of the garden, the noise of the street softens. Leaves turn in the breeze, and a bench holds the warmth of the afternoon sun. Someone has left a paper cup beside the path; nearby, tiny flowers have pushed through the soil. The scene is ordinary, but only if we hurry past it.")
                        .font(.system(size: 18, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(.primary.opacity(0.85))

                    Text("Make a note")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .padding(.top, 6)

                    Text("Switch to Note, then tap Add sticky note. Type a thought on the yellow note and drag it to the passage it belongs to. For example: What detail would I have missed if I had walked faster?")
                        .font(.system(size: 18, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(.primary.opacity(0.85))

                    Text("Try it")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .padding(.top, 6)

                    Text("Highlight one image that feels vivid. Add a sticky note with a question, a memory, or a detail you want to remember. Use Undo and Redo to explore changes, or Clear to start again.")
                        .font(.system(size: 18, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(.primary.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

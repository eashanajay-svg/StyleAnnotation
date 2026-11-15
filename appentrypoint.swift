import SwiftUI

@main
struct StyleAnnotationApp: App {
    var body: some Scene {
        WindowGroup {
            PencilAnnotationView(pageHeight: 1400) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.tint)
                        .padding(.bottom, 6)

                    Text("Bring your own reading")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)

                    Text("Open a PDF or TXT file to turn its contents into an annotatable page. Text PDFs are extracted directly, and scanned PDFs are read with on-device text recognition.")
                        .font(.system(size: 18, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(.primary.opacity(0.8))

                    Text("After importing, choose Highlight to mark passages, Handwriting to write with Apple Pencil, or Note to add a movable sticky note.")
                        .font(.system(size: 16, design: .serif))
                        .lineSpacing(7)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 70)
            }
        }
    }
}

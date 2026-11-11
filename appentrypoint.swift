import SwiftUI

@main
struct StyleAnnotationApp: App {
    var body: some Scene {
        WindowGroup {
            PencilAnnotationView {
                Text("Start annotating")
                    .padding()
            }
        }
    }
}

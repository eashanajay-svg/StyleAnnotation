import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceFile: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var storedFileName: String
    var drawingData: Data = PKDrawing().dataRepresentation()
    var notes: [SavedStickyNote] = []

    var fileURL: URL { WorkspaceStore.filesDirectory.appendingPathComponent(storedFileName) }
    var isPDF: Bool { fileURL.pathExtension.lowercased() == "pdf" }
}

struct SavedStickyNote: Codable, Identifiable {
    var id: UUID = UUID()
    var text = ""
    var drawingData = PKDrawing().dataRepresentation()
    var handwritingEnabled = true
    var offsetX = 0.0
    var offsetY = 0.0
    var width = 210.0
    var height = 190.0
}

struct Workspace: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var files: [WorkspaceFile] = []
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []

    private static let rootDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("StyleAnnotation", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let filesDirectory: URL = {
        let directory = rootDirectory.appendingPathComponent("WorkspaceFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private var storeURL: URL { Self.rootDirectory.appendingPathComponent("workspaces.json") }

    init() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = saved
        }
    }

    func createWorkspace(named name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        workspaces.insert(Workspace(name: cleanName), at: 0)
        persist()
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        workspaces[index].name = cleanName
        persist()
    }

    func deleteWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspace.files.forEach { try? FileManager.default.removeItem(at: $0.fileURL) }
        workspaces.removeAll { $0.id == id }
        persist()
    }

    func addFiles(_ urls: [URL], to workspaceID: UUID) throws {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        for sourceURL in urls {
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
            let fileID = UUID()
            let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
            let storedName = "\(fileID.uuidString).\(ext)"
            let destination = Self.filesDirectory.appendingPathComponent(storedName)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            let displayName = sourceURL.deletingPathExtension().lastPathComponent
            workspaces[workspaceIndex].files.append(WorkspaceFile(name: displayName, storedFileName: storedName))
        }
        persist()
    }

    func saveAnnotations(drawingData: Data, notes: [SavedStickyNote], workspaceID: UUID, fileID: UUID) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let fileIndex = workspaces[workspaceIndex].files.firstIndex(where: { $0.id == fileID }) else { return }
        workspaces[workspaceIndex].files[fileIndex].drawingData = drawingData
        workspaces[workspaceIndex].files[fileIndex].notes = notes
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

@main
struct StyleAnnotationApp: App {
    @StateObject private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceHomeView()
                .environmentObject(store)
        }
    }
}

private struct WorkspaceHomeView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var isCreatingWorkspace = false
    @State private var newWorkspaceName = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.workspaces.isEmpty {
                    ContentUnavailableView {
                        Label("Your workspaces", systemImage: "folder")
                    } description: {
                        Text("Create a workspace for each class, project, or set of reading materials.")
                    } actions: {
                        Button("Create workspace") { isCreatingWorkspace = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.workspaces) { workspace in
                            NavigationLink(value: workspace.id) {
                                HStack(spacing: 14) {
                                    Image(systemName: "folder.fill")
                                        .font(.title2)
                                        .foregroundStyle(.tint)
                                        .frame(width: 34)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workspace.name).font(.headline)
                                        Text("\(workspace.files.count) \(workspace.files.count == 1 ? "file" : "files")")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") {
                                    newWorkspaceName = workspace.name
                                    isCreatingWorkspace = true
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.deleteWorkspace(workspace.id)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("StyleAnnotation")
            .navigationDestination(for: UUID.self) { workspaceID in
                WorkspaceDetailView(workspaceID: workspaceID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newWorkspaceName = ""; isCreatingWorkspace = true } label: {
                        Label("New workspace", systemImage: "plus")
                    }
                    .accessibilityHint("Create a named workspace for your documents")
                }
            }
            .alert("New workspace", isPresented: $isCreatingWorkspace) {
                TextField("Workspace name", text: $newWorkspaceName)
                Button("Cancel", role: .cancel) { }
                Button("Save") { store.createWorkspace(named: newWorkspaceName) }
            } message: {
                Text("Give this workspace a name you can recognize later.")
            }
        }
    }
}

private struct WorkspaceDetailView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let workspaceID: UUID
    @State private var isImporterPresented = false
    @State private var importError: String?

    private var workspace: Workspace? { store.workspaces.first { $0.id == workspaceID } }

    var body: some View {
        Group {
            if let workspace {
                if workspace.files.isEmpty {
                    ContentUnavailableView {
                        Label("No files yet", systemImage: "doc.badge.plus")
                    } description: {
                        Text("Add PDFs or text files to this workspace. Your annotations are saved separately for each file.")
                    } actions: {
                        Button("Add files") { isImporterPresented = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(workspace.files) { file in
                            NavigationLink {
                                PencilAnnotationView(file: file) { drawing, notes in
                                    store.saveAnnotations(drawingData: drawing, notes: notes, workspaceID: workspaceID, fileID: file.id)
                                }
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.name).font(.headline)
                                        Text(file.isPDF ? "PDF · annotations autosave" : "Text · annotations autosave")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: file.isPDF ? "doc.richtext" : "doc.text")
                                        .foregroundStyle(.tint)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else {
                ContentUnavailableView("Workspace not found", systemImage: "folder.badge.questionmark")
            }
        }
        .navigationTitle(workspace?.name ?? "Workspace")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isImporterPresented = true } label: { Label("Add files", systemImage: "plus") }
            }
        }
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: [.pdf, .plainText],
                      allowsMultipleSelection: true) { result in
            do {
                try store.addFiles(result.get(), to: workspaceID)
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Unable to add files", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "Please choose a readable PDF or text file.")
        }
    }
}

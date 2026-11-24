import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// ManageClipboardItemsActivity + ClipsActivityAdapter: pinned clips with add/edit, delete, drag to reorder,
/// import and export.
struct ManageClipboardItemsView: View {
    @Environment(ClipsStore.self) private var store
    @Environment(\.palette) private var palette
    @State private var selection = Set<Int64>()
    @State private var order: [Clip]?
    @State private var editing: EditClip?
    @State private var confirmDelete = false
    @State private var exportDialog = false
    @State private var exportFile: URL?
    @State private var importing = false
    @State private var toast: String?

    struct EditClip: Identifiable {
        var clip: Clip?
        var id: Int64 { clip?.id ?? 0 }
    }

    private var clips: [Clip] { order ?? store.clips }

    var body: some View {
        VStack(spacing: 0) {
            if selection.isEmpty {
                TopBar(title: "Manage clipboard items", onBack: nil, background: nil, tint: nil) {
                    IconButton(icon: "plus") { editing = EditClip(clip: nil) }
                    OverflowMenu {
                        Button("Import clipboard items") { importing = true }
                        Button("Export clipboard items") { exportClips() }
                    }
                }
            } else {
                ActionModeBar(count: selection.count, onClose: finishActMode) {
                    if selection.count == 1 {
                        IconButton(icon: "pencil") { editing = EditClip(clip: clips.first { selection.contains($0.id) }) }
                    }
                    IconButton(icon: "trash") { confirmDelete = true }
                }
            }
            if clips.isEmpty {
                VStack(spacing: 16) {
                    Text("Your clipboard is empty.\n\nYou can manage or add clips here for quick access.")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.textColor)
                        .multilineTextAlignment(.center)
                    Button { editing = EditClip(clip: nil) } label: {
                        Text("Add a new item").underline().font(.system(size: 16)).foregroundStyle(palette.primaryColor)
                    }
                }
                .padding(.top, 48)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    ForEach(clips) { clip in
                        row(clip)
                            .listRowBackground(selection.contains(clip.id) ? palette.primaryColor.opacity(0.25) : palette.backgroundColor)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    }
                    .onMove(perform: selection.isEmpty ? nil : move)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(selection.isEmpty ? .inactive : .active))
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .toast($toast)
        .sheet(item: $editing) { e in
            AddOrEditClipDialog(original: e.clip) { finishActMode() }
        }
        .confirmationDialog("Are you sure you want to proceed with the deletion?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Yes", role: .destructive) {
                store.delete(selection)
                order = nil
                selection.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $exportDialog) {
            ExportTextFileDialog(title: "Export clipboard items", defaultName: "Keyboard_\(AutoBackup.currentFormattedDateTime())") { name in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".txt")
                do {
                    let json = try JSONEncoder().encode(store.clips.map(\.value))
                    try json.write(to: url, options: .atomic)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exportFile = url }
                } catch {
                    toast = "An unknown error occurred"
                }
            }
        }
        .fileMover(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }), file: exportFile) { result in
            if case .success = result { toast = "Exporting successful" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .json, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String].self, from: data) else {
                toast = "An unknown error occurred"
                return
            }
            let imported = values.filter { store.insertClip($0) > 0 }.count
            toast = imported > 0 ? "Importing successful" : "No new entries for importing have been found"
        }
    }

    private func row(_ clip: Clip) -> some View {
        Text(clip.value)
            .font(.system(size: palette.fontSize))
            .foregroundStyle(palette.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                if selection.isEmpty {
                    editing = EditClip(clip: clip)
                } else {
                    toggleSelection(clip.id, in: &selection)
                    if selection.isEmpty { finishActMode() }
                }
            }
            .onLongPressGesture { toggleSelection(clip.id, in: &selection) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = clips
        reordered.move(fromOffsets: source, toOffset: destination)
        order = reordered
    }

    /// onActionModeDestroyed(): persist a changed order by re-inserting the clips.
    private func finishActMode() {
        if let order {
            store.replaceAll(with: order)
            self.order = nil
        }
        selection.removeAll()
    }

    private func exportClips() {
        if store.clips.isEmpty {
            toast = "No entries for exporting have been found"
        } else {
            exportDialog = true
        }
    }
}

/// AddOrEditClipDialog.
struct AddOrEditClipDialog: View {
    @Environment(ClipsStore.self) private var store
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let original: Clip?
    let onSaved: () -> Void
    @State private var value: String
    @State private var error: String?
    @FocusState private var focused: Bool

    init(original: Clip?, onSaved: @escaping () -> Void) {
        self.original = original
        self.onSaved = onSaved
        _value = State(initialValue: original?.value ?? "")
    }

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            Text("Clip text").font(.system(size: 13)).foregroundStyle(palette.primaryColor)
            TextField("", text: $value, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .padding(.vertical, 8)
            Divider().overlay(palette.primaryColor)
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(.red).padding(.top, 6)
            }
            DialogButtons {
                if value.isEmpty {
                    error = "Value cannot be empty"
                    return
                }
                store.insertClip(value, id: original?.id)
                onSaved()
                dismiss()
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}

/// ManageKeyboardLanguagesDialog: tick the languages to switch between.
struct ManageKeyboardLanguagesDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(KeyboardLanguage.supported.sorted { KeyboardLanguage.title($0) < KeyboardLanguage.title($1) }, id: \.self) { language in
                        CheckRow(title: KeyboardLanguage.title(language), on: Binding(
                            get: { selected.contains(language) },
                            set: { if $0 { selected.insert(language) } else { selected.remove(language) } }))
                    }
                }
            }
            DialogButtons {
                var languages = selected
                if languages.isEmpty { languages.insert(Config.defaultLanguage) }
                config.selectedLanguages = languages
                if !languages.contains(config.keyboardLanguage) {
                    config.keyboardLanguage = config.selectedLanguagesSorted.first ?? Config.defaultLanguage
                }
                dismiss()
            }
        }
        .presentationDetents([.large])
        .onAppear { selected = config.selectedLanguages }
    }
}

#if os(iOS)
import SwiftUI
import DejaViCore

struct iOSAlbumPicker: View {
    let viewModel: SearchViewModel
    var onSelect: (String) -> Void
    var onCreateNew: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [String] = []
    @State private var newAlbumName = ""
    @State private var showNewAlbum = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if showNewAlbum {
                        HStack {
                            TextField("Album name", text: $newAlbumName)
                            Button("Create") {
                                guard !newAlbumName.isEmpty else { return }
                                onCreateNew(newAlbumName)
                                dismiss()
                            }
                            .disabled(newAlbumName.isEmpty)
                        }
                    } else {
                        Button {
                            showNewAlbum = true
                        } label: {
                            Label("Create New Album", systemImage: "plus")
                        }
                    }
                }

                Section("Albums") {
                    ForEach(albums, id: \.self) { album in
                        Button(album) {
                            onSelect(album)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if let actions = viewModel.photoActions {
                    albums = await actions.fetchAlbumNames()
                }
            }
        }
    }
}
#endif

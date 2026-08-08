import SwiftUI

/// Manage the followed locations: select, search, add and remove.
struct LocationManagerSheet: View {
    @ObservedObject private var store = LocationStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [AemetMunicipio] = []
    @State private var cached: [AemetMunicipio] = []
    @State private var debounce: Task<Void, Never>? = nil

    /// Called after the selection changes so the AEMET view can reload.
    let onChange: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Buscar y añadir") {
                    TextField("Municipio…", text: $searchText)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, newVal in
                            debounce?.cancel()
                            if newVal.count < 2 { results = []; return }
                            debounce = Task {
                                try? await Task.sleep(for: .milliseconds(300))
                                guard !Task.isCancelled else { return }
                                await search(newVal)
                            }
                        }
                    ForEach(results) { r in
                        Button { add(r) } label: {
                            HStack {
                                Text(r.nombre).foregroundStyle(.primary)
                                Spacer()
                                if store.locations.contains(where: { $0.code == r.codMunicipio }) {
                                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(AppTheme.green)
                                }
                            }
                        }
                    }
                }

                Section("Mis ubicaciones") {
                    ForEach(store.locations) { loc in
                        Button {
                            store.select(loc.code)
                            onChange()
                            dismiss()
                        } label: {
                            HStack {
                                Text(loc.name).foregroundStyle(.primary)
                                if let p = loc.province {
                                    Text(p).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if loc.code == store.selectedCode {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { store.remove(store.locations[i].code) }
                    }
                    if store.locations.count <= 1 {
                        Text("Mantén al menos una ubicación.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ubicaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private func add(_ m: AemetMunicipio) {
        store.add(store.makeLocation(from: m))
        onChange()
        searchText = ""
        results = []
    }

    private func search(_ query: String) async {
        if cached.isEmpty {
            cached = (try? await AEMETService.shared.allMunicipios()) ?? []
        }
        let q = query.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        results = Array(
            (cached
                .filter { $0.nombre.lowercased().folding(options: .diacriticInsensitive, locale: .current).contains(q) }
             + IPMA.searchAsMunicipios(query))
                .prefix(15)
        )
    }
}

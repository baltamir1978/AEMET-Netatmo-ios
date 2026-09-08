import SwiftUI

/// Manage the followed locations: select, search, add and remove.
struct LocationManagerSheet: View {
    @ObservedObject private var store = LocationStore.shared
    @ObservedObject private var search = LocationSearch.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    /// Calculado, no guardado: el índice responde en memoria, así que buscar cuesta menos
    /// que arrastrar el resultado en `@State` — y en cuanto el catálogo termina de cargar,
    /// la vista se recalcula sola con la búsqueda ya hecha.
    private var results: [LocationSuggestion] { search.search(searchText) }

    /// Called after the selection changes so the AEMET view can reload.
    let onChange: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Buscar y añadir") {
                    TextField("Municipio…", text: $searchText)
                        .autocorrectionDisabled()
                    if results.isEmpty, !searchText.isEmpty, search.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Cargando el listado de municipios…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(results) { r in
                        Button { add(r) } label: {
                            HStack {
                                Text(r.name).foregroundStyle(.primary)
                                if let m = r.municipality {
                                    Text(m).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.locations.contains(where: { $0.code == r.code }) {
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
            .task { search.prepare() }
            .navigationTitle("Ubicaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private func add(_ m: LocationSuggestion) {
        store.add(store.makeLocation(from: m))
        onChange()
        searchText = ""
    }
}

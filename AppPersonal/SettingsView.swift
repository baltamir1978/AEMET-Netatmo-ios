import SwiftUI

struct SettingsView: View {
    @ObservedObject private var cfg = AppConfiguration.shared

    var body: some View {
        NavigationStack {
            Form {
                netatmoSection
                stationSection
                windSection
                favoritesSection
                aemetSection
                helpSection
            }
            .navigationTitle("Ajustes")
        }
    }

    // MARK: - Netatmo OAuth credentials

    private var netatmoSection: some View {
        Section {
            LabeledContent("Client ID") {
                TextField("", text: $cfg.netatmoClientId)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            LabeledContent("Client Secret") {
                SecureField("", text: $cfg.netatmoClientSecret)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Refresh Token") {
                SecureField("", text: $cfg.netatmoRefreshToken)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Netatmo · Credenciales OAuth")
        } footer: {
            Text("Obtén tus credenciales en dev.netatmo.com. El refresh token lo genera auth.py la primera vez.")
        }
    }

    // MARK: - Station modules

    private var stationSection: some View {
        Section {
            settingRow("Device ID (interior)", binding: $cfg.deviceId)
            settingRow("Module Exterior",       binding: $cfg.moduleExterior)
            settingRow("Module Lluvia",          binding: $cfg.moduleRain)
            settingRow("Descripción ubicación",  binding: $cfg.stationLocation)
        } header: {
            Text("Estación principal")
        } footer: {
            Text("Los IDs tienen formato 70:ee:50:xx:xx:xx. Se ven en la app Netatmo o en getstationsdata.")
        }
    }

    // MARK: - Wind public station

    private var windSection: some View {
        Section {
            settingRow("Station ID (viento)", binding: $cfg.windStationId)
            settingRow("Ubicación (texto)",    binding: $cfg.windStationLoc)
            settingRow("BBox NE Lat",          binding: $cfg.windBboxNELat)
            settingRow("BBox NE Lon",          binding: $cfg.windBboxNELon)
            settingRow("BBox SW Lat",          binding: $cfg.windBboxSWLat)
            settingRow("BBox SW Lon",          binding: $cfg.windBboxSWLon)
        } header: {
            Text("Estación pública (viento) — Opcional")
        } footer: {
            Text("Caja de coordenadas del área donde buscar la estación pública con anemómetro.")
        }
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Favoritas").font(.caption).foregroundStyle(.secondary)
                TextField("Madrid:Madrid,Llanes:Naves", text: $cfg.favoriteNames, axis: .vertical)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .lineLimit(3, reservesSpace: true)
            }
        } header: {
            Text("Estaciones favoritas")
        } footer: {
            Text("Formato: ciudad:Nombre,ciudad2:Nombre2\nLa ciudad debe coincidir con el campo city de Netatmo (sin acentos).")
        }
    }

    // MARK: - AEMET

    private var aemetSection: some View {
        Section {
            LabeledContent("API Key") {
                SecureField("", text: $cfg.aemetApiKey)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("AEMET OpenData")
        } footer: {
            Text("Solicita clave gratuita en opendata.aemet.es → Obtención de API Key.")
        }
    }

    // MARK: - Help

    private var helpSection: some View {
        Section("Información") {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppConfiguration.shared.isNetatmoConfigured ? .green : .gray)
                Text("Netatmo configurado")
                Spacer()
                Text(AppConfiguration.shared.isNetatmoConfigured ? "✓" : "Pendiente")
                    .foregroundStyle(.secondary).font(.caption)
            }
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppConfiguration.shared.isAemetConfigured ? .green : .gray)
                Text("AEMET configurado")
                Spacer()
                Text(AppConfiguration.shared.isAemetConfigured ? "✓" : "Pendiente")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    // MARK: - Helper

    private func settingRow(_ label: String, binding: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("", text: binding)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}

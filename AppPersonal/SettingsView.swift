import SwiftUI

struct SettingsView: View {
    @ObservedObject private var cfg = AppConfiguration.shared

    var body: some View {
        NavigationStack {
            Form {
                refreshSection
                aemetSection
                netatmoSection
                stationSection
                helpSection
                creditsSection
            }
            .navigationTitle("Ajustes")
        }
    }

    // MARK: - Refresh cadence

    private var refreshSection: some View {
        Section {
            Picker("Actualización", selection: refreshBinding) {
                ForEach(RefreshInterval.pickerCases) { interval in
                    Text(interval.pickerLabel).tag(interval.rawValue)
                }
            }
        } header: {
            Text("Actualización en segundo plano")
        } footer: {
            Text("«Frecuente» refresca más a menudo; «Ahorro» gasta menos batería. iOS decide el momento exacto de las actualizaciones en segundo plano.")
        }
    }

    /// Maps the stored cadence onto the simplified pair so the picker always shows a
    /// selection, and writes the chosen value back (gently migrating older values).
    private var refreshBinding: Binding<Int> {
        Binding(get: { cfg.refreshInterval.simplified.rawValue },
                set: { cfg.refreshIntervalHours = $0 })
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
            if cfg.deviceId.isEmpty {
                Label(cfg.isDetectingStation ? "Detectando estación…" : "Sin estación detectada",
                      systemImage: cfg.isDetectingStation ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                // Picker only appears when the account exposes more than one station.
                if cfg.availableStations.count > 1 {
                    Picker("Estación", selection: stationSelection) {
                        ForEach(cfg.availableStations) { station in
                            Text(station.name).tag(station.id)
                        }
                    }
                } else {
                    LabeledContent("Estación", value: cfg.stationLocation)
                }
                moduleStatus("Módulo exterior", present: !cfg.moduleExterior.isEmpty)
                moduleStatus("Módulo lluvia",   present: !cfg.moduleRain.isEmpty)
            }
            Button {
                Task { await cfg.autoDetectStation() }
            } label: {
                Label("Detectar de nuevo", systemImage: "arrow.clockwise")
            }
            .disabled(cfg.isDetectingStation || !cfg.hasNetatmoCredentials)
        } header: {
            Text("Estación principal")
        } footer: {
            Text("Los módulos se detectan automáticamente desde tu cuenta Netatmo. No hace falta introducirlos a mano.")
        }
    }

    /// Drives the station Picker: reads the active device id, applies the picked one.
    private var stationSelection: Binding<String> {
        Binding(
            get: { cfg.deviceId },
            set: { id in
                if let station = cfg.availableStations.first(where: { $0.id == id }) {
                    cfg.applyStation(station)
                }
            }
        )
    }

    private func moduleStatus(_ label: String, present: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: present ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(present ? .green : .gray)
        }
        // Status is conveyed only by icon + colour otherwise.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(present ? "detectado" : "no detectado")
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

    // MARK: - Credits

    /// GeoNames ships under CC BY 4.0, which asks for credit wherever its data is used —
    /// here, every village name the app puts under your GPS fix.
    private var creditsSection: some View {
        Section {
            Text("Los nombres de pueblos y aldeas proceden de GeoNames, bajo licencia CC BY 4.0.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Datos")
        }
    }
}

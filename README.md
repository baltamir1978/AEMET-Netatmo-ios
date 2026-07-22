# Tiempo España — meteorología, sol/luna y mareas

App de iOS personal que reúne en un solo lugar la predicción y los avisos de **AEMET**, los datos de tu **estación Netatmo**, información de **sol y luna**, **mareas**, **eventos astronómicos**, gráficas históricas y una familia de **widgets** para la pantalla de inicio.

> Repositorio: `github.com/baltamir1978/AEMET-Netatmo-ios`

## Características

### Tiempo (AEMET)

- 🌦️ **Predicción oficial de AEMET**: por horas y por días desde la API OpenData (`AEMETService`), con temperatura actual observada de la estación más cercana.
- ⚠️ **Avisos meteorológicos** en formato CAP por comunidad autónoma (`AEMETAlertsService`).
- 📍 **Ubicación actual o ciudades seguidas**: busca municipios y guarda los que uses a diario (`LocationStore`, `LocationManagerSheet`, `CurrentLocationService`).
- 🗼 **Selector de estación**: AEMET asigna la más cercana, pero puedes fijar otra por municipio cuando la de al lado no es la de tu valle (`StationPickerSheet`).
- 🌍 **Sin API key de AEMET también funciona**: la pestaña se sirve completa desde **Open-Meteo** (`OpenMeteoService`), sin cambiar la interfaz.

### Sol·Luna

- ☀️🌙 Orto y ocaso, crepúsculos, fase lunar y calendario mensual (`SunMoonService`, `MoonPhasesService`).
- 🌌 Eventos astronómicos y solsticios/equinoccios con sus extremos de amanecer y atardecer (`AstroEventsService`, `CosmosView`).
- 🌊 **Mareas** del IHM con caché en disco (`TidesService`).

### Netatmo (opcional)

- 🌡️ **Datos en tiempo real** de tu estación y módulos: temperatura, humedad, presión, lluvia y viento (`NetatmoService`, OAuth2).
- 📈 **Gráficas** históricas de las medidas (`GraficasView`).

Las pestañas *Actual* y *Gráficas* solo aparecen si hay credenciales de Netatmo configuradas.

### Widgets

Cuatro widgets en tamaños pequeño, mediano y grande (`AppPersonalWidget`):

| Widget | Qué muestra |
|---|---|
| **Tiempo** | Temperatura actual, predicción y avisos, con fondo coloreado según la temperatura |
| **Sol·Luna** | Orto/ocaso y fase lunar |
| **Mareas** | Nivel del mar dibujado como playa (alta = azul, baja = arena) |
| **Netatmo** | Anillos de temperatura, humedad y presión de tu estación |

- Configurables desde el propio widget (ciudad, estilo) vía `WidgetConfigIntent`.
- **Deep links**: cada widget abre la sección correspondiente de la app.
- Se refrescan solos: descargan sus propios datos y comparten caché con la app a través del App Group `group.Altamirano.AppPersonal`.

### General

- 🔄 **Refresco en segundo plano** con `BGAppRefreshTask` e intervalo configurable (`BackgroundRefresher`).
- 🌗 **Modo claro y oscuro** con tintes adaptativos (`Theme.swift`, `WidgetTheme.swift`).
- 🗣️ **Localizada** en español (idioma base), inglés, gallego, euskera y catalán (`Localizable.xcstrings`).
- ♿️ Etiquetas de accesibilidad en las vistas principales.

## Requisitos

- Xcode 26 o superior
- iOS 26.5+
- API key de [AEMET OpenData](https://opendata.aemet.es/) *(opcional: sin ella se usa Open-Meteo)*
- Cuenta y app registrada en [Netatmo Connect](https://dev.netatmo.com/) *(opcional: solo para las pestañas Actual y Gráficas)*

## Configuración de credenciales (importante)

Las credenciales **no se versionan**. El repo incluye una plantilla:

```bash
# Copia la plantilla y rellena tus valores
cp Secrets.swift.example AppPersonal/Secrets.swift
```

`Secrets.swift` está en `.gitignore` (`**/Secrets.swift`) y nunca se sube. Rellena:

| Clave | Descripción |
|---|---|
| `aemetApiKey` | API key de AEMET OpenData |
| `netatmoClientId` / `netatmoClientSecret` | Credenciales de tu app en Netatmo Connect |
| `netatmoRefreshToken` | Refresh token OAuth2 de tu cuenta |
| `netatmoDeviceId` | MAC de la estación base (`70:ee:50:…`) |
| `netatmoModuleExt` | MAC del módulo exterior (`02:00:00:…`) |
| `netatmoModuleRain` | MAC del módulo de lluvia (`05:00:00:…`) |
| `netatmoWindId` | ID de estación pública de viento (opcional) |

También puedes introducir estos valores en tiempo de ejecución desde **Ajustes** (se guardan en `UserDefaults`).

## Estructura del proyecto

```
AppPersonal/
├── AppPersonal/                    # Target de la app
│   ├── AppPersonalApp.swift        # Punto de entrada + deep links
│   ├── ContentView.swift           # Navegación por pestañas
│   ├── AemetView.swift             # Predicción, avisos y estación
│   ├── CosmosView.swift            # Sol·Luna, mareas y eventos
│   ├── ActualView.swift            # Datos actuales de Netatmo
│   ├── GraficasView.swift          # Gráficas históricas
│   ├── SettingsView.swift          # Ajustes / credenciales
│   ├── LocationManagerSheet.swift  # Ciudades seguidas
│   ├── StationPickerSheet.swift    # Selector de estación AEMET
│   ├── AEMETService.swift / AEMETAlertsService.swift
│   ├── OpenMeteoService.swift / OpenMeteoForecast.swift
│   ├── NetatmoService.swift / NetatmoModels.swift / NetatmoSnapshotBuilder.swift
│   ├── SunMoonService.swift / MoonPhasesService.swift
│   ├── TidesService.swift / AstroEventsService.swift
│   ├── LocationStore.swift / CurrentLocationService.swift
│   ├── BackgroundRefresher.swift   # BGAppRefreshTask
│   ├── AppConfiguration.swift      # Configuración (UserDefaults)
│   ├── Theme.swift / Models.swift
│   ├── Localizable.xcstrings       # es · en · gl · eu · ca
│   └── Secrets.swift               # ⚠️ Local, NO versionado
├── AppPersonalWidget/              # Extensión de widgets
│   ├── WeatherWidget.swift / SunMoonWidget.swift
│   ├── TidesWidget.swift / NetatmoWidget.swift
│   ├── WidgetConfigIntent.swift / WidgetTheme.swift
│   └── Localizable.xcstrings
├── Shared/                         # Código compartido app ↔ widget
│   ├── AemetSnapshotBuilder.swift
│   └── WidgetShared.swift          # App Group y modelos de snapshot
├── Tools/generate_icon.py
├── Secrets.swift.example           # Plantilla de credenciales
└── AppPersonal.xcodeproj
```

## Puesta en marcha

1. Clona el repo y abre `AppPersonal.xcodeproj`.
2. Crea `Secrets.swift` a partir de la plantilla (ver arriba) **o** deja los valores vacíos e introdúcelos en Ajustes.
3. Selecciona tu *Team* de firma (app y extensión de widgets comparten el App Group).
4. Compila y ejecuta.

## Seguridad

- El `access_token` solo vive en memoria; el `refresh_token` se guarda en `UserDefaults` (aceptable para una app personal). Para producción se recomienda **Keychain**.
- `Secrets.swift` está excluido del control de versiones.

## Licencia

Proyecto personal de Bruno Altamirano. Datos meteorológicos cortesía de **AEMET**, **Open-Meteo**, **Netatmo** e **Instituto Hidrográfico de la Marina** (sujetos a sus respectivos términos de uso).

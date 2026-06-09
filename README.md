# AppPersonal — Estación meteorológica & astronomía

App de iOS personal que reúne en un solo lugar los datos de tu **estación Netatmo**, las predicciones de **AEMET**, información de **sol/luna**, **mareas**, **eventos astronómicos** y gráficas históricas.

> Repositorio: `github.com/baltamir1978/AEMET-Netatmo-ios`

## Características

- 🌡️ **Datos en tiempo real de Netatmo**: temperatura, humedad, presión, lluvia y viento desde tu estación y módulos (`NetatmoService`, OAuth2).
- 🌦️ **Predicción AEMET**: previsión oficial desde la API OpenData de AEMET (`AEMETService`).
- ☀️🌙 **Sol y Luna**: orto/ocaso, fase lunar, etc. (`SunMoonService`).
- 🌊 **Mareas** (`TidesService`).
- 🌌 **Eventos astronómicos** y vista del cosmos (`AstroEventsService`, `CosmosView`).
- 📈 **Gráficas** históricas de las medidas (`GraficasView`).
- ⚙️ **Ajustes** con credenciales y configuración de módulos/estaciones (`AppConfiguration`, `SettingsView`).

## Requisitos

- Xcode 15 o superior
- iOS 17.0+
- Cuenta y app registrada en [Netatmo Connect](https://dev.netatmo.com/) (Client ID/Secret + refresh token)
- API key de [AEMET OpenData](https://opendata.aemet.es/)

## Configuración de credenciales (importante)

Las credenciales **no se versionan**. El repo incluye una plantilla:

```bash
# Copia la plantilla y rellena tus valores
cp Secrets.swift.example AppPersonal/AppPersonal/Secrets.swift
```

`Secrets.swift` está en `.gitignore` (`**/Secrets.swift`) y nunca se sube. Rellena:

| Clave | Descripción |
|---|---|
| `netatmoClientId` / `netatmoClientSecret` | Credenciales de tu app en Netatmo Connect |
| `netatmoRefreshToken` | Refresh token OAuth2 de tu cuenta |
| `netatmoDeviceId` | MAC de la estación base (`70:ee:50:…`) |
| `netatmoModuleExt` | MAC del módulo exterior (`02:00:00:…`) |
| `netatmoModuleRain` | MAC del módulo de lluvia (`05:00:00:…`) |
| `netatmoWindId` | ID de estación pública de viento (opcional) |
| `aemetApiKey` | API key de AEMET OpenData |

También puedes introducir estos valores en tiempo de ejecución desde **Ajustes** (se guardan en `UserDefaults`).

## Estructura del proyecto

```
AppPersonal/
├── AppPersonal/
│   ├── AppPersonalApp.swift     # Punto de entrada
│   ├── ContentView.swift        # Navegación principal
│   ├── ActualView.swift         # Datos actuales
│   ├── AemetView.swift          # Predicción AEMET
│   ├── GraficasView.swift       # Gráficas históricas
│   ├── CosmosView.swift         # Vista astronómica
│   ├── SettingsView.swift       # Ajustes / credenciales
│   ├── AppConfiguration.swift   # Configuración (UserDefaults)
│   ├── NetatmoService.swift / NetatmoModels.swift
│   ├── AEMETService.swift
│   ├── SunMoonService.swift / TidesService.swift / AstroEventsService.swift
│   ├── Models.swift
│   └── Secrets.swift            # ⚠️ Local, NO versionado
├── Secrets.swift.example        # Plantilla de credenciales
└── AppPersonal.xcodeproj
```

## Puesta en marcha

1. Clona el repo y abre `AppPersonal.xcodeproj`.
2. Crea `Secrets.swift` a partir de la plantilla (ver arriba) **o** deja los valores vacíos e introdúcelos en Ajustes.
3. Selecciona tu *Team* de firma.
4. Compila y ejecuta.

## Seguridad

- El `access_token` solo vive en memoria; el `refresh_token` se guarda en `UserDefaults` (aceptable para una app personal). Para producción se recomienda **Keychain**.
- `Secrets.swift` está excluido del control de versiones.

## Licencia

Proyecto personal de Bruno Altamirano. Datos meteorológicos cortesía de **AEMET** y **Netatmo** (sujetos a sus respectivos términos de uso).

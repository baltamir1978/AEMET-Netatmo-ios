# Tiempo ES

App personal de iOS con el tiempo de **AEMET** (y del **IPMA** en Portugal), la **estación Netatmo** de casa, **sol y luna**, **mareas**, **eventos astronómicos** y cuatro **widgets** para la pantalla de inicio.

> Repositorio: `github.com/baltamir1978/AEMET-Netatmo-ios` · En la pantalla de inicio se llama **Tiempo ES**: «Tiempo España» no cabe en una línea.

## Qué hace

### Tiempo

- 🌦️ **Predicción oficial de AEMET** por horas y por días (API OpenData, `AEMETService`), con la temperatura observada en la estación más cercana y los **avisos** en formato CAP de la comunidad autónoma (`AEMETAlertsService`).
- 🌍 **Sin clave de AEMET también funciona**: la pestaña se sirve entera desde **Open-Meteo** (`OpenMeteoService`) con la misma interfaz.
- 🇵🇹 **Portugal con el IPMA** (`IPMAService`), sin clave: previsión, observaciones y avisos oficiales. El IPMA solo publica 35 localidades, así que allí el selector de estación pasa a ser un **selector de fuente**: la capital del IPMA más próxima (con su distancia) u Open-Meteo en tu coordenada exacta. A más de 25 km de cualquiera de esas 35, Open-Meteo va por defecto.
- 👆 **Una página por ubicación**: la ubicación GPS y las ciudades que sigas, pasando de una a otra con el dedo (`AemetView`, `AemetCityView`). Cada página tiene su propia previsión y caché en disco (`CityWeather`): una ciudad ya visitada aparece al instante y nunca se ve el tiempo de la anterior bajo el nombre de la nueva. Las páginas vecinas se preparan por adelantado.
- 🗼 **Estación a elegir**: AEMET asigna la más cercana, pero se puede fijar otra por municipio cuando la de al lado no es la de tu valle (`StationPickerSheet`).

### Sol·Luna y mareas

- ☀️🌙 Orto y ocaso, crepúsculos, fase lunar y calendario del mes (`SunMoonService`, `MoonPhasesService`); eventos astronómicos, solsticios y equinoccios (`AstroEventsService`, `CosmosView`).
- 🕐 **Cada sitio en su hora**: la zona horaria sale del territorio. Canarias va con `Atlantic/Canary`, y Madeira y Azores con la suya; en Tenerife el ocaso ya no se anuncia una hora tarde. Vale para la app y para el widget.
- 🌊 **Mareas del IHM** (`TidesService`), con caché en disco y los puertos ordenados por cercanía.
  - El IHM publica sus tablas **en UTC** sin decirlo, y su parámetro `date` elige un día UTC. Cada hora se pasa a la del puerto y las mareas se reagrupan por día local, pidiendo las dos o tres tablas UTC que solapan ese día. Sin esto, en verano peninsular la pleamar salía dos horas antes.
  - De Portugal el IHM solo sirve Lisboa, que queda estuario arriba y da medio metro de más. Como la costa atlántica ibérica rompe con menos de tres cuartos de hora de diferencia, el puerto más próximo (A Guarda al norte, Ayamonte al sur) es mejor referencia.

### Netatmo (opcional)

- 🌡️ Temperatura, humedad, presión, lluvia y viento de tu estación en tiempo real (`NetatmoService`, OAuth2), y **gráficas** históricas (`GraficasView`).
- Las pestañas *Actual* y *Gráficas* solo aparecen si hay credenciales de Netatmo.

### Buscar y ubicar

- 📍 **El pueblo, no el municipio** (`Nomenclator.swift`): el geocodificador de Apple no pasa del municipio, y en todo el concejo de Llanes devuelve «Llanes». La app lleva dentro un nomenclátor de unos 29.000 núcleos (`Nucleos.tsv`, generado con `Tools/build_nomenclator.py`) y elige el más cercano dentro del municipio que ya resolvió AEMET. En las ciudades grandes manda MapKit, que conoce los barrios (Chamberí, Gràcia, Triana).
- 🔎 **Buscador instantáneo** (`LocationSearch.swift`): índice en memoria con los municipios de AEMET, las localidades del IPMA y los pueblos del nomenclátor. Responde desde la primera letra y sin red, así que «Niembro» se encuentra igual que «Llanes». Ordena primero lo que empieza por lo escrito, el municipio antes que sus pueblos y el más poblado entre homónimos.

## Widgets

| Widget | Tamaños | Qué muestra |
|---|---|---|
| **Tiempo** | pequeño, mediano, grande | Temperatura actual, cielo, máxima y mínima, previsión por horas y días, avisos |
| **Netatmo** | pequeño, mediano, grande | Anillos de temperatura, humedad y presión de tu estación |
| **Sol·Luna** | pequeño, mediano | Orto, ocaso y fase lunar |
| **Mareas** | pequeño, mediano | El nivel del mar dibujado como una playa |

- Cada widget se configura desde «Editar widget» (ciudad y fondo, `WidgetConfigIntent`) y al tocarlo abre su sección de la app.
- Se refrescan solos: descargan sus datos y comparten caché con la app por el App Group `group.Altamirano.AppPersonal`. La app guarda una instantánea por ciudad, así que un widget fijado a cualquier ubicación tiene datos aunque no la abras.
- Los avisos a WidgetKit van agrupados (`LocationStore.nudgeWidgets`). WidgetKit tiene un cupo diario de recargas: avisar en cada página que pasas lo agotaba, y a partir de ahí los widgets se quedaban congelados.

### Color según la temperatura

Los widgets **Tiempo** y **Netatmo** pueden llevar el verde de la app o un fondo que cambia con la temperatura. La escala de colores se elige en **Ajustes → Widgets**, entre seis:

| Escala | Cómo es |
|---|---|
| **Pocas bandas** *(por defecto)* | Siete tramos anchos: ≤0, 1–9, 10–17, 18–25, 26–31, 32–37 y ≥38° |
| **Mapa clásico** | Morado y azules, cian y verdes; verde claro a 20–24°, amarillo desde 25°, hasta granate |
| **Blanco en el medio** | Casi blanca a 20–24°, más azul cuanto más frío y más roja cuanto más calor |
| **Tierra** | Pizarra, salvia, arena, ocre, terracota y siena |
| **Neón** | Colores muy saturados, de índigo eléctrico a rojo vivo |
| **Nocturna** | Todos los tramos oscuros; el texto siempre en blanco |

- Todas funcionan como la leyenda de un mapa: **un color fijo por tramo** (de 5° salvo en Pocas bandas) y cambio de golpe al pasar de tramo. No hay mezclas entre colores, que eran las que dejaban tonos sucios como un oliva mostaza a 21–24°.
- El tramo sale de la temperatura **redondeada**, la misma que enseña el widget.
- El fondo baja al mismo tono algo más oscuro, calculado en OKLab en lugar de mezclar con negro.
- El texto se pone en blanco o en azul marino según cuál contraste más con el peor extremo del fondo (`WidgetInk`). En las pantallas de inicio tintadas no hay fondo y el texto sigue en blanco.
- Los colores están en `TempScale` (`Shared/WidgetShared.swift`) y el cálculo del widget en `TempPalette` (`WidgetTheme.swift`).

## Otras cosas

- 🔄 Refresco en segundo plano con `BGAppRefreshTask`, frecuente (1 h) o de ahorro (6 h), desde Ajustes (`BackgroundRefresher`).
- 🌗 Modo claro y oscuro (`Theme.swift`, `WidgetTheme.swift`).
- 🗣️ En español (idioma base), inglés, gallego, euskera y catalán (`Localizable.xcstrings`).
- ♿️ Etiquetas de accesibilidad en las vistas principales.

## Requisitos

- Xcode 26 o posterior; el proyecto está en **Swift 6** y se compila con Xcode 27.
- iOS 26.5 o posterior.
- Clave de [AEMET OpenData](https://opendata.aemet.es/) *(opcional: sin ella se usa Open-Meteo)*.
- App registrada en [Netatmo Connect](https://dev.netatmo.com/) *(opcional: solo para Actual y Gráficas)*.

## Puesta en marcha

1. Clona el repo y abre `AppPersonal.xcodeproj`.
2. Copia la plantilla de credenciales y rellénala, o déjala vacía y mete los valores en Ajustes:

   ```bash
   cp Secrets.swift.example AppPersonal/Secrets.swift
   ```

3. Elige tu *Team* de firma. La app y la extensión de widgets comparten el App Group.
4. Compila y ejecuta.

`Secrets.swift` está en `.gitignore` (`**/Secrets.swift`) y nunca se sube. Lleva:

| Clave | Qué es |
|---|---|
| `aemetApiKey` | Clave de AEMET OpenData |
| `netatmoClientId` / `netatmoClientSecret` | Credenciales de tu app en Netatmo Connect |
| `netatmoRefreshToken` | *Refresh token* OAuth2 de tu cuenta |
| `netatmoDeviceId` | MAC de la estación base (`70:ee:50:…`) |
| `netatmoModuleExt` | MAC del módulo exterior (`02:00:00:…`) |
| `netatmoModuleRain` | MAC del módulo de lluvia (`05:00:00:…`) |
| `netatmoWindId` | Estación pública de viento (opcional) |

Los módulos de Netatmo también se detectan solos desde Ajustes → Estación principal.

> **Un aviso de compilación, a propósito.** Queda un único *warning*: `MKMapItem.placemark`, obsoleto desde iOS 26. Su sustituto, `MKAddressRepresentations`, sigue sin dar la sublocalidad ni el país ISO en el SDK de iOS 27, y la otra vía (`CLGeocoder`) también está obsoleta. De esos dos datos dependen mostrar «Chamberí» en vez de «Madrid» y decidir si un punto lo sirve AEMET o el IPMA. Está encerrado en `LocationStore.legacyFields(of:)`, la única línea que lo usa.

## Estructura

```
AppPersonal/
├── AppPersonal/                    # La app
│   ├── AppPersonalApp.swift        # Entrada y deep links
│   ├── ContentView.swift           # Pestañas
│   ├── AemetView.swift             # Tiempo: páginas por ubicación
│   ├── AemetCityView.swift         # Predicción, avisos y estación de una ubicación
│   ├── CityWeather.swift           # Datos de una ubicación, con caché
│   ├── CosmosView.swift            # Sol·Luna, mareas y eventos
│   ├── ActualView.swift            # Netatmo en tiempo real
│   ├── GraficasView.swift          # Gráficas históricas
│   ├── SettingsView.swift          # Ajustes, credenciales y colores de los widgets
│   ├── LocationManagerSheet.swift  # Ciudades seguidas
│   ├── StationPickerSheet.swift    # Estación AEMET o fuente en Portugal
│   ├── AEMETService.swift / AEMETAlertsService.swift
│   ├── IPMAService.swift
│   ├── OpenMeteoService.swift / OpenMeteoForecast.swift
│   ├── NetatmoService.swift / NetatmoModels.swift / NetatmoSnapshotBuilder.swift
│   ├── SunMoonService.swift / MoonPhasesService.swift
│   ├── TidesService.swift / AstroEventsService.swift
│   ├── LocationStore.swift / CurrentLocationService.swift
│   ├── Nomenclator.swift / Nucleos.tsv   # Pueblos y aldeas (GeoNames)
│   ├── LocationSearch.swift        # Índice del buscador
│   ├── BackgroundRefresher.swift   # BGAppRefreshTask
│   ├── AppConfiguration.swift      # Configuración (UserDefaults)
│   ├── Theme.swift / Models.swift
│   ├── Localizable.xcstrings
│   └── Secrets.swift               # Local, no se versiona
├── AppPersonalWidget/              # Extensión de widgets
│   ├── WeatherWidget.swift / NetatmoWidget.swift
│   ├── SunMoonWidget.swift / TidesWidget.swift
│   ├── WidgetConfigIntent.swift    # Ciudad y fondo de cada widget
│   ├── WidgetTheme.swift           # Colores, TempPalette y WidgetInk
│   └── Localizable.xcstrings
├── Shared/                         # Compartido app ↔ widget
│   ├── WidgetShared.swift          # App Group, instantáneas y TempScale
│   └── AemetSnapshotBuilder.swift
├── Tools/
│   ├── build_nomenclator.py        # Regenera Nucleos.tsv desde GeoNames
│   └── generate_icon.py
├── Secrets.swift.example
└── AppPersonal.xcodeproj
```

## Seguridad

- El `access_token` de Netatmo solo vive en memoria; el `refresh_token` va en `UserDefaults`, aceptable para una app personal. Para publicarla convendría el Keychain.
- `Secrets.swift` no se versiona.

## Créditos y licencia

Proyecto personal de Bruno Altamirano. Datos de **AEMET**, **IPMA**, **Open-Meteo**, **Netatmo** y el **Instituto Hidrográfico de la Marina**, cada uno con sus términos de uso.

Los nombres de pueblos y aldeas son de [**GeoNames**](https://www.geonames.org/), bajo [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); la atribución está también en Ajustes → Datos. Para regenerar el fichero:

```bash
python3 Tools/build_nomenclator.py
```

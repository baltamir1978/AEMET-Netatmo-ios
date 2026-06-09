# Revisión de código — AppPersonal

Revisión del estado del proyecto y recomendaciones.

## Resumen

App personal que integra varias fuentes de datos (Netatmo, AEMET, sol/luna, mareas, astronomía) con una capa de servicios por cada API y configuración centralizada en `AppConfiguration`. Buen manejo de secretos: las credenciales viven fuera del repo.

## Estado de Git

- Rama: `main` → `origin` (`github.com/baltamir1978/AEMET-Netatmo-ios.git`).
- 2 commits.
- Cambios **en *staging*** sin commitear: `NetatmoModels.swift`, `SunMoonService.swift`. Confirmar y hacer commit.

## Puntos fuertes

- ✅ **Gestión de secretos correcta**: `Secrets.swift` está en `.gitignore` y solo se versiona `Secrets.swift.example`. Verificado: el secreto real **no** está en el repo.
- ✅ Un servicio por API, modelos separados (`Models`, `NetatmoModels`).
- ✅ Configuración por `UserDefaults` con `AppConfiguration` como única fuente de verdad, y *flags* derivados (`isNetatmoConfigured`, `isAemetConfigured`, `windEnabled`).
- ✅ Comentarios honestos sobre límites (token en memoria vs. Keychain).

## Hallazgos / recomendaciones

### ⚠️ 1. Archivos de usuario de Xcode versionados
`AppPersonal.xcodeproj/xcuserdata/.../xcschememanagement.plist` está trackeado pese a que `.gitignore` ya excluye `xcuserdata/`. Al haberse añadido antes de la regla, sigue en el índice. Limpieza:

```bash
git rm -r --cached AppPersonal.xcodeproj/xcuserdata
git commit -m "Remove Xcode user data from version control"
```

(El `.gitignore` ya cubre `*.xcuserstate` y `xcuserdata/` para el futuro.)

### 2. Seguridad de tokens
- El `refresh_token` se guarda en `UserDefaults`. Para una app personal es aceptable, pero si algún día se distribuye conviene moverlo al **Keychain**. Ya está anotado en el código.

### 3. Robustez
- Añadir manejo de errores de red y de expiración del token AEMET (las URLs de AEMET caducan; verificar reintento/refresh).
- Considerar caché local de la última lectura para mostrar datos aunque falle la red.

### 4. Calidad
- Tests unitarios para el parseo de respuestas (Netatmo/AEMET) y para `AppConfiguration.windBbox` / `favoriteCityNames` (parseo de cadenas) serían baratos y valiosos.

## Checklist previo a release

- [ ] Commit de los cambios en *staging*.
- [ ] `git rm --cached` de `xcuserdata`.
- [ ] Verificar que el repo no contiene ningún token real (revisar histórico si hubo dudas).
- [ ] Probar el flujo OAuth de Netatmo desde cero (refresh token caducado).
- [ ] Revisar textos de permisos si se usa ubicación.

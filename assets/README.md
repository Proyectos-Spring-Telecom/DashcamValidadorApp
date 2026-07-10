# Guía de Assets - Transmovi

Este documento explica dónde colocar las diferentes imágenes del proyecto.

## 📁 Estructura de Carpetas

### 1. **Logo de la App** (usado en la interfaz)
**Ubicación:** `assets/images/logo.png`

- Formato recomendado: PNG con fondo transparente
- Tamaño recomendado: 512x512 píxeles (para buena calidad en diferentes tamaños)
- Se usa en: SplashScreen, Drawer, AppBar, etc.

**Uso en el código:**
```dart
Image.asset('assets/images/logo.png')
```

---

### 2. **Iconos** (usados en la interfaz)
**Ubicación:** `assets/icons/`

- Coloca aquí cualquier icono personalizado que uses en la app
- Formato recomendado: PNG o SVG (si usas un paquete para SVG)
- Ejemplo: `assets/icons/bus_icon.png`, `assets/icons/user_icon.png`

**Uso en el código:**
```dart
Image.asset('assets/icons/bus_icon.png')
```

---

### 3. **Icono de la App** (Android)
**Ubicación:** `android/app/src/main/res/mipmap-*/`

Para Android, necesitas crear iconos en diferentes resoluciones:

- **mipmap-mdpi/** - 48x48 px (`ic_launcher.png`)
- **mipmap-hdpi/** - 72x72 px (`ic_launcher.png`)
- **mipmap-xhdpi/** - 96x96 px (`ic_launcher.png`)
- **mipmap-xxhdpi/** - 144x144 px (`ic_launcher.png`)
- **mipmap-xxxhdpi/** - 192x192 px (`ic_launcher.png`)

**Recomendación:** Usa el paquete `flutter_launcher_icons` para generar automáticamente todos los tamaños desde una sola imagen.

---

### 4. **Icono de la App** (iOS)
**Ubicación:** `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

Para iOS, necesitas crear iconos en diferentes tamaños. La estructura ya está creada, solo reemplaza los archivos PNG.

**Recomendación:** Usa el paquete `flutter_launcher_icons` para generar automáticamente todos los tamaños desde una sola imagen.

---

### 5. **Splash Screen** (Android)
**Ubicación:** `android/app/src/main/res/drawable/` y `drawable-v21/`

Los archivos de splash ya están configurados:
- `drawable/launch_background.xml` - Splash para versiones anteriores a Android 5.0
- `drawable-v21/launch_background.xml` - Splash para Android 5.0+

**Para personalizar el splash:**
1. Edita los archivos XML para cambiar colores o agregar imágenes
2. Si quieres usar una imagen de splash, agrégala a `drawable/` y referencia en el XML

**Recomendación:** Usa el paquete `flutter_native_splash` para generar automáticamente el splash desde una imagen.

---

### 6. **Splash Screen** (iOS)
**Ubicación:** `ios/Runner/Assets.xcassets/LaunchImage.imageset/`

Para iOS, los archivos de splash están en:
- `LaunchImage.png` - 320x480 px (iPhone 3G/3GS)
- `LaunchImage@2x.png` - 640x960 px (iPhone 4/4S)
- `LaunchImage@3x.png` - 1242x2208 px (iPhone 6 Plus)

**Recomendación:** Usa el paquete `flutter_native_splash` para generar automáticamente el splash desde una imagen.

---

## 🛠️ Herramientas Recomendadas

### 1. **flutter_launcher_icons**
Genera automáticamente los iconos de la app para todas las plataformas.

**Instalación:**
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1
```

**Configuración en `pubspec.yaml`:**
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/images/app_icon.png"  # Imagen fuente (1024x1024 px)
```

**Ejecutar:**
```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

### 2. **flutter_native_splash**
Genera automáticamente el splash screen para todas las plataformas.

**Instalación:**
```yaml
dev_dependencies:
  flutter_native_splash: ^2.3.10
```

**Configuración en `pubspec.yaml`:**
```yaml
flutter_native_splash:
  color: "#155EEF"  # Color de fondo
  image: "assets/images/splash_logo.png"  # Logo del splash (opcional)
  android: true
  ios: true
```

**Ejecutar:**
```bash
flutter pub get
flutter pub run flutter_native_splash:create
```

---

## 📝 Resumen Rápido

| Tipo de Imagen | Ubicación | Uso |
|----------------|-----------|-----|
| **Logo de la app** | `assets/images/logo.png` | Interfaz de usuario |
| **Iconos personalizados** | `assets/icons/` | Interfaz de usuario |
| **Icono de la app (Android)** | `android/app/src/main/res/mipmap-*/` | Icono del launcher |
| **Icono de la app (iOS)** | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | Icono del launcher |
| **Splash (Android)** | `android/app/src/main/res/drawable*/` | Pantalla de inicio |
| **Splash (iOS)** | `ios/Runner/Assets.xcassets/LaunchImage.imageset/` | Pantalla de inicio |

---

## ✅ Checklist

- [ ] Crear `assets/images/logo.png` (logo de la app)
- [ ] Crear `assets/icons/` (iconos personalizados si los hay)
- [ ] Crear icono de la app para Android (o usar `flutter_launcher_icons`)
- [ ] Crear icono de la app para iOS (o usar `flutter_launcher_icons`)
- [ ] Personalizar splash screen para Android (o usar `flutter_native_splash`)
- [ ] Personalizar splash screen para iOS (o usar `flutter_native_splash`)
- [ ] Ejecutar `flutter pub get` después de agregar assets
- [ ] Verificar que las imágenes se carguen correctamente en la app

---

## 🔍 Notas Importantes

1. **Después de agregar assets**, ejecuta:
   ```bash
   flutter pub get
   ```

2. **Para usar assets en el código**, siempre usa rutas relativas desde `assets/`:
   ```dart
   Image.asset('assets/images/logo.png')
   ```

3. **Los assets deben estar declarados en `pubspec.yaml`** para que Flutter los incluya en la compilación.

4. **Los iconos de la app y splash screens** requieren configuración específica por plataforma, por lo que es recomendable usar los paquetes mencionados arriba.


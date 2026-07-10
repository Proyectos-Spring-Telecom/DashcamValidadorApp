# Iconos de la Aplicación

## 📍 Dónde colocar el icono

Coloca tu icono principal aquí con el nombre: **`app_icon.png`**

## 📐 Especificaciones del icono

- **Formato**: PNG (recomendado) o JPG
- **Tamaño recomendado**: **1024x1024 píxeles** (mínimo 512x512)
- **Fondo**: Preferiblemente transparente o con fondo sólido
- **Forma**: Cuadrado (se redondeará automáticamente en Android/iOS)

## 🚀 Cómo generar los iconos

Una vez que coloques el archivo `app_icon.png` en esta carpeta:

1. Instala las dependencias:
   ```bash
   flutter pub get
   ```

2. Genera los iconos para todas las plataformas:
   ```bash
   flutter pub run flutter_launcher_icons
   ```

Esto generará automáticamente todos los iconos necesarios para:
- ✅ Android (todas las densidades)
- ✅ iOS (todos los tamaños)
- ✅ Web (favicon y manifest)
- ✅ Windows (.ico)
- ✅ macOS (.icns)
- ✅ Linux (.png)

## 📝 Nota

El icono se actualizará automáticamente en todas las plataformas cuando ejecutes el comando de generación.


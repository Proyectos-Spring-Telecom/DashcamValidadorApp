# Solución para Problemas del Emulador Android

## Problema
El emulador `Telefono_Flutter` falla al iniciar con error relacionado con Vulkan/graphics.

## Soluciones Aplicadas

### 1. Cambiar Backend de Gráficos a SwiftShader

Se modificó la configuración del emulador para usar SwiftShader en lugar de Vulkan:

**Archivo modificado:** `C:\Users\fammo\.android\avd\Telefono_Flutter.avd\config.ini`

**Cambios:**
- `hw.gpu.enabled = yes`
- `hw.gpu.mode = swiftshader_indirect`

### 2. Lanzar Emulador con Parámetros Específicos

```powershell
$env:ANDROID_HOME = "C:\Users\fammo\AppData\Local\Android\sdk"
& "$env:ANDROID_HOME\emulator\emulator.exe" -avd Telefono_Flutter -gpu swiftshader_indirect
```

## Emuladores Disponibles

Actualmente tienes 3 emuladores:

1. **Medium_Phone_API_36.1** - Teléfono genérico (funciona)
2. **Pixel7** - Google Pixel 7 (funciona) ✅
3. **Telefono_Flutter** - Nuevo emulador (requiere ajustes)

## Usar Emuladores que Funcionan

### Lanzar Pixel7:
```bash
flutter emulators --launch Pixel7
```

### Lanzar Medium Phone:
```bash
flutter emulators --launch Medium_Phone_API_36.1
```

### Ejecutar la App en el Emulador:
```bash
flutter run
```

## Soluciones Alternativas

### Opción 1: Recrear el Emulador con Configuración Correcta

```powershell
# Eliminar el emulador problemático
$env:ANDROID_HOME = "C:\Users\fammo\AppData\Local\Android\sdk"
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\avdmanager.bat" delete avd -n Telefono_Flutter

# Crear nuevo con configuración explícita
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\avdmanager.bat" create avd -n Telefono_Flutter_Nuevo -k "system-images;android-36.1;google_apis_playstore;x86_64" -d "pixel_7"

# Editar config.ini antes de lanzar
# hw.gpu.enabled = yes
# hw.gpu.mode = swiftshader_indirect
```

### Opción 2: Usar Emulador Existente

El emulador **Pixel7** ya está configurado y funcionando. Es la opción más rápida.

### Opción 3: Verificar Aceleración de Hardware

```powershell
$env:ANDROID_HOME = "C:\Users\fammo\AppData\Local\Android\sdk"
& "$env:ANDROID_HOME\emulator\emulator.exe" -accel-check
```

## Comandos Útiles

**Ver emuladores:**
```bash
flutter emulators
```

**Ver dispositivos conectados:**
```bash
flutter devices
```

**Lanzar emulador específico:**
```bash
flutter emulators --launch Pixel7
```

**Ejecutar app en emulador:**
```bash
flutter run
```

## Nota

El emulador **Pixel7** está funcionando correctamente y es recomendable usarlo para desarrollo. El emulador `Telefono_Flutter` puede requerir más ajustes de configuración.

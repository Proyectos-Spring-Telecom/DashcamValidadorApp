# Solución para el Error de Symlink en Windows

## Problema
Flutter no puede crear symlinks entre diferentes unidades (C:, D:, B:) sin permisos especiales en Windows.

## Solución Recomendada: Habilitar Modo de Desarrollador

Esta es la solución más fácil y permanente:

### Pasos:
1. Presiona `Win + I` para abrir Configuración de Windows
2. Ve a: **Privacidad y seguridad** → **Para desarrolladores**
3. Activa el interruptor **"Modo de desarrollador"**
4. Acepta el aviso de seguridad si aparece
5. Cierra y vuelve a abrir PowerShell
6. Ejecuta: `flutter pub get`

### Ventajas:
- ✅ No requiere permisos de administrador
- ✅ Permite crear symlinks sin restricciones
- ✅ Solución permanente para todos tus proyectos

---

## Solución Alternativa: Ejecutar como Administrador

Si no puedes habilitar el Modo de Desarrollador:

1. Cierra PowerShell actual
2. Click derecho en **PowerShell** → **Ejecutar como administrador**
3. Navega a tu proyecto:
   ```powershell
   cd D:\dashcamP18Q
   ```
4. Ejecuta el script:
   ```powershell
   .\fix_symlink.ps1
   ```
5. O ejecuta directamente:
   ```powershell
   flutter pub get
   ```

---

## Verificar si Funciona

Después de aplicar cualquiera de las soluciones:

```powershell
flutter pub get
```

Si no aparece el error del symlink, ¡está resuelto! ✅

---

## Nota Importante

Aunque aparezca el error del symlink, **la aplicación puede funcionar correctamente**. El symlink es principalmente para desarrollo y no afecta la ejecución de la app en la mayoría de los casos.

Para ejecutar la aplicación:
```powershell
flutter run -d windows
```

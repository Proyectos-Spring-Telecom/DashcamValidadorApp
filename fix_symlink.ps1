# Script para resolver el problema de symlinks en Windows
# Ejecutar como Administrador

Write-Host "=== Solucion para symlinks de Flutter ===" -ForegroundColor Cyan
Write-Host ""

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ADVERTENCIA: Este script requiere permisos de administrador." -ForegroundColor Yellow
    Write-Host "Por favor, ejecuta PowerShell como administrador." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "O bien, habilita el Modo de Desarrollador manualmente:" -ForegroundColor Yellow
    Write-Host "1. Abre Configuracion de Windows (Win + I)" -ForegroundColor White
    Write-Host "2. Ve a: Privacidad y seguridad > Para desarrolladores" -ForegroundColor White
    Write-Host "3. Activa 'Modo de desarrollador'" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "Ejecutando como administrador" -ForegroundColor Green
Write-Host ""

Write-Host "Intentando habilitar Modo de Desarrollador..." -ForegroundColor Cyan
$regPath = "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
$regValue = "AllowDevelopmentWithoutDevLicense"

try {
    $currentValue = Get-ItemProperty -Path "Registry::$regPath" -Name $regValue -ErrorAction SilentlyContinue
    if ($currentValue -and $currentValue.$regValue -eq 1) {
        Write-Host "Modo de Desarrollador ya esta habilitado" -ForegroundColor Green
    } else {
        Set-ItemProperty -Path "Registry::$regPath" -Name $regValue -Value 1 -Type DWord -Force
        Write-Host "Modo de Desarrollador habilitado correctamente" -ForegroundColor Green
    }
} catch {
    Write-Host "Error al habilitar Modo de Desarrollador: $_" -ForegroundColor Red
}

Write-Host ""

Write-Host "Intentando crear symlink manualmente..." -ForegroundColor Cyan

$sourcePath = "C:\Users\fammo\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_secure_storage_windows-3.1.2"
$targetPath = "D:\dashcamP18Q\windows\flutter\ephemeral\.plugin_symlinks\flutter_secure_storage_windows"

if (-not (Test-Path $sourcePath)) {
    Write-Host "No se encontro el directorio fuente: $sourcePath" -ForegroundColor Red
    Write-Host "Ejecuta 'flutter pub get' primero para descargar las dependencias" -ForegroundColor Yellow
    exit 1
}

$targetParent = Split-Path -Parent $targetPath
if (-not (Test-Path $targetParent)) {
    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    Write-Host "Directorio creado: $targetParent" -ForegroundColor Green
}

if (Test-Path $targetPath) {
    Remove-Item -Path $targetPath -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "Symlink anterior eliminado" -ForegroundColor Green
}

try {
    New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath -Force | Out-Null
    Write-Host "Symlink creado correctamente" -ForegroundColor Green
} catch {
    Write-Host "Error al crear symlink: $_" -ForegroundColor Red
    Write-Host "Asegurate de que el Modo de Desarrollador este habilitado" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Proceso completado ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora ejecuta: flutter pub get" -ForegroundColor Green

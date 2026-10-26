@echo off
echo ========================================================
echo A processar utilizador a partir do ficheiro de texto...
echo ========================================================
powershell -ExecutionPolicy Bypass -File "%~dp0processar_usuario.ps1"
@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0processar_email.ps1"
exit
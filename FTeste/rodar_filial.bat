@echo off
chcp 65001 >nul
echo A iniciar o processo de criacao de utilizador na Filial...
powershell -ExecutionPolicy Bypass -File "%~dp0processar_filial.ps1"
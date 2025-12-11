@echo off
SETLOCAL

:: Define o título da janela
TITLE Essentials PPack - Instalador Windows

:: Muda o diretório de trabalho para onde este arquivo .bat está
CD /D "%~dp0"

CLS
ECHO ==============================================================
ECHO          ESSENTIALS PPACK - SETUP DO WINDOWS
ECHO ==============================================================
ECHO.
ECHO Localizando setup_windows.ps1...

:: Verifica se o arquivo existe na mesma pasta
IF NOT EXIST "setup_windows.ps1" (
    ECHO [ERRO] O arquivo setup_windows.ps1 nao foi encontrado!
    ECHO Certifique-se de que este .bat esta na mesma pasta que o .ps1.
    ECHO.
    PAUSE
    EXIT /B 1
)

ECHO Arquivo encontrado. Iniciando processo...
ECHO.
ECHO * O PowerShell pode solicitar permissoes de Administrador.
ECHO * Por favor, aceite para continuar a instalacao.
ECHO.

:: Executa o script PowerShell ignorando a politica de execucao restrita
:: O comando "& '...'" garante que caminhos com espacos funcionem corretamente
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0setup_windows.ps1'"

ECHO.
ECHO ==============================================================
ECHO Execucao finalizada.
ECHO ==============================================================
ECHO.
PAUSE

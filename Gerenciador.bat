@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ORIG_DIR=%~dp0"
if "%ORIG_DIR:~-1%"=="\" set "ORIG_DIR=%ORIG_DIR:~0,-1%"

net session >nul 2>&1
if errorlevel 1 (
    set "RUN_COPY=%PUBLIC%\ServerMonitor-Gerenciador.bat"
    copy /Y "%~f0" "!RUN_COPY!" >nul 2>&1
    if not exist "!RUN_COPY!" (
        echo ERRO: Nao foi possivel preparar o gerenciador em !RUN_COPY!.
        pause
        exit /b 1
    )
    > "%PUBLIC%\ServerMonitor-origdir.txt" echo !ORIG_DIR!
    powershell -NoProfile -Command "Start-Process -FilePath ($env:PUBLIC + '\ServerMonitor-Gerenciador.bat') -Verb RunAs"
    exit /b
)

if exist "%PUBLIC%\ServerMonitor-origdir.txt" (
    set /p ORIG_DIR=<"%PUBLIC%\ServerMonitor-origdir.txt"
    del /q "%PUBLIC%\ServerMonitor-origdir.txt" >nul 2>&1
)

set "WORK_TMP=%SystemRoot%\Temp"
if not exist "%WORK_TMP%" set "WORK_TMP=%PUBLIC%"

chcp 65001 >nul
title Server Monitor - Painel de Controle
mode con: cols=74 lines=34 >nul 2>&1
color 0F

set "TASK_DASH=ServerMonitorDashboard"
set "TASK_AGENT=ServerMonitorAgente"

:MENU
call :CHECK_STATUS
cls
echo.
echo   ======================================================================
echo                    SERVER MONITOR - PAINEL DE CONTROLE
echo                       Servidor: %COMPUTERNAME% (Local)
echo   ======================================================================
echo.
echo   STATUS ATUAL
echo   ----------------------------------------------------------------------
echo.
echo     * Dashboard         : !DASH_STATUS!
echo     * Coleta (Agente)   : !AGENT_STATUS!
echo     * API / Interface   : !API_STATUS!
echo     * Telemetria        : !TELEMETRY_STATUS!
echo.
echo   OPCOES DISPONIVEIS
echo   ----------------------------------------------------------------------
echo.
echo     [1]  Iniciar dashboard
echo     [2]  Reiniciar dashboard
echo     [3]  Encerrar dashboard
echo.
echo     [4]  Atualizar status
echo     [0]  Sair
echo.
echo   ----------------------------------------------------------------------
echo.
set "OPCAO="
set /p "OPCAO=  Escolha uma opcao (0-4): "

if "%OPCAO%"=="1" goto DO_START
if "%OPCAO%"=="2" goto DO_RESTART
if "%OPCAO%"=="3" goto DO_STOP
if "%OPCAO%"=="4" goto MENU
if "%OPCAO%"=="0" goto DO_EXIT

echo.
echo   [AVISO] Opcao invalida. Digite 1, 2, 3, 4 ou 0.
timeout /t 1 /nobreak >nul
goto MENU

:DO_START
cls
echo.
echo   ======================================================================
echo                        INICIANDO A DASHBOARD...
echo   ======================================================================
echo.
call :START_SERVICES
echo.
echo   ======================================================================
if "!START_OK!"=="1" (
    echo     SISTEMA INICIADO COM SUCESSO.
    echo     A dashboard continua rodando em segundo plano no servidor.
    echo     Voce ja pode fechar esta janela ^(ou pressione ENTER para o menu^).
) else if "!START_CANCELLED!"=="1" (
    echo     OPERACAO CANCELADA.
    echo     Nenhum servico foi instalado ou iniciado.
) else (
    echo     NAO FOI POSSIVEL INICIAR A DASHBOARD.
    echo     Verifique os avisos acima e tente novamente.
)
echo   ======================================================================
echo.
set "VOLTAR="
set /p "VOLTAR=  Pressione ENTER para voltar ao menu (ou feche esta janela): "
goto MENU

:DO_RESTART
cls
echo.
echo   ======================================================================
echo                       REINICIANDO A DASHBOARD...
echo   ======================================================================
echo.
call :STOP_SERVICES
echo.
timeout /t 1 /nobreak >nul
call :START_SERVICES
echo.
echo   ======================================================================
if "!START_OK!"=="1" (
    echo     SISTEMA REINICIADO COM SUCESSO.
    echo     A dashboard continua rodando em segundo plano no servidor.
    echo     Voce ja pode fechar esta janela ^(ou pressione ENTER para o menu^).
) else if "!START_CANCELLED!"=="1" (
    echo     OPERACAO CANCELADA.
    echo     Os servicos permanecem parados.
) else (
    echo     NAO FOI POSSIVEL REINICIAR A DASHBOARD.
    echo     Verifique os avisos acima e tente novamente.
)
echo   ======================================================================
echo.
set "VOLTAR="
set /p "VOLTAR=  Pressione ENTER para voltar ao menu (ou feche esta janela): "
goto MENU

:DO_STOP
cls
echo.
echo   ======================================================================
echo                        ENCERRANDO A DASHBOARD...
echo   ======================================================================
echo.
call :STOP_SERVICES
echo.
echo   ======================================================================
echo     DASHBOARD ENCERRADA COM SUCESSO.
echo     Voce ja pode fechar esta janela (ou pressione ENTER para o menu).
echo   ======================================================================
echo.
set "VOLTAR="
set /p "VOLTAR=  Pressione ENTER para voltar ao menu (ou feche esta janela): "
goto MENU

:DO_EXIT
echo.
echo   Encerrando painel de controle...
timeout /t 1 /nobreak >nul
exit /b 0

REM ====================================================================
REM  FUNCAO: VERIFICAR PORTA ONLINE
REM ====================================================================
:PROBE_HEALTH
set "FOUND_PORT="
curl.exe -s --max-time 2 http://127.0.0.1/api/health > "%WORK_TMP%\sm_h.tmp" 2>nul
findstr /i "true" "%WORK_TMP%\sm_h.tmp" >nul 2>&1
if not errorlevel 1 (
    set "FOUND_PORT=80"
) else (
    curl.exe -s --max-time 2 http://127.0.0.1:3000/api/health > "%WORK_TMP%\sm_h.tmp" 2>nul
    findstr /i "true" "%WORK_TMP%\sm_h.tmp" >nul 2>&1
    if not errorlevel 1 set "FOUND_PORT=3000"
)
del /q "%WORK_TMP%\sm_h.tmp" >nul 2>&1
goto :eof

REM ====================================================================
REM  FUNCAO: VERIFICAR STATUS DA TELEMETRIA
REM ====================================================================
:PROBE_METRICS
set "FOUND_METRICS=offline"
if not defined PROBE_PORT goto :eof
if "%PROBE_PORT%"=="80" (
    set "M_CHECK_URL=http://127.0.0.1/api/metrics"
) else (
    set "M_CHECK_URL=http://127.0.0.1:%PROBE_PORT%/api/metrics"
)
curl.exe -s --max-time 2 "%M_CHECK_URL%" > "%WORK_TMP%\sm_m.tmp" 2>nul
findstr /i /c:"status\":\"online" "%WORK_TMP%\sm_m.tmp" >nul 2>&1
if not errorlevel 1 (
    set "FOUND_METRICS=online"
) else (
    findstr /i /c:"status\":\"waiting" "%WORK_TMP%\sm_m.tmp" >nul 2>&1
    if not errorlevel 1 set "FOUND_METRICS=waiting"
)
del /q "%WORK_TMP%\sm_m.tmp" >nul 2>&1
goto :eof

REM ====================================================================
REM  FUNCAO: VERIFICAR STATUS GERAL
REM ====================================================================
:CHECK_STATUS
set "DASH_INSTALLED=0"
set "AGENT_INSTALLED=0"
set "DASH_STATUS=Nao instalado"
set "AGENT_STATUS=Nao instalado"
set "ONLINE_PORT="
set "API_STATUS=Offline"
set "TELEMETRY_STATUS=Sem sinal"

schtasks /query /tn "%TASK_DASH%" /fo LIST > "%WORK_TMP%\sm_dash.tmp" 2>nul
if not errorlevel 1 (
    set "DASH_INSTALLED=1"
    set "DASH_STATUS=Parado"
    findstr /i /c:"Disabled" /c:"Desabilit" "%WORK_TMP%\sm_dash.tmp" >nul 2>&1 && set "DASH_STATUS=Desabilitado"
    findstr /i /c:"Running" /c:"Em execu" "%WORK_TMP%\sm_dash.tmp" >nul 2>&1 && set "DASH_STATUS=Em execucao"
)

schtasks /query /tn "%TASK_AGENT%" /fo LIST > "%WORK_TMP%\sm_agent.tmp" 2>nul
if not errorlevel 1 (
    set "AGENT_INSTALLED=1"
    set "AGENT_STATUS=Parado"
    findstr /i /c:"Disabled" /c:"Desabilit" "%WORK_TMP%\sm_agent.tmp" >nul 2>&1 && set "AGENT_STATUS=Desabilitado"
    findstr /i /c:"Running" /c:"Em execu" "%WORK_TMP%\sm_agent.tmp" >nul 2>&1 && set "AGENT_STATUS=Em execucao"
)

del /q "%WORK_TMP%\sm_dash.tmp" "%WORK_TMP%\sm_agent.tmp" >nul 2>&1

call :PROBE_HEALTH
if defined FOUND_PORT (
    set "ONLINE_PORT=!FOUND_PORT!"
    if "!ONLINE_PORT!"=="80" (
        set "API_STATUS=Online (porta 80 - http://%COMPUTERNAME%)"
    ) else (
        set "API_STATUS=Online (porta !ONLINE_PORT! - http://%COMPUTERNAME%:!ONLINE_PORT!)"
    )
    set "PROBE_PORT=!ONLINE_PORT!"
    call :PROBE_METRICS
    if "!FOUND_METRICS!"=="online" (
        set "TELEMETRY_STATUS=Online (coleta ativa)"
    ) else if "!FOUND_METRICS!"=="waiting" (
        set "TELEMETRY_STATUS=Aguardando primeiro sinal"
    ) else (
        set "TELEMETRY_STATUS=Offline (sem resposta)"
    )
)
goto :eof

REM ====================================================================
REM  FUNCAO: ENCERRAR SERVICOS
REM ====================================================================
:STOP_SERVICES
echo   [1/3] Parando servico da dashboard...
schtasks /end /tn "%TASK_DASH%" >nul 2>&1
if not errorlevel 1 (
    echo         - Tarefa %TASK_DASH% encerrada.
) else (
    echo         - Tarefa %TASK_DASH% ja estava parada.
)
echo.

echo   [2/3] Parando servico de coleta...
schtasks /end /tn "%TASK_AGENT%" >nul 2>&1
if not errorlevel 1 (
    echo         - Tarefa %TASK_AGENT% encerrada.
) else (
    echo         - Tarefa %TASK_AGENT% ja estava parada.
)
echo.

echo   [3/3] Limpando processos remanescentes e liberando a porta...
timeout /t 1 /nobreak >nul
wmic process where "name='powershell.exe' and (commandline like '%%local-server.ps1%%' or commandline like '%%server-agent.ps1%%')" call terminate >nul 2>&1
echo         - Concluido.
goto :eof

REM ====================================================================
REM  FUNCAO: INICIAR SERVICOS
REM ====================================================================
:START_SERVICES
set "START_OK=0"
set "START_CANCELLED=0"
call :CHECK_STATUS

if "!DASH_INSTALLED!"=="0" goto OFFER_INSTALL
if "!AGENT_INSTALLED!"=="0" goto OFFER_INSTALL

schtasks /change /tn "%TASK_DASH%" /enable >nul 2>&1
schtasks /change /tn "%TASK_AGENT%" /enable >nul 2>&1

echo   [1/4] Iniciando servidor da dashboard...
if defined ONLINE_PORT (
    echo         - Dashboard ja estava online na porta !ONLINE_PORT!.
) else (
    schtasks /end /tn "%TASK_DASH%" >nul 2>&1
    schtasks /run /tn "%TASK_DASH%" >nul 2>&1
    if errorlevel 1 (
        echo         - [ERRO] Nao foi possivel iniciar a tarefa %TASK_DASH%.
    ) else (
        echo         - Servico da dashboard acionado.
    )
)
echo.

echo   [2/4] Verificando disponibilidade da interface HTTP...
set "READY_PORT="
for /L %%i in (1,1,8) do (
    if not defined READY_PORT (
        call :PROBE_HEALTH
        if defined FOUND_PORT set "READY_PORT=!FOUND_PORT!"
        if not defined READY_PORT timeout /t 1 /nobreak >nul
    )
)
if defined READY_PORT (
    echo         - Servidor HTTP online na porta !READY_PORT!.
) else (
    echo         - [AVISO] Servidor ainda iniciando - nao respondeu em 8s.
)
echo.

echo   [3/4] Iniciando servico de coleta de dados...
schtasks /end /tn "%TASK_AGENT%" >nul 2>&1
timeout /t 1 /nobreak >nul
schtasks /run /tn "%TASK_AGENT%" >nul 2>&1
if errorlevel 1 (
    echo         - [ERRO] Nao foi possivel iniciar a tarefa %TASK_AGENT%.
) else (
    echo         - Servico de coleta acionado.
)
echo.

echo   [4/4] Aguardando telemetria ficar online...
set "METRICS_OK=0"
if defined READY_PORT (
    set "PROBE_PORT=!READY_PORT!"
    for /L %%i in (1,1,8) do (
        if "!METRICS_OK!"=="0" (
            call :PROBE_METRICS
            if "!FOUND_METRICS!"=="online" set "METRICS_OK=1"
            if "!METRICS_OK!"=="0" timeout /t 1 /nobreak >nul
        )
    )
)
if "!METRICS_OK!"=="1" (
    echo         - Telemetria conectada e atualizando em tempo real.
) else (
    echo         - Coleta iniciada - os dados aparecerao em alguns segundos.
)
echo.

echo   ----------------------------------------------------------------------
echo.
if defined READY_PORT (
    set "START_OK=1"
    if "!READY_PORT!"=="80" (
        echo     [ONLINE] Dashboard ativa na porta 80
        echo     Acesse:  http://%COMPUTERNAME%   ou   http://localhost
    ) else (
        echo     [ONLINE] Dashboard ativa na porta !READY_PORT!
        echo     Acesse:  http://%COMPUTERNAME%:!READY_PORT!   ou   http://localhost:!READY_PORT!
    )
) else (
    echo     [AVISO]  Aguarde alguns segundos e recarregue http://%COMPUTERNAME%
)
goto :eof

:OFFER_INSTALL
echo   [AVISO] Os servicos ainda nao estao instalados neste computador.
echo.
if exist "%ORIG_DIR%\scripts\instalar.ps1" (
    set "RESP="
    set /p "RESP=  Deseja instalar e iniciar a dashboard agora? (S/N): "
    if /i "!RESP!"=="S" (
        echo.
        powershell -NoProfile -ExecutionPolicy Bypass -File "%ORIG_DIR%\scripts\instalar.ps1"
        if not errorlevel 1 set "START_OK=1"
    ) else (
        echo.
        echo   Instalacao cancelada pelo usuario.
        set "START_CANCELLED=1"
    )
) else (
    echo   [ERRO] Instalador nao encontrado em: %ORIG_DIR%\scripts\instalar.ps1
)
goto :eof

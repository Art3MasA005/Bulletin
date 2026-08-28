@echo off
REM Windows shim so the CLAUDE.md target names work without GNU make.
REM   .\make.cmd test          .\make.cmd extract-report -- --vision
setlocal
set PY=%~dp0.venv\Scripts\python.exe
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
set TARGET=%1
if "%TARGET%"=="" set TARGET=help
shift

REM Collect remaining args into ARGS.
set ARGS=
:collect
if "%1"=="" goto run
set ARGS=%ARGS% %1
shift
goto collect

:run
if not exist "%PY%" (
  echo No virtualenv found. Run:  python -m venv .venv
  exit /b 1
)

if "%TARGET%"=="install" (
  "%PY%" -m pip install --upgrade pip && "%PY%" -m pip install -e "%~dp0backend[api,dev]"
  exit /b %ERRORLEVEL%
)
if "%TARGET%"=="extract-report" (
  cd /d "%~dp0backend" && "%PY%" -m tools.extract_report %ARGS%
  exit /b %ERRORLEVEL%
)
if "%TARGET%"=="dev" (
  cd /d "%~dp0backend" && "%PY%" -m uvicorn app.main:app --reload --port 8000
  exit /b %ERRORLEVEL%
)
if "%TARGET%"=="ingest" (
  cd /d "%~dp0backend" && "%PY%" -m tools.ingest_corpus %ARGS%
  exit /b %ERRORLEVEL%
)
if "%TARGET%"=="eval" (
  cd /d "%~dp0backend" && "%PY%" "%~dp0eval\run_eval.py" %ARGS%
  exit /b %ERRORLEVEL%
)
if "%TARGET%"=="test" (
  cd /d "%~dp0backend" && "%PY%" -m pytest -q %ARGS%
  exit /b %ERRORLEVEL%
)
if "%TARGET%"=="lint" (
  cd /d "%~dp0backend" && "%PY%" -m ruff check .
  exit /b %ERRORLEVEL%
)
if "%TARGET%"=="fmt" (
  cd /d "%~dp0backend" && "%PY%" -m ruff check --fix . && "%PY%" -m black .
  exit /b %ERRORLEVEL%
)

echo install         create .venv and install backend dependencies
echo dev             backend, reload                       (Phase 2)
echo extract-report  encoding classification -- RUN FIRST on new corpora
echo ingest          full pipeline                         (Phase 1)
echo eval            ablation tables to eval/reports/      (Phase 1)
echo test            pytest
echo fmt             ruff + black

# Bulletin -- see CLAUDE.md for what each target is for.
#
# Windows without make: use .\make.cmd <target>, which takes the same names.

PY := .venv/Scripts/python.exe
ifeq ($(OS),)
  PY := .venv/bin/python
endif

BACKEND := backend
export PYTHONUTF8 := 1
export PYTHONIOENCODING := utf-8

.PHONY: help dev extract-report ingest eval test fmt lint install

help:
	@echo "install         create .venv and install backend dependencies"
	@echo "dev             backend, reload                       (Phase 2)"
	@echo "extract-report  encoding classification -- RUN FIRST on new corpora"
	@echo "ingest          full pipeline                         (Phase 1)"
	@echo "eval            ablation tables -> eval/reports/      (Phase 1)"
	@echo "test            pytest"
	@echo "fmt             ruff + black"

install:
	python -m venv .venv
	$(PY) -m pip install --upgrade pip
	$(PY) -m pip install -e "$(BACKEND)[api,dev]"

# CLAUDE.md #7: run this before `make ingest` on any new corpus. Legacy-font
# documents ingested without the converter index as garbage, with no error.
# Runs WITHOUT vision by default, so it costs nothing; add ARGS="--vision".
extract-report:
	cd $(BACKEND) && ../$(PY) -m tools.extract_report $(ARGS)

dev:
	cd $(BACKEND) && ../$(PY) -m uvicorn app.main:app --reload --port 8000

ingest:
	cd $(BACKEND) && ../$(PY) -m tools.ingest_corpus $(ARGS)

eval:
	cd $(BACKEND) && ../$(PY) ../eval/run_eval.py $(ARGS)

test:
	cd $(BACKEND) && ../$(PY) -m pytest -q $(ARGS)

lint:
	cd $(BACKEND) && ../$(PY) -m ruff check .

fmt:
	cd $(BACKEND) && ../$(PY) -m ruff check --fix . && ../$(PY) -m black .

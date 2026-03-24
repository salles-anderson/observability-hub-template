#!/bin/sh
# -----------------------------------------------------------------------------
# Entrypoint — Inicia Chainlit com config default (gerado por chainlit init)
# Customizacoes via env vars do Chainlit:
#   CHAINLIT_CUSTOM_CSS, CHAINLIT_THEME, etc.
# -----------------------------------------------------------------------------

exec python -m chainlit run app.py -h --host 0.0.0.0 --port 8501

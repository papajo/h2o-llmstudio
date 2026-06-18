#!/bin/bash
set -e

# Ensure USER is set so that getpass.getuser() works for arbitrary UIDs
# that may not exist in /etc/passwd (e.g. when running with --user <uid>).
export USER="${USER:-$(id -un 2>/dev/null)}"

# nvidia-smi is optional — only run if available (e.g. GPU-backed runners)
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi
else
  echo "nvidia-smi not found — running without GPU diagnostics"
fi

echo "Starting H2O LLM Studio on port ${PORT:-10101}..."

# H2O_WAVE_ADDRESS is already set in the Dockerfile to bind on 0.0.0.0.
# Allow shell override: a caller can export H2O_WAVE_ADDRESS before exec.
exec wave run --no-reload llm_studio.app

# Dockerfile
#
# WHAT THIS FILE DOES:
# Builds the container image the whole pipeline revolves around. Multi-
# stage-lite: a small, pinned base image, minimal layers, non-root user.
#
# WHY THIS MATTERS FOR LEARNING:
# The ARG/ENV pattern below is exactly what lets CI stamp a unique,
# traceable version into every image it builds without editing this file
# on every commit — see .github/workflows/ci.yml, which passes
# --build-arg APP_VERSION=$(git rev-parse --short HEAD).

FROM python:3.12-slim

# Build-time argument, provided by CI (defaults to "dev" for local builds)
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Don't run as root inside the container — a basic hardening step that
# costs nothing here and is worth having as muscle memory.
RUN useradd --no-create-home --uid 1001 appuser
USER appuser

EXPOSE 5000

CMD ["python", "main.py"]

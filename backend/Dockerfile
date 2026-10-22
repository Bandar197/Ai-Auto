# AutoMind AI API image.
# BUILD CONTEXT = REPOSITORY ROOT (the image needs ../shared: PID table, KB, scenarios):
#   docker build -f backend/Dockerfile -t automind-api .

FROM python:3.13-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /src
COPY backend/pyproject.toml backend/README.md ./
COPY backend/automind ./automind
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install ".[llm]"

FROM python:3.13-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    AUTOMIND_SHARED_DIR=/app/shared \
    AUTOMIND_ENVIRONMENT=prod
RUN groupadd --system --gid 10001 automind \
 && useradd --system --uid 10001 --gid automind --home-dir /app --shell /usr/sbin/nologin automind
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY --chown=root:root shared /app/shared
USER automind:automind
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health', timeout=4).status == 200 else 1)"
# Forwarded headers are trusted only from the proxies listed in FORWARDED_ALLOW_IPS
# (uvicorn default 127.0.0.1); set it to your load balancer's address in production.
CMD ["uvicorn", "automind.api.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-server-header"]

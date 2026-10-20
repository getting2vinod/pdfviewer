FROM python:3.11-slim

# Install uv package manager
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

WORKDIR /app

# Install system dependencies required for pdf2image
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency specifications
COPY pyproject.toml uv.lock ./

# Create virtual environment and install packages
RUN uv sync --frozen --no-cache

# Copy application source code
COPY ./app ./app

# Set environment variables and python path
ENV PYTHONPATH="/app"
ENV PATH="/app/.venv/bin:$PATH"
ENV ROUTE_PATH="/pdf"
ENV DATA_DIR="/app/data"

EXPOSE 4015

# Run using python module syntax on port 4015
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "4015"]
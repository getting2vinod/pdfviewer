#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Creating project directory structure..."
mkdir -p app/templates
mkdir -p app/static/css
mkdir -p data

echo "Creating pyproject.toml..."
cat << 'EOF' > pyproject.toml
[project]
name = "pdf-image-viewer"
version = "0.1.0"
description = "FastAPI Jinja2 PDF to Image Viewer Application"
readme = "README.md"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.110.0",
    "uvicorn[standard]>=0.28.0",
    "jinja2>=3.1.3",
    "python-multipart>=0.0.9",
    "pdf2image>=1.17.0",
    "pillow>=10.2.0",
]
EOF

echo "Creating app/main.py..."
cat << 'EOF' > app/main.py
import os
import shutil
from pathlib import Path
from fastapi import FastAPI, Request, UploadFile, File, Form, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pdf2image import convert_from_path

# Read environment variables
ROUTE_PATH = os.getenv("ROUTE_PATH", "/pdf").rstrip("/")
DATA_DIR = Path(os.getenv("DATA_DIR", "/app/data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(root_path=ROUTE_PATH)

# Mount static files and data storage
app.mount("/static", StaticFiles(directory="app/static"), name="static")
app.mount("/media", StaticFiles(directory=DATA_DIR), name="media")

templates = Jinja2Templates(directory="app/templates")

# Make ROUTE_PATH universally accessible in Jinja2 templates
templates.env.globals["ROUTE_PATH"] = ROUTE_PATH

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    items = []
    if DATA_DIR.exists():
        for entry in sorted(DATA_DIR.iterdir(), key=lambda e: e.stat().st_mtime, reverse=True):
            if entry.is_dir():
                page_count = len(list(entry.glob("*.jpg")))
                items.append({
                    "name": entry.name,
                    "type": "folder",
                    "page_count": page_count,
                    "path": f"media/{entry.name}"
                })
            elif entry.is_file() and entry.suffix.lower() in [".jpg", ".jpeg"]:
                items.append({
                    "name": entry.name,
                    "type": "file",
                    "page_count": 1,
                    "path": f"media/{entry.name}"
                })

    return templates.TemplateResponse("index.html", {
        "request": request,
        "items": items
    })

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    filename = file.filename
    if not filename:
        raise HTTPException(status_code=400, detail="No file selected")

    file_ext = Path(filename).suffix.lower()
    base_name = Path(filename).stem

    if file_ext == ".pdf":
        target_folder = DATA_DIR / base_name
        target_folder.mkdir(parents=True, exist_ok=True)
        
        temp_pdf_path = target_folder / filename
        with temp_pdf_path.open("wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        try:
            images = convert_from_path(str(temp_pdf_path))
            for idx, img in enumerate(images, start=1):
                img_name = f"{base_name}_page_{idx}.jpg"
                img.save(target_folder / img_name, "JPEG")
        finally:
            if temp_pdf_path.exists():
                temp_pdf_path.unlink()

    elif file_ext in [".jpg", ".jpeg"]:
        target_file = DATA_DIR / filename
        with target_file.open("wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
    else:
        raise HTTPException(status_code=400, detail="Only PDF and JPG/JPEG files are allowed.")

    return RedirectResponse(url=f"{ROUTE_PATH}/", status_code=303)

@app.get("/preview/{item_name}", response_class=HTMLResponse)
async def preview(request: Request, item_name: str):
    target = DATA_DIR / item_name
    if not target.exists():
        raise HTTPException(status_code=404, detail="Item not found")

    images = []
    if target.is_dir():
        jpg_files = sorted(
            list(target.glob("*.jpg")),
            key=lambda p: int(p.stem.split("_page_")[-1]) if "_page_" in p.stem and p.stem.split("_page_")[-1].isdigit() else p.name
        )
        for img in jpg_files:
            images.append(f"{ROUTE_PATH}/media/{item_name}/{img.name}")
    elif target.is_file():
        images.append(f"{ROUTE_PATH}/media/{item_name}")

    return templates.TemplateResponse("preview.html", {
        "request": request,
        "title": item_name,
        "images": images
    })

@app.post("/delete")
async def delete_item(item_name: str = Form(...)):
    target = DATA_DIR / item_name
    if target.exists():
        if target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()
    return RedirectResponse(url=f"{ROUTE_PATH}/", status_code=303)
EOF

echo "Creating app/templates/base.html..."
cat << 'EOF' > app/templates/base.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}PDF Viewer Hub{% endblock %}</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css">
    <style>
        html {
            scroll-behavior: smooth;
        }
    </style>
    {% block head %}{% endblock %}
</head>
<body class="bg-light">
    {% block content %}{% endblock %}
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    {% block scripts %}{% endblock %}
</body>
</html>
EOF

echo "Creating app/templates/index.html..."
cat << 'EOF' > app/templates/index.html
{% extends "base.html" %}

{% block content %}
<nav class="navbar navbar-expand-lg navbar-dark bg-dark mb-4 shadow-sm">
    <div class="container">
        <a class="navbar-link navbar-brand fw-bold" href="{{ ROUTE_PATH }}/">
            <i class="bi bi-file-earmark-pdf-fill text-danger me-2"></i>Document Viewer Hub
        </a>
    </div>
</nav>

<div class="container mb-5">
    <div class="card shadow-sm mb-4">
        <div class="card-body">
            <h5 class="card-title mb-3"><i class="bi bi-cloud-upload me-2"></i>Upload PDF or JPG Document</h5>
            <form action="{{ ROUTE_PATH }}/upload" method="post" enctype="multipart/form-data" class="row g-3 align-items-center">
                <div class="col-md-9">
                    <input class="form-control" type="file" name="file" accept=".pdf,.jpg,.jpeg" required>
                </div>
                <div class="col-md-3">
                    <button type="submit" class="btn btn-primary w-100 fw-semibold">
                        <i class="bi bi-upload me-1"></i> Upload & Process
                    </button>
                </div>
            </form>
        </div>
    </div>

    <h4 class="mb-3">Stored Documents</h4>
    <div class="row row-cols-1 row-cols-md-3 row-cols-lg-4 g-4">
        {% for item in items %}
        <div class="col">
            <div class="card h-100 shadow-sm border-0">
                <div class="card-body text-center d-flex flex-column align-items-center justify-content-between">
                    <div class="mb-3">
                        {% if item.type == 'folder' %}
                            <i class="bi bi-folder-symlink-fill text-warning display-1"></i>
                        {% else %}
                            <i class="bi bi-file-earmark-image-fill text-primary display-1"></i>
                        {% endif %}
                    </div>
                    <div>
                        <h6 class="card-title text-truncate fw-bold mb-1" style="max-width: 220px;" title="{{ item.name }}">
                            {{ item.name }}
                        </h6>
                        <span class="badge bg-secondary mb-3">
                            {% if item.type == 'folder' %}
                                {{ item.page_count }} Page(s)
                            {% else %}
                                Image File
                            {% endif %}
                        </span>
                    </div>
                    <div class="d-flex w-100 gap-2 mt-2">
                        <a href="{{ ROUTE_PATH }}/preview/{{ item.name }}" class="btn btn-outline-primary btn-sm flex-fill">
                            <i class="bi bi-eye"></i> View
                        </a>
                        <form action="{{ ROUTE_PATH }}/delete" method="post" onsubmit="return confirm('Are you sure you want to delete this file?');" class="flex-fill">
                            <input type="hidden" name="item_name" value="{{ item.name }}">
                            <button type="submit" class="btn btn-outline-danger btn-sm w-100">
                                <i class="bi bi-trash"></i> Delete
                            </button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
        {% else %}
        <div class="col-12">
            <div class="alert alert-info text-center" role="alert">
                No documents found. Upload a file above to get started!
            </div>
        </div>
        {% endfor %}
    </div>
</div>
{% endblock %}
EOF

echo "Creating app/templates/preview.html..."
cat << 'EOF' > app/templates/preview.html
{% extends "base.html" %}

{% block head %}
<style>
    body {
        overflow: hidden;
    }
    #fixed-header {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        height: 60px;
        z-index: 1030;
    }
    #content-container {
        position: absolute;
        top: 60px;
        bottom: 0;
        left: 0;
        right: 0;
        overflow-y: auto;
        padding: 20px 0;
    }
    #blankout-overlay {
        display: none;
        position: fixed;
        top: 0;
        left: 0;
        width: 100vw;
        height: 100vh;
        background-color: black;
        z-index: 9999;
        color: white;
    }
</style>
{% endblock %}

{% block content %}
<div id="blankout-overlay" class="d-flex flex-column justify-content-center align-items-center">
    <h3>Screen timed out due to inactivity</h3>
    <p>Move mouse, touch screen, or press any key to resume viewing.</p>
</div>

<div id="fixed-header" class="bg-dark text-white d-flex align-items-center justify-content-between px-4 shadow">
    <a href="{{ ROUTE_PATH }}/" class="btn btn-outline-light btn-sm">
        <i class="bi bi-arrow-left me-1"></i> Back
    </a>
    <h5 class="m-0 text-truncate mx-3 fw-bold">{{ title }}</h5>
    <div style="width: 75px;"></div>
</div>

<div id="content-container">
    <div class="container d-flex flex-column align-items-center">
        {% for img_path in images %}
            <div class="card shadow mb-4 bg-white p-2">
                <img src="{{ img_path }}" class="img-fluid rounded" alt="Page Image" loading="lazy">
            </div>
        {% endfor %}
    </div>
</div>
{% endblock %}

{% block scripts %}
<script>
    const itemKey = "scroll_pos_" + encodeURIComponent("{{ title }}");
    const container = document.getElementById("content-container");
    const overlay = document.getElementById("blankout-overlay");

    window.addEventListener("DOMContentLoaded", () => {
        const savedPos = localStorage.getItem(itemKey);
        if (savedPos) {
            container.scrollTop = parseInt(savedPos, 10);
        }
    });

    let isScrolling;
    container.addEventListener("scroll", () => {
        window.clearTimeout(isScrolling);
        isScrolling = setTimeout(() => {
            localStorage.setItem(itemKey, container.scrollTop);
        }, 100);
    });

    const INACTIVITY_TIMEOUT = 10 * 60 * 1000;
    let inactivityTimer;

    function resetInactivityTimer() {
        if (overlay.style.display === "flex") {
            overlay.style.display = "none";
        }
        clearTimeout(inactivityTimer);
        inactivityTimer = setTimeout(() => {
            overlay.style.display = "flex";
        }, INACTIVITY_TIMEOUT);
    }

    ["mousemove", "keydown", "click", "touchstart", "scroll"].forEach(evt => {
        window.addEventListener(evt, resetInactivityTimer, true);
    });

    resetInactivityTimer();
</script>
{% endblock %}
EOF

echo "Creating Dockerfile..."
cat << 'EOF' > Dockerfile
FROM python:3.11-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-cache

FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/.venv /.venv

COPY ./app ./app

ENV PATH="/.venv/bin:$PATH"
ENV ROUTE_PATH="/pdf"
ENV DATA_DIR="/app/data"

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

echo "Creating docker-compose.yml..."
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  pdf-app:
    build: .
    container_name: pdf_viewer_app
    restart: always
    environment:
      - ROUTE_PATH=/pdf
      - DATA_DIR=/app/data
    volumes:
      - pdf_data:/app/data
    ports:
      - "8000:8000"

volumes:
  pdf_data:
EOF

echo "Project structure successfully created and populated!"
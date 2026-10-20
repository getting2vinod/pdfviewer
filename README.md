# PDF & Image Viewer Web Application

A lightweight, high-performance web application built with Python FastAPI, Jinja2, and Bootstrap 5 to store, view, and manage uploaded PDF and image documents. PDFs are automatically broken down page-by-page into high-quality JPEG images for effortless browser viewing.

---

## 🌟 Key Features

* **Subpath Reverse Proxy Ready:** Configured with the `ROUTE_PATH` environment variable (e.g., `/pdf`), ensuring all URLs, forms, dynamic assets, and Jinja templates adjust correctly when hosted behind Nginx, Caddy, or DuckDNS subpaths.
* **Automatic PDF Page Extraction:** Uploaded PDFs are stored in dedicated folders named after the source file, with each page extracted as `_page_x.jpg`.
* **Clean Card Dashboard:** Displays files and folders in a responsive Bootstrap 5 grid sorted chronologically by upload date in descending order.
  * PDF folders feature a red PDF icon (`bi-file-earmark-pdf-fill`).
  * Image files feature a blue image icon (`bi-file-earmark-image-fill`).
  * Full file names are displayed without truncation.
  * Card corners are rounded (`rounded-4`), and delete actions are styled discretely to prevent accidental removal.
* **Interactive Document Preview:**
  * Fixed header section showing the document name with an explicit back button.
  * Scroll position auto-saved to `localStorage` per document—resumes exactly where you left off on return.
  * **Inactivity Blankout:** Automatically blacks out the view after 10 minutes of inactivity to preserve display life and privacy; unblanks immediately on mouse movement, touch, or keypress.
* **Modern Python Tooling:** Uses `uv` as the fast dependency manager and runs in an optimized multi-stage Docker container with `poppler-utils`.

---

## 📂 Project Architecture

```text
pdf-app/
├── app/
│   ├── main.py              # FastAPI endpoints, static mounts, and Jinja setup
│   └── templates/
│       ├── base.html        # Shared layout, Bootstrap 5 CDN, and icons
│       ├── index.html       # Card view dashboard and upload interface
│       └── preview.html     # Scrollable image reader with inactivity blankout
├── data/                    # Persistent storage volume for uploads
├── .vscode/
│   └── launch.json          # VS Code local uvicorn debugger configuration
├── pyproject.toml           # Package requirements managed by uv
├── setup.sh                 # Single-command setup script
├── Dockerfile               # Multi-stage Docker image using python-slim & poppler
└── docker-compose.yml       # Production deployment specification


Nginx Config:

location /pdf/ {
    proxy_pass [http://127.0.0.1:8000/](http://127.0.0.1:8000/);
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    client_max_body_size 50M; //will help with large files.
}



# Install dependencies into virtualenv
uv sync

# Run uvicorn server locally
ROUTE_PATH="/pdf" DATA_DIR="./data" uv run uvicorn app.main:app --reload --port 8000
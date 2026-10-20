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

    return templates.TemplateResponse(
        request=request,
        name="index.html",
        context={"items": items}
    )

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

    return templates.TemplateResponse(
        request=request,
        name="preview.html",
        context={"title": item_name, "images": images}
    )

@app.post("/delete")
async def delete_item(item_name: str = Form(...)):
    target = DATA_DIR / item_name
    if target.exists():
        if target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()
    return RedirectResponse(url=f"{ROUTE_PATH}/", status_code=303)
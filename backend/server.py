"""
Flames-Up Governance Dashboard Server
Serves the admin web dashboard + proxies health checks.
All API traffic goes directly to Cloudflare Workers.
"""
import os
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, RedirectResponse
from starlette.middleware.cors import CORSMiddleware

app = FastAPI(title="Flames-Up Governance")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

STATIC_DIR = os.path.join(os.path.dirname(__file__), "static", "admin")

@app.get("/api/health")
async def health():
    return {"status": "ok", "message": "Flames-Up Governance Dashboard Server"}

@app.get("/api/gov")
async def gov_redirect():
    return RedirectResponse(url="/api/gov/")

@app.get("/api/gov/")
async def gov_index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"), media_type="text/html")

@app.get("/api/{path:path}")
async def catch_all(path: str):
    return {"error": "This backend is deprecated. Use Cloudflare Workers API.", "path": path}

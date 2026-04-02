"""
Minimal stub server - Legacy backend replaced by Cloudflare Workers.
All API traffic goes directly to https://flames-up-api.karfalacisse900.workers.dev
This stub only exists to keep the supervisor process alive.
"""
from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

app = FastAPI(title="Flames-Up Legacy Stub")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/health")
async def health():
    return {"status": "stub", "message": "Backend migrated to Cloudflare Workers"}

@app.get("/api/{path:path}")
async def catch_all(path: str):
    return {"error": "This backend is deprecated. Use Cloudflare Workers API.", "path": path}

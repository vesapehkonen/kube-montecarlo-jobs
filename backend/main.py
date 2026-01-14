from __future__ import annotations

import logging
import time
import uuid
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

#from backend.backend_io import JobMsg, RedisJobQueue, RedisJobStore, build_redis
from backend.wiring import build_backend
from backend.interfaces import JobMsg

logger = logging.getLogger("demoapp")

app = FastAPI(title="Job Demo API")

# -------------------------
# Redis-backed store + queue
# -------------------------
store, queue = build_backend()

#r = build_redis()
#store = RedisJobStore(r)
#queue = RedisJobQueue(r)

# -------------------------
# API models
# -------------------------
class CreateJobRequest(BaseModel):
    ticker: str = Field(default="AAPL", min_length=1, max_length=16)
    horizon_days: int = Field(default=30, ge=1, le=365)
    simulations: int = Field(default=10_000, ge=100, le=2_000_000)


class JobResponse(BaseModel):
    id: str
    ticker: str
    status: str
    created_at: float
    started_at: Optional[float] = None
    finished_at: Optional[float] = None
    result: Optional[Any] = None
    error: Optional[str] = None


# -------------------------
# Serve frontend
# -------------------------
BASE_DIR = Path(__file__).resolve().parent.parent

@app.get("/")
def index():
    return FileResponse(BASE_DIR / "frontend" / "index.html")


# -------------------------
# API endpoints
# -------------------------
@app.post("/api/jobs", response_model=JobResponse)
def create_job(req: CreateJobRequest):
    job_id = uuid.uuid4().hex
    now = time.time()

    job = {
        "id": job_id,
        "ticker": req.ticker.strip().upper(),
        "status": "queued",
        "created_at": now,
        "started_at": None,
        "finished_at": None,
        "result": None,
        "error": None,
        # keep request parameters for debugging / audit
        "horizon_days": req.horizon_days,
        "simulations": req.simulations,
    }

    store.save(job)
    queue.enqueue(JobMsg(job_id=job_id, horizon_days=req.horizon_days, simulations=req.simulations))
    return job


@app.get("/api/jobs")
def list_jobs_endpoint():
    return store.list()


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
    job = store.load(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return job

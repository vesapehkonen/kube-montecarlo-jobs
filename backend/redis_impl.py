# backend/redis_impl.py
from __future__ import annotations

import json
import os
from typing import Any, Optional

import redis

from .interfaces import JobMsg, JobStore, JobQueue, QueueItem


class RedisJobStore:
    def __init__(self, r: redis.Redis, key_prefix: str = "jobs:") -> None:
        self._r = r
        self._prefix = key_prefix

    def _key(self, job_id: str) -> str:
        return f"{self._prefix}{job_id}"

    def save(self, job: dict[str, Any]) -> None:
        self._r.set(self._key(job["id"]), json.dumps(job))

    def load(self, job_id: str) -> Optional[dict[str, Any]]:
        raw = self._r.get(self._key(job_id))
        return json.loads(raw) if raw else None

    def list(self) -> list[dict[str, Any]]:
        keys = self._r.keys(f"{self._prefix}*")
        jobs: list[dict[str, Any]] = []
        for k in keys:
            raw = self._r.get(k)
            if raw:
                jobs.append(json.loads(raw))

        def sort_key(j: dict[str, Any]) -> float:
            v = j.get("created_at")
            if isinstance(v, (int, float)):
                return float(v)
            if isinstance(v, str):
                try:
                    from datetime import datetime
                    return datetime.fromisoformat(v).timestamp()
                except Exception:
                    return 0.0
            return 0.0

        jobs.sort(key=sort_key, reverse=True)
        return jobs


class RedisJobQueue:
    def __init__(self, r: redis.Redis, queue_key: str = "queue:jobs") -> None:
        self._r = r
        self._queue_key = queue_key

    def enqueue(self, msg: JobMsg) -> None:
        self._r.lpush(self._queue_key, msg.to_json())

    def dequeue_blocking(self) -> QueueItem:
        _, raw = self._r.brpop(self._queue_key)
        msg = JobMsg.from_json(raw)
        return QueueItem(msg=msg, ack=lambda: None)


def build_redis() -> redis.Redis:
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    return redis.Redis.from_url(redis_url, decode_responses=True)

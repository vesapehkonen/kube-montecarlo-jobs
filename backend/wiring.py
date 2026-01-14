# backend/wiring.py
from __future__ import annotations

import os
from typing import Tuple

from .interfaces import JobQueue, JobStore


def build_backend() -> tuple[JobStore, JobQueue]:
    mode = os.getenv("APP_MODE", "local").lower()
    # local: Redis store + Redis queue
    if mode == "local":
        from .redis_impl import RedisJobQueue, RedisJobStore, build_redis
        r = build_redis()
        return RedisJobStore(r), RedisJobQueue(r)

    # aws: Dynamo store + SQS queue
    if mode == "aws":
        from .sqs_impl import build_sqs_queue_from_env
        from .dynamo_impl import build_dynamo_store_from_env
        store = build_dynamo_store_from_env()
        queue = build_sqs_queue_from_env()
        return store, queue

    raise ValueError(f"Unknown APP_MODE={mode!r} (expected 'local' or 'aws')")

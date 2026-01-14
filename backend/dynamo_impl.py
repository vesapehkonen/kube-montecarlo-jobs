# backend/dynamo_impl.py
from __future__ import annotations

import json
import os
from typing import Any, Optional

import boto3

from .interfaces import JobStore


class DynamoJobStore:
    def __init__(self, table_name: str, region: Optional[str] = None) -> None:
        self._dynamodb = boto3.resource("dynamodb", region_name=region)
        self._table = self._dynamodb.Table(table_name)

    def save(self, job: dict[str, Any]) -> None:
        item = {
            "id": job["id"],
            "payload": json.dumps(job, default=str),  # default=str handles any odd types
        }
        # Optional, helps sorting without parsing payload
        if "created_at" in job:
            try:
                item["created_at"] = float(job["created_at"])
            except Exception:
                pass

        self._table.put_item(Item=item)

    def load(self, job_id: str) -> Optional[dict[str, Any]]:
        resp = self._table.get_item(Key={"id": job_id})
        item = resp.get("Item")
        if not item:
            return None
        return json.loads(item["payload"])

    def list(self) -> list[dict[str, Any]]:
        # For a demo app, Scan is OK. For large scale, you'd want a GSI by created_at.
        jobs: list[dict[str, Any]] = []
        last_key = None

        while True:
            kwargs = {}
            if last_key:
                kwargs["ExclusiveStartKey"] = last_key

            resp = self._table.scan(**kwargs)
            for it in resp.get("Items", []):
                try:
                    jobs.append(json.loads(it["payload"]))
                except Exception:
                    continue

            last_key = resp.get("LastEvaluatedKey")
            if not last_key:
                break

        jobs.sort(key=lambda j: float(j.get("created_at", 0.0)), reverse=True)
        return jobs


def build_dynamo_store_from_env() -> DynamoJobStore:
    table = os.environ["DDB_TABLE_NAME"]
    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
    return DynamoJobStore(table_name=table, region=region)

# backend/interfaces.py
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Callable, Optional, Protocol


@dataclass(frozen=True)
class JobMsg:
    job_id: str
    horizon_days: int
    simulations: int

    def to_json(self) -> str:
        return json.dumps(
            {
                "job_id": self.job_id,
                "horizon_days": self.horizon_days,
                "simulations": self.simulations,
            }
        )

    @staticmethod
    def from_json(raw: str) -> "JobMsg":
        d = json.loads(raw)
        return JobMsg(
            job_id=d["job_id"],
            horizon_days=int(d["horizon_days"]),
            simulations=int(d["simulations"]),
        )


@dataclass(frozen=True)
class QueueItem:
    msg: JobMsg
    ack: Callable[[], None]


class JobStore(Protocol):
    def save(self, job: dict[str, Any]) -> None: ...
    def load(self, job_id: str) -> Optional[dict[str, Any]]: ...
    def list(self) -> list[dict[str, Any]]: ...


class JobQueue(Protocol):
    def enqueue(self, msg: JobMsg) -> None: ...
    def dequeue_blocking(self) -> QueueItem: ...
    

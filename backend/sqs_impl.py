# backend/sqs_impl.py
from __future__ import annotations

import os
import time
from typing import Optional

import boto3

from .interfaces import JobMsg, JobQueue, QueueItem


class SqsJobQueue:
    """
    Minimal SQS-backed queue that matches JobQueue.
    - enqueue: SendMessage with JSON body
    - dequeue_blocking: long poll ReceiveMessage; returns QueueItem with ack() that DeleteMessage's
    """

    def __init__(
        self,
        queue_url: str,
        region: Optional[str] = None,
        wait_time_seconds: int = 20,
        visibility_timeout: Optional[int] = None,
    ) -> None:
        self._queue_url = queue_url
        self._wait = max(0, min(wait_time_seconds, 20))  # SQS max long poll wait is 20
        self._visibility_timeout = visibility_timeout
        self._client = boto3.client("sqs", region_name=region)

    def enqueue(self, msg: JobMsg) -> None:
        self._client.send_message(
            QueueUrl=self._queue_url,
            MessageBody=msg.to_json(),
        )

    def dequeue_blocking(self) -> QueueItem:
        # Loop so it truly blocks (ReceiveMessage can return empty).
        while True:
            kwargs = {
                "QueueUrl": self._queue_url,
                "MaxNumberOfMessages": 1,
                "WaitTimeSeconds": self._wait,
            }
            if self._visibility_timeout is not None:
                kwargs["VisibilityTimeout"] = int(self._visibility_timeout)

            resp = self._client.receive_message(**kwargs)
            messages = resp.get("Messages", [])
            if not messages:
                continue

            m = messages[0]
            body = m["Body"]
            receipt = m["ReceiptHandle"]

            job_msg = JobMsg.from_json(body)

            def _ack() -> None:
                self._client.delete_message(
                    QueueUrl=self._queue_url,
                    ReceiptHandle=receipt,
                )

            return QueueItem(msg=job_msg, ack=_ack)


def build_sqs_queue_from_env() -> SqsJobQueue:
    queue_url = os.environ["SQS_QUEUE_URL"]
    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
    wait = int(os.getenv("SQS_WAIT_TIME_SECONDS", "20"))
    vis = os.getenv("SQS_VISIBILITY_TIMEOUT")
    visibility_timeout = int(vis) if vis else None
    return SqsJobQueue(
        queue_url=queue_url,
        region=region,
        wait_time_seconds=wait,
        visibility_timeout=visibility_timeout,
    )

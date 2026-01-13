import time
import logging

from backend.sim import get_prices_stooq, fake_price_history, monte_carlo_gbm_metrics

#from backend.backend_io import RedisJobQueue, RedisJobStore, build_redis
from backend.wiring import build_backend
from backend.interfaces import JobMsg

logger = logging.getLogger("demoapp")


def main():
    #r = build_redis()
    #store = RedisJobStore(r)
    #queue = RedisJobQueue(r)
    store, queue = build_backend()

    print("[worker] started, waiting for jobs...")

    while True:
        item = queue.dequeue_blocking()
        msg = item.msg

        job = store.load(msg.job_id)
        if not job:
            continue

        # idempotency-ish: if job already completed, skip
        if job.get("status") in ("done", "failed"):
            continue

        job["status"] = "running"
        job["started_at"] = time.time()
        store.save(job)

        try:
            try:
                prices = get_prices_stooq(job["ticker"], days=252)
                price_source = "stooq"
            except Exception as e:
                prices = []
                price_source = "stooq_error"
                logger.warning("Stooq fetch failed for %s job_id=%s: %s", job.get("ticker"), msg.job_id, e)

            if not prices:
                prices = fake_price_history(job["ticker"], days=252)
                price_source = "synthetic_fallback"

            metrics = monte_carlo_gbm_metrics(prices, msg.horizon_days, msg.simulations)
            metrics["price_source"] = price_source

            job["result"] = metrics
            job["status"] = "done"
            job["finished_at"] = time.time()
            store.save(job)

        except Exception as e:
            job["status"] = "failed"
            job["error"] = str(e)
            job["finished_at"] = time.time()
            store.save(job)
        finally:
            item.ack()

if __name__ == "__main__":
    main()

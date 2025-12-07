#!/usr/bin/env python3
"""
Dual-SKU Load Test Comparison

Runs identical load tests against both Jetson Thor and RTX 4000 Pro
simulations to demonstrate how the unified solution behaves differently
based on hardware configuration.

Usage:
    python load-test-comparison.py

Requirements:
    pip install requests aiohttp asyncio
"""

import asyncio
import aiohttp
import time
import json
from dataclasses import dataclass
from typing import List, Dict
import statistics

@dataclass
class TestResult:
    sku: str
    endpoint: str
    sessions_created: int
    sessions_rejected: int
    avg_latency_ms: float
    p90_latency_ms: float
    total_requests: int
    errors: int

async def create_session(session: aiohttp.ClientSession, base_url: str) -> Dict:
    """Create an inference session"""
    try:
        async with session.post(f"{base_url}/v1/sessions") as resp:
            if resp.status == 200:
                return {"success": True, "data": await resp.json()}
            elif resp.status == 503:
                return {"success": False, "reason": "max_sessions"}
            else:
                return {"success": False, "reason": f"status_{resp.status}"}
    except Exception as e:
        return {"success": False, "reason": str(e)}

async def send_inference(session: aiohttp.ClientSession, base_url: str, session_id: str) -> Dict:
    """Send an inference request"""
    start = time.perf_counter()
    try:
        payload = {
            "prompt": "What maintenance is required for an HVAC unit showing high discharge temperature?",
            "session_id": session_id,
            "max_tokens": 128
        }
        async with session.post(f"{base_url}/v1/chat", json=payload) as resp:
            latency = (time.perf_counter() - start) * 1000
            if resp.status == 200:
                data = await resp.json()
                return {
                    "success": True,
                    "latency_ms": latency,
                    "ttft_ms": data.get("metrics", {}).get("ttft_ms", 0)
                }
            else:
                return {"success": False, "latency_ms": latency}
    except Exception as e:
        return {"success": False, "error": str(e)}

async def get_sku_config(base_url: str) -> Dict:
    """Get SKU configuration"""
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{base_url}/v1/sku") as resp:
            if resp.status == 200:
                return await resp.json()
            return {}

async def run_load_test(sku_name: str, base_url: str, target_sessions: int, requests_per_session: int) -> TestResult:
    """Run load test against a single SKU endpoint"""
    print(f"\n{'='*60}")
    print(f"Testing: {sku_name}")
    print(f"Endpoint: {base_url}")
    print(f"Target sessions: {target_sessions}")
    print(f"Requests per session: {requests_per_session}")
    print('='*60)

    # Get config
    config = await get_sku_config(base_url)
    max_sessions = config.get("applied_config", {}).get("max_concurrent_sessions", "unknown")
    print(f"Configured max_sessions: {max_sessions}")

    sessions_created = 0
    sessions_rejected = 0
    session_ids = []
    latencies = []
    errors = 0

    async with aiohttp.ClientSession() as http_session:
        # Phase 1: Create sessions up to limit
        print(f"\nPhase 1: Creating sessions...")
        for i in range(target_sessions):
            result = await create_session(http_session, base_url)
            if result["success"]:
                sessions_created += 1
                session_ids.append(result["data"]["session_id"])
                print(f"  Session {i+1}: Created ({result['data']['session_id']})")
            else:
                sessions_rejected += 1
                print(f"  Session {i+1}: Rejected ({result['reason']})")

        print(f"\nSessions: {sessions_created} created, {sessions_rejected} rejected")

        # Phase 2: Send inference requests
        if session_ids:
            print(f"\nPhase 2: Sending {requests_per_session} requests per session...")
            tasks = []
            for session_id in session_ids:
                for _ in range(requests_per_session):
                    tasks.append(send_inference(http_session, base_url, session_id))

            results = await asyncio.gather(*tasks)

            for r in results:
                if r.get("success"):
                    latencies.append(r["latency_ms"])
                else:
                    errors += 1

    # Calculate stats
    avg_latency = statistics.mean(latencies) if latencies else 0
    p90_latency = sorted(latencies)[int(len(latencies) * 0.9)] if len(latencies) > 1 else avg_latency

    return TestResult(
        sku=sku_name,
        endpoint=base_url,
        sessions_created=sessions_created,
        sessions_rejected=sessions_rejected,
        avg_latency_ms=round(avg_latency, 2),
        p90_latency_ms=round(p90_latency, 2),
        total_requests=len(latencies) + errors,
        errors=errors
    )

def print_comparison(jetson: TestResult, rtx: TestResult):
    """Print side-by-side comparison"""
    print("\n")
    print("=" * 80)
    print("                    DUAL-SKU LOAD TEST COMPARISON")
    print("=" * 80)
    print()
    print(f"{'Metric':<30} {'Jetson Thor':<20} {'RTX 4000 Pro':<20}")
    print("-" * 80)
    print(f"{'Sessions Created':<30} {jetson.sessions_created:<20} {rtx.sessions_created:<20}")
    print(f"{'Sessions Rejected':<30} {jetson.sessions_rejected:<20} {rtx.sessions_rejected:<20}")
    print(f"{'Total Requests':<30} {jetson.total_requests:<20} {rtx.total_requests:<20}")
    print(f"{'Errors':<30} {jetson.errors:<20} {rtx.errors:<20}")
    print(f"{'Avg Latency (ms)':<30} {jetson.avg_latency_ms:<20} {rtx.avg_latency_ms:<20}")
    print(f"{'P90 Latency (ms)':<30} {jetson.p90_latency_ms:<20} {rtx.p90_latency_ms:<20}")
    print("-" * 80)
    print()

    # Analysis
    print("ANALYSIS:")
    print("-" * 40)

    if jetson.sessions_created > rtx.sessions_created:
        print(f"  Jetson Thor handled {jetson.sessions_created - rtx.sessions_created} more concurrent sessions")
        print(f"  This matches expectation: Thor has 128GB unified vs RTX's 20GB dedicated")

    if jetson.sessions_rejected < rtx.sessions_rejected:
        print(f"  RTX rejected {rtx.sessions_rejected - jetson.sessions_rejected} more session requests")
        print(f"  This is expected due to lower max_concurrent_sessions config")

    print()
    print("KEY INSIGHT:")
    print("  Same container image, same code, different behavior based on SKU config.")
    print("  This is the 'unified optimized solution' the SOW requires.")
    print()

async def main():
    print("=" * 80)
    print("     HONEYWELL FORGE COGNITION - DUAL-SKU LOAD TEST")
    print("=" * 80)
    print()
    print("This test demonstrates how the unified container behaves differently")
    print("based on SKU-specific configuration.")
    print()
    print("Prerequisites:")
    print("  1. Run: ./simulation/compare-skus.sh (to start both simulations)")
    print("  2. Verify endpoints:")
    print("     - Jetson Thor: http://localhost:8001")
    print("     - RTX 4000 Pro: http://localhost:8002")
    print()

    # Test parameters
    TARGET_SESSIONS = 15  # More than RTX limit (8), less than Jetson limit (20)
    REQUESTS_PER_SESSION = 3

    try:
        # Run tests
        jetson_result = await run_load_test(
            "Jetson AGX Thor",
            "http://localhost:8001",
            TARGET_SESSIONS,
            REQUESTS_PER_SESSION
        )

        rtx_result = await run_load_test(
            "RTX 4000 Pro",
            "http://localhost:8002",
            TARGET_SESSIONS,
            REQUESTS_PER_SESSION
        )

        # Compare
        print_comparison(jetson_result, rtx_result)

    except aiohttp.ClientConnectorError as e:
        print(f"\nERROR: Could not connect to simulation endpoints.")
        print(f"Make sure to run: ./simulation/compare-skus.sh first")
        print(f"Details: {e}")

if __name__ == "__main__":
    asyncio.run(main())

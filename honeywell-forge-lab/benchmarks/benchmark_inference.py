#!/usr/bin/env python3
"""
Honeywell Forge Cognition - Inference Benchmarking Suite
Comprehensive performance testing for LLM inference optimization

Benchmarks:
1. Single-user latency baseline
2. Concurrent user scaling
3. Token throughput
4. Memory footprint per session
5. Latency degradation curve

Usage:
    python benchmark_inference.py --host http://localhost:8000
    python benchmark_inference.py --host http://localhost:8000 --output results/
    python benchmark_inference.py --host http://localhost:8000 --quick
"""

import argparse
import asyncio
import json
import os
import statistics
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from typing import List, Dict, Optional

import aiohttp


@dataclass
class BenchmarkResult:
    """Single benchmark measurement"""
    name: str
    concurrent_users: int
    total_requests: int
    successful_requests: int
    failed_requests: int
    ttft_p50_ms: float
    ttft_p90_ms: float
    ttft_p99_ms: float
    ttft_mean_ms: float
    latency_p50_ms: float
    latency_p90_ms: float
    latency_p99_ms: float
    latency_mean_ms: float
    tokens_per_second_mean: float
    requests_per_second: float
    duration_seconds: float


@dataclass
class BenchmarkSuite:
    """Complete benchmark suite results"""
    timestamp: str
    host: str
    results: List[BenchmarkResult]
    hardware_info: Dict


class InferenceBenchmark:
    """Benchmark runner for Forge Cognition inference server"""

    SAMPLE_PROMPTS = [
        "What is the maintenance schedule for HVAC unit AHU-001?",
        "Show me the fault history for chiller CH-003",
        "What are common causes of high discharge pressure?",
        "Generate a preventive maintenance checklist for elevator ELV-012",
        "What spare parts should be stocked for boiler BLR-005?",
    ]

    def __init__(self, host: str, output_dir: Optional[str] = None):
        self.host = host.rstrip('/')
        self.output_dir = output_dir
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)

    def percentile(self, data: List[float], p: float) -> float:
        """Calculate percentile"""
        if not data:
            return 0.0
        sorted_data = sorted(data)
        index = int(len(sorted_data) * p / 100)
        return sorted_data[min(index, len(sorted_data) - 1)]

    async def single_request(
        self,
        session: aiohttp.ClientSession,
        prompt: str,
        session_id: Optional[str] = None
    ) -> Dict:
        """Make a single inference request"""
        payload = {
            "prompt": prompt,
            "max_tokens": 256,
            "temperature": 0.7
        }
        if session_id:
            payload["session_id"] = session_id

        start = time.perf_counter()
        try:
            async with session.post(
                f"{self.host}/v1/chat",
                json=payload,
                timeout=aiohttp.ClientTimeout(total=60)
            ) as response:
                elapsed = (time.perf_counter() - start) * 1000

                if response.status == 200:
                    data = await response.json()
                    return {
                        "success": True,
                        "ttft_ms": data.get("metrics", {}).get("ttft_ms", elapsed),
                        "latency_ms": data.get("metrics", {}).get("total_latency_ms", elapsed),
                        "tokens_per_second": data.get("metrics", {}).get("tokens_per_second", 0),
                        "elapsed_ms": elapsed
                    }
                else:
                    return {
                        "success": False,
                        "error": f"HTTP {response.status}",
                        "elapsed_ms": elapsed
                    }
        except Exception as e:
            elapsed = (time.perf_counter() - start) * 1000
            return {
                "success": False,
                "error": str(e),
                "elapsed_ms": elapsed
            }

    async def run_concurrent_test(
        self,
        num_users: int,
        requests_per_user: int
    ) -> List[Dict]:
        """Run concurrent user test"""
        results = []

        async def user_session():
            """Simulate a single user making requests"""
            user_results = []
            async with aiohttp.ClientSession() as session:
                # Create session
                try:
                    async with session.post(f"{self.host}/v1/sessions") as resp:
                        if resp.status == 200:
                            data = await resp.json()
                            session_id = data.get("session_id")
                        else:
                            session_id = None
                except:
                    session_id = None

                # Make requests
                for _ in range(requests_per_user):
                    prompt = self.SAMPLE_PROMPTS[len(user_results) % len(self.SAMPLE_PROMPTS)]
                    result = await self.single_request(session, prompt, session_id)
                    user_results.append(result)
                    await asyncio.sleep(0.1)  # Small delay between requests

                # Close session
                if session_id:
                    try:
                        await session.delete(f"{self.host}/v1/sessions/{session_id}")
                    except:
                        pass

            return user_results

        # Run all users concurrently
        tasks = [user_session() for _ in range(num_users)]
        user_results = await asyncio.gather(*tasks)

        # Flatten results
        for user_result in user_results:
            results.extend(user_result)

        return results

    def analyze_results(
        self,
        name: str,
        concurrent_users: int,
        results: List[Dict],
        duration: float
    ) -> BenchmarkResult:
        """Analyze benchmark results"""
        successful = [r for r in results if r.get("success")]
        failed = [r for r in results if not r.get("success")]

        ttft_values = [r["ttft_ms"] for r in successful if "ttft_ms" in r]
        latency_values = [r["latency_ms"] for r in successful if "latency_ms" in r]
        tps_values = [r["tokens_per_second"] for r in successful if "tokens_per_second" in r]

        return BenchmarkResult(
            name=name,
            concurrent_users=concurrent_users,
            total_requests=len(results),
            successful_requests=len(successful),
            failed_requests=len(failed),
            ttft_p50_ms=self.percentile(ttft_values, 50),
            ttft_p90_ms=self.percentile(ttft_values, 90),
            ttft_p99_ms=self.percentile(ttft_values, 99),
            ttft_mean_ms=statistics.mean(ttft_values) if ttft_values else 0,
            latency_p50_ms=self.percentile(latency_values, 50),
            latency_p90_ms=self.percentile(latency_values, 90),
            latency_p99_ms=self.percentile(latency_values, 99),
            latency_mean_ms=statistics.mean(latency_values) if latency_values else 0,
            tokens_per_second_mean=statistics.mean(tps_values) if tps_values else 0,
            requests_per_second=len(successful) / duration if duration > 0 else 0,
            duration_seconds=duration
        )

    async def get_hardware_info(self) -> Dict:
        """Get GPU info from server"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.host}/v1/gpu/stats") as resp:
                    if resp.status == 200:
                        return await resp.json()
        except:
            pass
        return {}

    async def run_suite(self, quick: bool = False) -> BenchmarkSuite:
        """Run complete benchmark suite"""
        print("=" * 60)
        print("FORGE COGNITION BENCHMARK SUITE")
        print("=" * 60)
        print(f"Host: {self.host}")
        print(f"Mode: {'Quick' if quick else 'Full'}")
        print()

        # Get hardware info
        print("Getting hardware info...")
        hardware_info = await self.get_hardware_info()
        if hardware_info.get("gpus"):
            for gpu in hardware_info["gpus"]:
                print(f"  GPU {gpu.get('gpu_id', 0)}: "
                      f"{gpu.get('memory_total_gb', 0):.1f}GB total, "
                      f"{gpu.get('memory_used_gb', 0):.1f}GB used")

        results = []

        # Test configurations
        if quick:
            configs = [
                ("Baseline (1 user)", 1, 5),
                ("Light load (3 users)", 3, 3),
                ("Medium load (5 users)", 5, 3),
            ]
        else:
            configs = [
                ("Baseline (1 user)", 1, 20),
                ("Light load (2 users)", 2, 10),
                ("Light load (3 users)", 3, 10),
                ("Medium load (5 users)", 5, 10),
                ("Medium load (7 users)", 7, 8),
                ("Heavy load (10 users)", 10, 5),
                ("Stress test (15 users)", 15, 3),
            ]

        for name, users, requests in configs:
            print(f"\n[{name}]")
            print(f"  Users: {users}, Requests/user: {requests}")

            start = time.perf_counter()
            raw_results = await self.run_concurrent_test(users, requests)
            duration = time.perf_counter() - start

            result = self.analyze_results(name, users, raw_results, duration)
            results.append(result)

            print(f"  Success rate: {result.successful_requests}/{result.total_requests}")
            print(f"  TTFT P90: {result.ttft_p90_ms:.2f}ms")
            print(f"  Latency P90: {result.latency_p90_ms:.2f}ms")
            print(f"  TPS mean: {result.tokens_per_second_mean:.1f}")

        suite = BenchmarkSuite(
            timestamp=datetime.now().isoformat(),
            host=self.host,
            results=results,
            hardware_info=hardware_info
        )

        # Print summary
        print("\n" + "=" * 60)
        print("BENCHMARK SUMMARY")
        print("=" * 60)

        print(f"\n{'Scenario':<25} {'Users':>6} {'TTFT P90':>10} {'Latency P90':>12} {'TPS':>8}")
        print("-" * 65)
        for r in results:
            print(f"{r.name:<25} {r.concurrent_users:>6} "
                  f"{r.ttft_p90_ms:>9.1f}ms {r.latency_p90_ms:>11.1f}ms "
                  f"{r.tokens_per_second_mean:>8.1f}")

        # Save results
        if self.output_dir:
            self.save_results(suite)

        return suite

    def save_results(self, suite: BenchmarkSuite):
        """Save results to JSON"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filepath = os.path.join(self.output_dir, f"benchmark_{timestamp}.json")

        output = {
            "timestamp": suite.timestamp,
            "host": suite.host,
            "hardware_info": suite.hardware_info,
            "results": [asdict(r) for r in suite.results]
        }

        with open(filepath, 'w') as f:
            json.dump(output, f, indent=2)

        print(f"\nResults saved to: {filepath}")


async def main():
    parser = argparse.ArgumentParser(
        description="Forge Cognition Inference Benchmark Suite"
    )
    parser.add_argument(
        '--host',
        type=str,
        default='http://localhost:8000',
        help='Inference server URL (default: http://localhost:8000)'
    )
    parser.add_argument(
        '--output', '-o',
        type=str,
        default=None,
        help='Output directory for results'
    )
    parser.add_argument(
        '--quick', '-q',
        action='store_true',
        help='Run quick benchmark (fewer iterations)'
    )

    args = parser.parse_args()

    benchmark = InferenceBenchmark(args.host, args.output)

    # Check server health
    print("Checking server health...")
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{args.host}/health") as resp:
                if resp.status != 200:
                    print(f"Error: Server returned {resp.status}")
                    return
                data = await resp.json()
                if not data.get("model_loaded"):
                    print("Warning: Model not fully loaded")
    except Exception as e:
        print(f"Error connecting to server: {e}")
        return

    print("Server healthy, starting benchmarks...\n")
    await benchmark.run_suite(quick=args.quick)


if __name__ == "__main__":
    asyncio.run(main())

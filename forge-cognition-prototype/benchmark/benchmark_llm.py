#!/usr/bin/env python3
"""
Forge Cognition LLM Benchmark Suite
====================================
Measures key performance indicators for LLM inference:
- Time to First Token (TTFT)
- Throughput (tokens/second)
- Latency percentiles (P50, P90, P99)
- Concurrent session scaling

Usage:
    python benchmark_llm.py --endpoint http://triton-inference-server:8000
    python benchmark_llm.py --endpoint http://triton-inference-server:8000 --concurrency 1,2,4,8
"""

import argparse
import asyncio
import json
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from typing import List, Optional
import statistics

# Check for optional dependencies
try:
    import aiohttp
    AIOHTTP_AVAILABLE = True
except ImportError:
    AIOHTTP_AVAILABLE = False

try:
    import numpy as np
    NUMPY_AVAILABLE = True
except ImportError:
    NUMPY_AVAILABLE = False


@dataclass
class RequestResult:
    """Result from a single inference request."""
    prompt: str
    success: bool
    ttft_ms: float  # Time to first token in milliseconds
    total_latency_ms: float  # Total request time in milliseconds
    tokens_generated: int
    tokens_per_second: float
    error: Optional[str] = None


@dataclass
class BenchmarkResult:
    """Aggregated benchmark results for a concurrency level."""
    concurrency: int
    total_requests: int
    successful_requests: int
    failed_requests: int

    # TTFT metrics (milliseconds)
    ttft_min: float
    ttft_max: float
    ttft_mean: float
    ttft_p50: float
    ttft_p90: float
    ttft_p99: float

    # Latency metrics (milliseconds)
    latency_min: float
    latency_max: float
    latency_mean: float
    latency_p50: float
    latency_p90: float
    latency_p99: float

    # Throughput
    tokens_per_second_mean: float
    total_throughput: float

    # Timing
    test_duration_sec: float


def percentile(data: List[float], p: float) -> float:
    """Calculate percentile without numpy."""
    if not data:
        return 0.0
    sorted_data = sorted(data)
    k = (len(sorted_data) - 1) * (p / 100)
    f = int(k)
    c = f + 1 if f + 1 < len(sorted_data) else f
    return sorted_data[f] + (sorted_data[c] - sorted_data[f]) * (k - f)


class LLMBenchmark:
    """Benchmark suite for LLM inference servers."""

    def __init__(self, endpoint: str, model_name: str = "tensorrt_llm"):
        self.endpoint = endpoint.rstrip('/')
        self.model_name = model_name
        self.results: List[RequestResult] = []

    def _get_test_prompts(self, count: int) -> List[str]:
        """Generate test prompts."""
        base_prompts = [
            "What is predictive maintenance and how does it work?",
            "Explain the concept of machine learning in simple terms.",
            "How do neural networks process information?",
            "What are the benefits of edge computing for industrial applications?",
            "Describe the key components of a building automation system.",
            "What is the difference between supervised and unsupervised learning?",
            "How can AI improve energy efficiency in buildings?",
            "What are the main challenges in deploying AI at the edge?",
            "Explain the concept of digital twins in manufacturing.",
            "What is the role of sensors in IoT systems?",
        ]

        prompts = []
        for i in range(count):
            prompts.append(base_prompts[i % len(base_prompts)])
        return prompts

    async def _send_request(
        self,
        session: 'aiohttp.ClientSession',
        prompt: str,
        max_tokens: int = 100
    ) -> RequestResult:
        """Send a single inference request."""

        # Build request payload for Triton
        payload = {
            "text_input": prompt,
            "max_tokens": max_tokens,
            "temperature": 0.7,
            "top_p": 0.9,
        }

        start_time = time.perf_counter()
        first_token_time = None
        tokens_generated = 0
        error_msg = None

        try:
            url = f"{self.endpoint}/v2/models/{self.model_name}/generate"

            async with session.post(url, json=payload, timeout=aiohttp.ClientTimeout(total=120)) as response:
                if response.status != 200:
                    error_msg = f"HTTP {response.status}"
                    return RequestResult(
                        prompt=prompt[:50],
                        success=False,
                        ttft_ms=0,
                        total_latency_ms=0,
                        tokens_generated=0,
                        tokens_per_second=0,
                        error=error_msg
                    )

                # Handle streaming response
                async for chunk in response.content.iter_any():
                    if first_token_time is None:
                        first_token_time = time.perf_counter()
                    tokens_generated += 1

        except asyncio.TimeoutError:
            error_msg = "Request timeout"
        except Exception as e:
            error_msg = str(e)

        end_time = time.perf_counter()

        if error_msg:
            return RequestResult(
                prompt=prompt[:50],
                success=False,
                ttft_ms=0,
                total_latency_ms=(end_time - start_time) * 1000,
                tokens_generated=0,
                tokens_per_second=0,
                error=error_msg
            )

        ttft = (first_token_time - start_time) * 1000 if first_token_time else 0
        total_latency = (end_time - start_time) * 1000
        tps = tokens_generated / (total_latency / 1000) if total_latency > 0 else 0

        return RequestResult(
            prompt=prompt[:50],
            success=True,
            ttft_ms=ttft,
            total_latency_ms=total_latency,
            tokens_generated=tokens_generated,
            tokens_per_second=tps
        )

    async def _run_concurrent_requests(
        self,
        prompts: List[str],
        concurrency: int
    ) -> List[RequestResult]:
        """Run concurrent inference requests."""

        connector = aiohttp.TCPConnector(limit=concurrency)
        async with aiohttp.ClientSession(connector=connector) as session:
            tasks = [self._send_request(session, p) for p in prompts]
            results = await asyncio.gather(*tasks, return_exceptions=True)

        # Convert exceptions to failed results
        processed_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                processed_results.append(RequestResult(
                    prompt=prompts[i][:50],
                    success=False,
                    ttft_ms=0,
                    total_latency_ms=0,
                    tokens_generated=0,
                    tokens_per_second=0,
                    error=str(result)
                ))
            else:
                processed_results.append(result)

        return processed_results

    def _calculate_metrics(
        self,
        results: List[RequestResult],
        concurrency: int,
        duration: float
    ) -> BenchmarkResult:
        """Calculate aggregate metrics from results."""

        successful = [r for r in results if r.success]

        if not successful:
            return BenchmarkResult(
                concurrency=concurrency,
                total_requests=len(results),
                successful_requests=0,
                failed_requests=len(results),
                ttft_min=0, ttft_max=0, ttft_mean=0,
                ttft_p50=0, ttft_p90=0, ttft_p99=0,
                latency_min=0, latency_max=0, latency_mean=0,
                latency_p50=0, latency_p90=0, latency_p99=0,
                tokens_per_second_mean=0,
                total_throughput=0,
                test_duration_sec=duration
            )

        ttft_values = [r.ttft_ms for r in successful]
        latency_values = [r.total_latency_ms for r in successful]
        tps_values = [r.tokens_per_second for r in successful]
        total_tokens = sum(r.tokens_generated for r in successful)

        return BenchmarkResult(
            concurrency=concurrency,
            total_requests=len(results),
            successful_requests=len(successful),
            failed_requests=len(results) - len(successful),

            ttft_min=min(ttft_values),
            ttft_max=max(ttft_values),
            ttft_mean=statistics.mean(ttft_values),
            ttft_p50=percentile(ttft_values, 50),
            ttft_p90=percentile(ttft_values, 90),
            ttft_p99=percentile(ttft_values, 99),

            latency_min=min(latency_values),
            latency_max=max(latency_values),
            latency_mean=statistics.mean(latency_values),
            latency_p50=percentile(latency_values, 50),
            latency_p90=percentile(latency_values, 90),
            latency_p99=percentile(latency_values, 99),

            tokens_per_second_mean=statistics.mean(tps_values),
            total_throughput=total_tokens / duration if duration > 0 else 0,
            test_duration_sec=duration
        )

    def run_benchmark(
        self,
        concurrency_levels: List[int] = [1, 2, 4, 8],
        requests_per_level: int = 20
    ) -> List[BenchmarkResult]:
        """Run the complete benchmark suite."""

        if not AIOHTTP_AVAILABLE:
            print("ERROR: aiohttp is required. Install with: pip install aiohttp")
            return []

        print("=" * 70)
        print("  FORGE COGNITION LLM BENCHMARK")
        print("=" * 70)
        print(f"  Endpoint: {self.endpoint}")
        print(f"  Model: {self.model_name}")
        print(f"  Concurrency levels: {concurrency_levels}")
        print(f"  Requests per level: {requests_per_level}")
        print("=" * 70)
        print()

        all_results = []

        for concurrency in concurrency_levels:
            print(f"Running benchmark with concurrency={concurrency}...")

            prompts = self._get_test_prompts(requests_per_level)

            start_time = time.perf_counter()
            results = asyncio.run(self._run_concurrent_requests(prompts, concurrency))
            duration = time.perf_counter() - start_time

            metrics = self._calculate_metrics(results, concurrency, duration)
            all_results.append(metrics)

            # Print summary
            print(f"  Requests: {metrics.successful_requests}/{metrics.total_requests} successful")
            print(f"  TTFT:     P50={metrics.ttft_p50:.1f}ms  P90={metrics.ttft_p90:.1f}ms  P99={metrics.ttft_p99:.1f}ms")
            print(f"  Latency:  P50={metrics.latency_p50:.1f}ms  P90={metrics.latency_p90:.1f}ms  P99={metrics.latency_p99:.1f}ms")
            print(f"  Throughput: {metrics.total_throughput:.1f} tokens/sec")
            print()

        return all_results

    def save_results(self, results: List[BenchmarkResult], output_file: str):
        """Save benchmark results to JSON file."""

        output = {
            "metadata": {
                "endpoint": self.endpoint,
                "model": self.model_name,
                "timestamp": datetime.now().isoformat(),
            },
            "results": [asdict(r) for r in results]
        }

        with open(output_file, 'w') as f:
            json.dump(output, f, indent=2)

        print(f"Results saved to: {output_file}")

    def print_summary_table(self, results: List[BenchmarkResult]):
        """Print a formatted summary table."""

        print()
        print("=" * 90)
        print("  BENCHMARK SUMMARY")
        print("=" * 90)
        print()
        print(f"{'Concurrency':<12} {'Success':<10} {'TTFT P50':<12} {'TTFT P99':<12} {'Lat P50':<12} {'Throughput':<15}")
        print("-" * 90)

        for r in results:
            print(f"{r.concurrency:<12} {r.successful_requests}/{r.total_requests:<7} {r.ttft_p50:>8.1f}ms   {r.ttft_p99:>8.1f}ms   {r.latency_p50:>8.1f}ms   {r.total_throughput:>10.1f} tok/s")

        print("-" * 90)
        print()


def main():
    parser = argparse.ArgumentParser(description="Forge Cognition LLM Benchmark Suite")
    parser.add_argument("--endpoint", default="http://localhost:8000",
                        help="Triton server endpoint")
    parser.add_argument("--model", default="tensorrt_llm",
                        help="Model name")
    parser.add_argument("--concurrency", default="1,2,4,8",
                        help="Comma-separated concurrency levels")
    parser.add_argument("--requests", type=int, default=20,
                        help="Requests per concurrency level")
    parser.add_argument("--output", default="benchmark_results.json",
                        help="Output file for results")

    args = parser.parse_args()

    concurrency_levels = [int(x) for x in args.concurrency.split(",")]

    benchmark = LLMBenchmark(args.endpoint, args.model)
    results = benchmark.run_benchmark(concurrency_levels, args.requests)

    if results:
        benchmark.print_summary_table(results)
        benchmark.save_results(results, args.output)


if __name__ == "__main__":
    main()

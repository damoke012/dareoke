#!/usr/bin/env python3
"""
Honeywell Forge Cognition - Memory Profiler
Profiles GPU memory usage to determine concurrent session capacity

Key Metrics:
- Base model memory footprint
- Per-session memory overhead (KV cache)
- Memory growth rate under load
- Maximum concurrent sessions before OOM

Usage:
    python memory_profiler.py --host http://localhost:8000
    python memory_profiler.py --host http://localhost:8000 --max-sessions 20
"""

import argparse
import asyncio
import json
import os
import time
from dataclasses import dataclass
from datetime import datetime
from typing import List, Dict, Optional

import aiohttp


@dataclass
class MemoryProfile:
    """Memory profile at a given session count"""
    session_count: int
    memory_used_mb: float
    memory_total_mb: float
    memory_percent: float
    memory_delta_mb: float  # Change from previous
    timestamp: str


class MemoryProfiler:
    """Profile GPU memory usage vs concurrent sessions"""

    def __init__(self, host: str):
        self.host = host.rstrip('/')
        self.baseline_memory = 0.0
        self.profiles: List[MemoryProfile] = []
        self.active_sessions: List[str] = []

    async def get_gpu_memory(self) -> Dict:
        """Get current GPU memory from server"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.host}/v1/gpu/stats") as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        if data.get("gpus"):
                            gpu = data["gpus"][0]  # Primary GPU
                            return {
                                "used_mb": gpu.get("memory_used_gb", 0) * 1024,
                                "total_mb": gpu.get("memory_total_gb", 0) * 1024,
                                "percent": gpu.get("memory_percent", 0)
                            }
        except Exception as e:
            print(f"Error getting GPU memory: {e}")
        return {"used_mb": 0, "total_mb": 0, "percent": 0}

    async def create_session(self) -> Optional[str]:
        """Create a new inference session"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(f"{self.host}/v1/sessions") as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        return data.get("session_id")
                    elif resp.status == 503:
                        return None  # Max sessions reached
        except:
            pass
        return None

    async def close_session(self, session_id: str):
        """Close an inference session"""
        try:
            async with aiohttp.ClientSession() as session:
                await session.delete(f"{self.host}/v1/sessions/{session_id}")
        except:
            pass

    async def warm_session(self, session_id: str):
        """Make a request to warm up the session (allocate KV cache)"""
        try:
            async with aiohttp.ClientSession() as session:
                await session.post(
                    f"{self.host}/v1/chat",
                    json={
                        "prompt": "What is the maintenance status?",
                        "session_id": session_id,
                        "max_tokens": 100
                    },
                    timeout=aiohttp.ClientTimeout(total=30)
                )
        except:
            pass

    async def profile_sessions(self, max_sessions: int) -> List[MemoryProfile]:
        """Profile memory usage by incrementally adding sessions"""
        print("=" * 60)
        print("FORGE COGNITION MEMORY PROFILER")
        print("=" * 60)

        # Get baseline
        print("\nMeasuring baseline memory (no sessions)...")
        await asyncio.sleep(2)  # Let things settle
        baseline = await self.get_gpu_memory()
        self.baseline_memory = baseline["used_mb"]

        print(f"Baseline: {self.baseline_memory:.1f} MB / {baseline['total_mb']:.1f} MB "
              f"({baseline['percent']:.1f}%)")

        initial_profile = MemoryProfile(
            session_count=0,
            memory_used_mb=baseline["used_mb"],
            memory_total_mb=baseline["total_mb"],
            memory_percent=baseline["percent"],
            memory_delta_mb=0,
            timestamp=datetime.now().isoformat()
        )
        self.profiles.append(initial_profile)

        print(f"\nAdding sessions (max: {max_sessions})...")
        print("-" * 50)

        prev_memory = baseline["used_mb"]

        for i in range(1, max_sessions + 1):
            # Create session
            session_id = await self.create_session()
            if not session_id:
                print(f"Session {i}: Failed to create (max reached?)")
                break

            self.active_sessions.append(session_id)

            # Warm up session to allocate KV cache
            await self.warm_session(session_id)
            await asyncio.sleep(0.5)  # Let memory allocation settle

            # Measure memory
            mem = await self.get_gpu_memory()
            delta = mem["used_mb"] - prev_memory

            profile = MemoryProfile(
                session_count=i,
                memory_used_mb=mem["used_mb"],
                memory_total_mb=mem["total_mb"],
                memory_percent=mem["percent"],
                memory_delta_mb=delta,
                timestamp=datetime.now().isoformat()
            )
            self.profiles.append(profile)

            print(f"Sessions: {i:3d} | "
                  f"Memory: {mem['used_mb']:.1f} MB ({mem['percent']:.1f}%) | "
                  f"Delta: +{delta:.1f} MB")

            prev_memory = mem["used_mb"]

            # Stop if memory > 90%
            if mem["percent"] > 90:
                print(f"\n⚠️  Memory threshold reached ({mem['percent']:.1f}%), stopping")
                break

        # Clean up sessions
        print("\nCleaning up sessions...")
        for sid in self.active_sessions:
            await self.close_session(sid)
        self.active_sessions.clear()

        # Analysis
        self.print_analysis()

        return self.profiles

    def print_analysis(self):
        """Print memory analysis"""
        if len(self.profiles) < 2:
            print("Not enough data for analysis")
            return

        print("\n" + "=" * 60)
        print("MEMORY ANALYSIS")
        print("=" * 60)

        # Calculate per-session overhead
        deltas = [p.memory_delta_mb for p in self.profiles[1:] if p.memory_delta_mb > 0]
        if deltas:
            avg_per_session = sum(deltas) / len(deltas)
            print(f"\nAverage per-session overhead: {avg_per_session:.1f} MB")
        else:
            avg_per_session = 0

        # Estimate maximum sessions
        last_profile = self.profiles[-1]
        available = last_profile.memory_total_mb * 0.85  # 85% threshold
        model_memory = self.baseline_memory

        if avg_per_session > 0:
            max_sessions = int((available - model_memory) / avg_per_session)
            print(f"Estimated max sessions (85% threshold): {max_sessions}")

        # Memory efficiency
        total_session_memory = last_profile.memory_used_mb - self.baseline_memory
        print(f"\nTotal session memory: {total_session_memory:.1f} MB")
        print(f"Sessions created: {last_profile.session_count}")

        # Recommendations
        print("\n" + "-" * 50)
        print("RECOMMENDATIONS FOR FORGE COGNITION:")

        if avg_per_session > 0:
            # RTX 4000 Pro estimate (~20GB)
            rtx_sessions = int((20 * 1024 * 0.85 - model_memory) / avg_per_session)
            print(f"  RTX 4000 Pro (~20GB): ~{rtx_sessions} concurrent sessions")

            # Jetson Thor estimate (128GB unified - but shared with CPU)
            # Assume 80GB available for GPU
            thor_sessions = int((80 * 1024 * 0.85 - model_memory) / avg_per_session)
            print(f"  Jetson Thor (~80GB GPU): ~{thor_sessions} concurrent sessions")

    def save_results(self, output_path: str):
        """Save profiling results to JSON"""
        results = {
            "timestamp": datetime.now().isoformat(),
            "host": self.host,
            "baseline_memory_mb": self.baseline_memory,
            "profiles": [
                {
                    "session_count": p.session_count,
                    "memory_used_mb": p.memory_used_mb,
                    "memory_total_mb": p.memory_total_mb,
                    "memory_percent": p.memory_percent,
                    "memory_delta_mb": p.memory_delta_mb
                }
                for p in self.profiles
            ]
        }

        with open(output_path, 'w') as f:
            json.dump(results, f, indent=2)

        print(f"\nResults saved to: {output_path}")


async def main():
    parser = argparse.ArgumentParser(
        description="Forge Cognition GPU Memory Profiler"
    )
    parser.add_argument(
        '--host',
        type=str,
        default='http://localhost:8000',
        help='Inference server URL'
    )
    parser.add_argument(
        '--max-sessions',
        type=int,
        default=15,
        help='Maximum sessions to test (default: 15)'
    )
    parser.add_argument(
        '--output', '-o',
        type=str,
        default=None,
        help='Output file for results (JSON)'
    )

    args = parser.parse_args()

    profiler = MemoryProfiler(args.host)

    # Check server
    print("Checking server...")
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{args.host}/health") as resp:
                if resp.status != 200:
                    print(f"Server returned {resp.status}")
                    return
    except Exception as e:
        print(f"Cannot connect to server: {e}")
        return

    # Run profiler
    profiles = await profiler.profile_sessions(args.max_sessions)

    # Save if output specified
    if args.output:
        profiler.save_results(args.output)


if __name__ == "__main__":
    asyncio.run(main())

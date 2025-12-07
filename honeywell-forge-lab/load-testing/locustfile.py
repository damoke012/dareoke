"""
Honeywell Forge Cognition - Load Testing Framework
Simulates multiple concurrent users querying the inference server

Usage:
    # Web UI mode
    locust -f locustfile.py --host=http://localhost:8000

    # Headless mode (CI/CD)
    locust -f locustfile.py --host=http://localhost:8000 \
           --headless -u 10 -r 2 -t 60s \
           --csv=results/load_test

Scenarios:
    1. MaintenanceAssistUser - Simulates maintenance queries
    2. AssetEngineerUser - Simulates asset engineering conversations
    3. MixedWorkload - Combination of both user types
"""

import json
import random
import time
from locust import HttpUser, task, between, events
from locust.runners import MasterRunner

# ============================================================================
# Sample Prompts (Maintenance Assistant Domain)
# ============================================================================

MAINTENANCE_PROMPTS = [
    "What is the recommended maintenance schedule for HVAC unit AHU-001?",
    "Show me the fault history for chiller CH-003 in Building A",
    "What are the common causes of high discharge pressure in cooling towers?",
    "Generate a preventive maintenance checklist for elevator ELV-012",
    "What spare parts should be kept in stock for boiler BLR-005?",
    "Explain the troubleshooting steps for a VFD fault code E-015",
    "What is the expected lifespan of a centrifugal pump bearing?",
    "Show me the energy consumption trend for the past 30 days",
    "What maintenance tasks are overdue for Building B?",
    "Recommend optimization settings for the BAS control loop",
]

ASSET_ENGINEERING_PROMPTS = [
    "Compare the efficiency ratings of chillers CH-001, CH-002, and CH-003",
    "What is the total replacement cost for the HVAC system in Zone A?",
    "Generate a capital planning forecast for the next 5 years",
    "Analyze the lifecycle cost of upgrading to LED lighting",
    "What assets are approaching end-of-life in the next 12 months?",
    "Create an asset criticality ranking for the power distribution system",
    "What is the ROI for installing variable frequency drives on all pumps?",
    "Show me the maintenance cost breakdown by asset category",
    "Recommend energy efficiency improvements for the building envelope",
    "Generate a risk assessment for the fire suppression system",
]

# ============================================================================
# Metrics Collection
# ============================================================================

class MetricsCollector:
    def __init__(self):
        self.ttft_values = []
        self.tps_values = []
        self.latency_values = []

    def record(self, ttft_ms: float, tps: float, latency_ms: float):
        self.ttft_values.append(ttft_ms)
        self.tps_values.append(tps)
        self.latency_values.append(latency_ms)

    def get_percentile(self, values: list, percentile: float) -> float:
        if not values:
            return 0.0
        sorted_values = sorted(values)
        index = int(len(sorted_values) * percentile / 100)
        return sorted_values[min(index, len(sorted_values) - 1)]

    def summary(self) -> dict:
        return {
            "ttft": {
                "p50": self.get_percentile(self.ttft_values, 50),
                "p90": self.get_percentile(self.ttft_values, 90),
                "p99": self.get_percentile(self.ttft_values, 99),
                "mean": sum(self.ttft_values) / len(self.ttft_values) if self.ttft_values else 0
            },
            "tokens_per_second": {
                "p50": self.get_percentile(self.tps_values, 50),
                "p90": self.get_percentile(self.tps_values, 90),
                "mean": sum(self.tps_values) / len(self.tps_values) if self.tps_values else 0
            },
            "total_latency": {
                "p50": self.get_percentile(self.latency_values, 50),
                "p90": self.get_percentile(self.latency_values, 90),
                "p99": self.get_percentile(self.latency_values, 99),
                "mean": sum(self.latency_values) / len(self.latency_values) if self.latency_values else 0
            },
            "total_requests": len(self.latency_values)
        }

metrics = MetricsCollector()

# ============================================================================
# User Classes
# ============================================================================

class MaintenanceAssistUser(HttpUser):
    """
    Simulates a maintenance technician using the Maintenance Assistant.
    - Short, focused queries
    - Quick succession of questions
    - Session-based interactions
    """
    weight = 3  # 60% of users
    wait_time = between(2, 5)  # 2-5 seconds between requests

    def on_start(self):
        """Create a session when user starts"""
        response = self.client.post("/v1/sessions")
        if response.status_code == 200:
            self.session_id = response.json().get("session_id")
        else:
            self.session_id = None

    def on_stop(self):
        """Close session when user stops"""
        if self.session_id:
            self.client.delete(f"/v1/sessions/{self.session_id}")

    @task(10)
    def maintenance_query(self):
        """Standard maintenance query"""
        prompt = random.choice(MAINTENANCE_PROMPTS)

        with self.client.post(
            "/v1/chat",
            json={
                "prompt": prompt,
                "session_id": self.session_id,
                "max_tokens": 256,
                "temperature": 0.7
            },
            catch_response=True
        ) as response:
            if response.status_code == 200:
                data = response.json()
                ttft = data.get("metrics", {}).get("ttft_ms", 0)
                tps = data.get("metrics", {}).get("tokens_per_second", 0)
                latency = data.get("metrics", {}).get("total_latency_ms", 0)

                metrics.record(ttft, tps, latency)

                # Mark as failure if TTFT > 500ms (SLO violation)
                if ttft > 500:
                    response.failure(f"TTFT SLO violation: {ttft}ms > 500ms")
                else:
                    response.success()
            else:
                response.failure(f"Status code: {response.status_code}")

    @task(1)
    def check_health(self):
        """Periodic health check"""
        self.client.get("/health")


class AssetEngineerUser(HttpUser):
    """
    Simulates an asset engineer using AI Assisted Asset Engineering.
    - Longer, complex queries
    - More thoughtful pauses between questions
    - Multi-turn conversations
    """
    weight = 2  # 40% of users
    wait_time = between(5, 10)  # 5-10 seconds between requests

    def on_start(self):
        """Create a session when user starts"""
        response = self.client.post("/v1/sessions")
        if response.status_code == 200:
            self.session_id = response.json().get("session_id")
            self.conversation_history = []
        else:
            self.session_id = None
            self.conversation_history = []

    def on_stop(self):
        """Close session when user stops"""
        if self.session_id:
            self.client.delete(f"/v1/sessions/{self.session_id}")

    @task(10)
    def asset_query(self):
        """Complex asset engineering query"""
        prompt = random.choice(ASSET_ENGINEERING_PROMPTS)

        # Add context from previous turn (simulates multi-turn)
        if self.conversation_history:
            context = f"Following up on: {self.conversation_history[-1][:100]}... "
            prompt = context + prompt

        with self.client.post(
            "/v1/chat",
            json={
                "prompt": prompt,
                "session_id": self.session_id,
                "max_tokens": 512,  # Longer responses for engineering queries
                "temperature": 0.5  # More deterministic for analysis
            },
            catch_response=True
        ) as response:
            if response.status_code == 200:
                data = response.json()
                ttft = data.get("metrics", {}).get("ttft_ms", 0)
                tps = data.get("metrics", {}).get("tokens_per_second", 0)
                latency = data.get("metrics", {}).get("total_latency_ms", 0)

                metrics.record(ttft, tps, latency)

                # Store for context
                self.conversation_history.append(prompt)
                if len(self.conversation_history) > 3:
                    self.conversation_history.pop(0)

                # Mark as failure if TTFT > 750ms (different SLO for complex queries)
                if ttft > 750:
                    response.failure(f"TTFT SLO violation: {ttft}ms > 750ms")
                else:
                    response.success()
            else:
                response.failure(f"Status code: {response.status_code}")

    @task(1)
    def view_sessions(self):
        """Check active sessions"""
        self.client.get("/v1/sessions")


# ============================================================================
# Event Handlers
# ============================================================================

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Print metrics summary when test ends"""
    if not isinstance(environment.runner, MasterRunner):
        summary = metrics.summary()
        print("\n" + "=" * 60)
        print("FORGE COGNITION LOAD TEST SUMMARY")
        print("=" * 60)
        print(f"\nTotal Requests: {summary['total_requests']}")
        print(f"\nTime to First Token (TTFT):")
        print(f"  P50: {summary['ttft']['p50']:.2f}ms")
        print(f"  P90: {summary['ttft']['p90']:.2f}ms")
        print(f"  P99: {summary['ttft']['p99']:.2f}ms")
        print(f"  Mean: {summary['ttft']['mean']:.2f}ms")
        print(f"\nTokens Per Second:")
        print(f"  P50: {summary['tokens_per_second']['p50']:.2f}")
        print(f"  P90: {summary['tokens_per_second']['p90']:.2f}")
        print(f"  Mean: {summary['tokens_per_second']['mean']:.2f}")
        print(f"\nTotal Latency:")
        print(f"  P50: {summary['total_latency']['p50']:.2f}ms")
        print(f"  P90: {summary['total_latency']['p90']:.2f}ms")
        print(f"  P99: {summary['total_latency']['p99']:.2f}ms")
        print("=" * 60 + "\n")


# ============================================================================
# CLI Helper Scripts
# ============================================================================

if __name__ == "__main__":
    print("""
Forge Cognition Load Testing Framework

Quick Start:
    # Start inference server first
    cd ../inference-server && python server.py

    # Run load test with web UI
    locust -f locustfile.py --host=http://localhost:8000

    # Run headless (for CI/CD)
    locust -f locustfile.py --host=http://localhost:8000 \\
           --headless -u 10 -r 2 -t 60s

Scenarios:
    - MaintenanceAssistUser (60%): Quick maintenance queries
    - AssetEngineerUser (40%): Complex engineering analysis

Metrics Tracked:
    - Time to First Token (TTFT)
    - Tokens per Second (TPS)
    - Total Request Latency
    - SLO Violations
    """)

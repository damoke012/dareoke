"""
Honeywell Forge Cognition - Unified Inference Server
Supports both hardware SKUs with automatic detection and optimization:
  - SKU 1: Jetson AGX Thor (ARM64, 128GB unified memory)
  - SKU 2: RTX 4000 Pro (x86_64, ~20GB VRAM)

Key Features:
- Automatic SKU detection and configuration
- TensorRT-LLM optimized inference
- Concurrent session management with SKU-appropriate limits
- Real-time latency tracking
- GPU memory monitoring with SKU-specific thresholds
- Prometheus metrics export
"""

import asyncio
import os
import platform
import time
import uuid
from contextlib import asynccontextmanager
from typing import Dict, List, Optional
from dataclasses import dataclass, field
from pathlib import Path

import yaml
import numpy as np
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import pynvml
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response

# ============================================================================
# SKU Detection and Configuration
# ============================================================================

@dataclass
class SKUProfile:
    """Hardware profile for a specific SKU"""
    name: str
    description: str
    gpu_memory_gb: float
    gpu_memory_type: str
    max_concurrent_sessions: int
    max_batch_size: int
    kv_cache_gb: float
    quantization: str
    memory_warning_percent: float
    memory_critical_percent: float
    target_ttft_ms: float
    target_tps: float

@dataclass
class ServerConfig:
    model_name: str = "maintenance-assist"
    max_concurrent_sessions: int = 10
    max_tokens: int = 512
    temperature: float = 0.7
    gpu_memory_threshold: float = 0.85
    target_ttft_ms: float = 100.0
    target_tps: float = 50.0
    # SKU-specific
    sku_name: str = "unknown"
    sku_description: str = ""
    quantization: str = "FP16"

def detect_sku() -> str:
    """
    Detect which SKU we're running on based on:
    1. Architecture (ARM64 = Jetson, x86_64 = RTX)
    2. GPU name pattern matching
    """
    arch = platform.machine()

    # Check architecture first
    if arch in ("aarch64", "arm64"):
        return "jetson_thor"
    elif arch in ("x86_64", "AMD64"):
        # Could be RTX 4000 Pro or dev machine - check GPU
        try:
            pynvml.nvmlInit()
            handle = pynvml.nvmlDeviceGetHandleByIndex(0)
            gpu_name = pynvml.nvmlDeviceGetName(handle)
            if isinstance(gpu_name, bytes):
                gpu_name = gpu_name.decode('utf-8')
            pynvml.nvmlShutdown()

            if "RTX 4000" in gpu_name or "AD104" in gpu_name:
                return "rtx_4000_pro"
            else:
                return "generic"
        except Exception:
            return "generic"
    else:
        return "generic"

def load_sku_profiles(path: str = "sku_profiles.yaml") -> Dict:
    """Load SKU profiles from YAML"""
    try:
        with open(path, 'r') as f:
            return yaml.safe_load(f) or {}
    except FileNotFoundError:
        print(f"Warning: SKU profiles not found at {path}")
        return {}

def load_config(config_path: str = "config.yaml", profiles_path: str = "sku_profiles.yaml") -> ServerConfig:
    """
    Load configuration with SKU auto-detection.
    SKU-specific settings override base config.
    """
    # Load base config
    base_config = {}
    try:
        with open(config_path, 'r') as f:
            base_config = yaml.safe_load(f) or {}
    except FileNotFoundError:
        pass

    # Detect SKU
    auto_detect = os.environ.get("FORGE_SKU_AUTO_DETECT", "true").lower() == "true"
    sku_override = os.environ.get("FORGE_SKU")

    if sku_override:
        sku_name = sku_override
        print(f"SKU override: {sku_name}")
    elif auto_detect:
        sku_name = detect_sku()
        print(f"Auto-detected SKU: {sku_name}")
    else:
        sku_name = "generic"

    # Load SKU profiles and apply
    profiles = load_sku_profiles(profiles_path)
    sku_profile = profiles.get(sku_name, profiles.get("generic", {}))

    # Merge: base config < SKU defaults < environment overrides
    config_dict = {
        "model_name": base_config.get("model_name", "maintenance-assist"),
        "max_tokens": base_config.get("max_tokens", 512),
        "temperature": base_config.get("temperature", 0.7),
        "sku_name": sku_name,
        "sku_description": sku_profile.get("description", ""),
    }

    # Apply SKU-specific inference settings
    inference = sku_profile.get("inference", {})
    config_dict["max_concurrent_sessions"] = inference.get(
        "max_concurrent_sessions",
        base_config.get("max_concurrent_sessions", 10)
    )
    config_dict["quantization"] = inference.get("quantization", "FP16")

    # Apply SKU-specific thresholds
    thresholds = sku_profile.get("thresholds", {})
    config_dict["gpu_memory_threshold"] = thresholds.get(
        "memory_critical_percent", 85
    ) / 100.0
    config_dict["target_ttft_ms"] = thresholds.get("target_ttft_ms", 100.0)
    config_dict["target_tps"] = thresholds.get("target_tps", 50.0)

    print(f"Configuration loaded for SKU: {sku_name}")
    print(f"  Max concurrent sessions: {config_dict['max_concurrent_sessions']}")
    print(f"  Memory threshold: {config_dict['gpu_memory_threshold']*100:.0f}%")
    print(f"  Target TTFT: {config_dict['target_ttft_ms']}ms")

    return ServerConfig(**config_dict)

config = load_config()

# ============================================================================
# Prometheus Metrics
# ============================================================================

# Counters
REQUEST_COUNT = Counter(
    'forge_inference_requests_total',
    'Total inference requests',
    ['status', 'model']
)

# Histograms
TTFT_HISTOGRAM = Histogram(
    'forge_ttft_seconds',
    'Time to First Token in seconds',
    ['model'],
    buckets=(0.01, 0.025, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3, 0.5, 1.0, 2.0)
)

TOKENS_PER_SECOND = Histogram(
    'forge_tokens_per_second',
    'Output tokens per second',
    ['model'],
    buckets=(10, 20, 30, 40, 50, 75, 100, 150, 200)
)

TOTAL_LATENCY = Histogram(
    'forge_total_latency_seconds',
    'Total request latency in seconds',
    ['model'],
    buckets=(0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0)
)

# Gauges
ACTIVE_SESSIONS = Gauge(
    'forge_active_sessions',
    'Number of active inference sessions'
)

GPU_MEMORY_USED = Gauge(
    'forge_gpu_memory_used_bytes',
    'GPU memory used in bytes',
    ['gpu_id']
)

GPU_MEMORY_TOTAL = Gauge(
    'forge_gpu_memory_total_bytes',
    'GPU memory total in bytes',
    ['gpu_id']
)

GPU_UTILIZATION = Gauge(
    'forge_gpu_utilization_percent',
    'GPU utilization percentage',
    ['gpu_id']
)

# ============================================================================
# GPU Monitoring
# ============================================================================

class GPUMonitor:
    def __init__(self):
        self.initialized = False
        try:
            pynvml.nvmlInit()
            self.device_count = pynvml.nvmlDeviceGetCount()
            self.handles = [pynvml.nvmlDeviceGetHandleByIndex(i) for i in range(self.device_count)]
            self.initialized = True
        except Exception as e:
            print(f"Warning: Could not initialize NVML: {e}")
            self.device_count = 0
            self.handles = []

    def get_gpu_stats(self) -> List[Dict]:
        if not self.initialized:
            return []

        stats = []
        for i, handle in enumerate(self.handles):
            try:
                mem_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
                util = pynvml.nvmlDeviceGetUtilizationRates(handle)

                stat = {
                    "gpu_id": i,
                    "memory_used_gb": mem_info.used / (1024**3),
                    "memory_total_gb": mem_info.total / (1024**3),
                    "memory_percent": (mem_info.used / mem_info.total) * 100,
                    "gpu_utilization": util.gpu,
                    "memory_utilization": util.memory
                }
                stats.append(stat)

                # Update Prometheus gauges
                GPU_MEMORY_USED.labels(gpu_id=str(i)).set(mem_info.used)
                GPU_MEMORY_TOTAL.labels(gpu_id=str(i)).set(mem_info.total)
                GPU_UTILIZATION.labels(gpu_id=str(i)).set(util.gpu)

            except Exception as e:
                print(f"Error getting stats for GPU {i}: {e}")

        return stats

    def shutdown(self):
        if self.initialized:
            pynvml.nvmlShutdown()

gpu_monitor = GPUMonitor()

# ============================================================================
# Session Management (Simulates concurrent users)
# ============================================================================

@dataclass
class InferenceSession:
    session_id: str
    created_at: float
    last_request: float
    request_count: int = 0
    total_tokens: int = 0
    avg_latency_ms: float = 0.0

class SessionManager:
    def __init__(self, max_sessions: int):
        self.max_sessions = max_sessions
        self.sessions: Dict[str, InferenceSession] = {}
        self._lock = asyncio.Lock()

    async def create_session(self) -> str:
        async with self._lock:
            if len(self.sessions) >= self.max_sessions:
                raise HTTPException(
                    status_code=503,
                    detail=f"Max concurrent sessions ({self.max_sessions}) reached"
                )

            session_id = str(uuid.uuid4())[:8]
            now = time.time()
            self.sessions[session_id] = InferenceSession(
                session_id=session_id,
                created_at=now,
                last_request=now
            )
            ACTIVE_SESSIONS.set(len(self.sessions))
            return session_id

    async def get_session(self, session_id: str) -> InferenceSession:
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")
        return self.sessions[session_id]

    async def update_session(self, session_id: str, tokens: int, latency_ms: float):
        async with self._lock:
            if session_id in self.sessions:
                session = self.sessions[session_id]
                session.last_request = time.time()
                session.request_count += 1
                session.total_tokens += tokens
                # Running average
                session.avg_latency_ms = (
                    (session.avg_latency_ms * (session.request_count - 1) + latency_ms)
                    / session.request_count
                )

    async def close_session(self, session_id: str):
        async with self._lock:
            if session_id in self.sessions:
                del self.sessions[session_id]
                ACTIVE_SESSIONS.set(len(self.sessions))

    async def get_all_sessions(self) -> List[InferenceSession]:
        return list(self.sessions.values())

    async def cleanup_stale_sessions(self, max_idle_seconds: int = 300):
        """Remove sessions idle for more than max_idle_seconds"""
        async with self._lock:
            now = time.time()
            stale = [
                sid for sid, s in self.sessions.items()
                if now - s.last_request > max_idle_seconds
            ]
            for sid in stale:
                del self.sessions[sid]
            if stale:
                ACTIVE_SESSIONS.set(len(self.sessions))
                print(f"Cleaned up {len(stale)} stale sessions")

session_manager = SessionManager(config.max_concurrent_sessions)

# ============================================================================
# Inference Engine (Simulated for prototype)
# ============================================================================

class InferenceEngine:
    """
    Simulated inference engine for prototype.
    In production, this would wrap TensorRT-LLM.
    """

    def __init__(self, model_name: str):
        self.model_name = model_name
        self.loaded = False
        self._base_latency_ms = 50  # Base processing time
        self._token_latency_ms = 10  # Per-token generation time

    async def load_model(self):
        """Simulate model loading"""
        print(f"Loading model: {self.model_name}")
        await asyncio.sleep(2)  # Simulate load time
        self.loaded = True
        print(f"Model loaded: {self.model_name}")

    async def generate(
        self,
        prompt: str,
        max_tokens: int = 256,
        temperature: float = 0.7
    ) -> Dict:
        """
        Simulate inference with realistic latency patterns.
        Adds load-based latency to simulate contention.
        """
        if not self.loaded:
            raise HTTPException(status_code=503, detail="Model not loaded")

        start_time = time.perf_counter()

        # Simulate compute based on input length and active sessions
        input_tokens = len(prompt.split()) * 1.3  # Rough token estimate
        active_count = len(session_manager.sessions)

        # TTFT simulation (increases with load)
        load_factor = 1 + (active_count * 0.1)  # 10% increase per concurrent session
        ttft_ms = self._base_latency_ms * load_factor
        await asyncio.sleep(ttft_ms / 1000)

        ttft_time = time.perf_counter()
        ttft_actual = (ttft_time - start_time) * 1000

        # Token generation simulation
        output_tokens = min(max_tokens, int(input_tokens * 0.8) + 50)
        generation_time_ms = output_tokens * self._token_latency_ms * load_factor
        await asyncio.sleep(generation_time_ms / 1000)

        end_time = time.perf_counter()
        total_latency = (end_time - start_time) * 1000
        tokens_per_sec = output_tokens / ((end_time - ttft_time) if (end_time - ttft_time) > 0 else 1)

        # Simulated response
        response_text = f"[Simulated response for: {prompt[:50]}...] " + \
                       "This is a prototype response simulating the Maintenance Assistant. " * 5

        return {
            "text": response_text[:output_tokens * 4],  # Rough char estimate
            "input_tokens": int(input_tokens),
            "output_tokens": output_tokens,
            "ttft_ms": round(ttft_actual, 2),
            "total_latency_ms": round(total_latency, 2),
            "tokens_per_second": round(tokens_per_sec, 2),
            "model": self.model_name
        }

inference_engine = InferenceEngine(config.model_name)

# ============================================================================
# API Models
# ============================================================================

class ChatRequest(BaseModel):
    prompt: str
    session_id: Optional[str] = None
    max_tokens: int = 256
    temperature: float = 0.7

class ChatResponse(BaseModel):
    session_id: str
    response: str
    metrics: Dict

class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    active_sessions: int
    gpu_stats: List[Dict]
    sku: str
    sku_description: str

# ============================================================================
# FastAPI Application
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("Starting Forge Cognition Inference Server...")
    await inference_engine.load_model()

    # Start background cleanup task
    async def cleanup_loop():
        while True:
            await asyncio.sleep(60)
            await session_manager.cleanup_stale_sessions()

    cleanup_task = asyncio.create_task(cleanup_loop())

    yield

    # Shutdown
    cleanup_task.cancel()
    gpu_monitor.shutdown()
    print("Inference server shutdown complete")

app = FastAPI(
    title="Forge Cognition Inference Server",
    description="Prototype LLM inference server for Honeywell Forge Cognition",
    version="0.1.0",
    lifespan=lifespan
)

# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint with GPU stats and SKU info"""
    return HealthResponse(
        status="healthy" if inference_engine.loaded else "loading",
        model_loaded=inference_engine.loaded,
        active_sessions=len(session_manager.sessions),
        gpu_stats=gpu_monitor.get_gpu_stats(),
        sku=config.sku_name,
        sku_description=config.sku_description
    )

@app.get("/v1/sku")
async def get_sku_info():
    """Get detailed SKU information and applied configuration"""
    return {
        "sku_name": config.sku_name,
        "sku_description": config.sku_description,
        "architecture": platform.machine(),
        "applied_config": {
            "max_concurrent_sessions": config.max_concurrent_sessions,
            "gpu_memory_threshold": config.gpu_memory_threshold,
            "target_ttft_ms": config.target_ttft_ms,
            "target_tps": config.target_tps,
            "quantization": config.quantization,
        },
        "gpu_info": gpu_monitor.get_gpu_stats()
    }

@app.post("/v1/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Main inference endpoint.
    Handles session management and tracks metrics.
    """
    # Create or get session
    if request.session_id:
        session = await session_manager.get_session(request.session_id)
        session_id = session.session_id
    else:
        session_id = await session_manager.create_session()

    try:
        # Run inference
        result = await inference_engine.generate(
            prompt=request.prompt,
            max_tokens=request.max_tokens,
            temperature=request.temperature
        )

        # Record metrics
        TTFT_HISTOGRAM.labels(model=config.model_name).observe(result["ttft_ms"] / 1000)
        TOKENS_PER_SECOND.labels(model=config.model_name).observe(result["tokens_per_second"])
        TOTAL_LATENCY.labels(model=config.model_name).observe(result["total_latency_ms"] / 1000)
        REQUEST_COUNT.labels(status="success", model=config.model_name).inc()

        # Update session stats
        await session_manager.update_session(
            session_id,
            result["output_tokens"],
            result["total_latency_ms"]
        )

        return ChatResponse(
            session_id=session_id,
            response=result["text"],
            metrics={
                "ttft_ms": result["ttft_ms"],
                "total_latency_ms": result["total_latency_ms"],
                "tokens_per_second": result["tokens_per_second"],
                "input_tokens": result["input_tokens"],
                "output_tokens": result["output_tokens"]
            }
        )

    except Exception as e:
        REQUEST_COUNT.labels(status="error", model=config.model_name).inc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/sessions")
async def create_session():
    """Create a new inference session"""
    session_id = await session_manager.create_session()
    return {"session_id": session_id}

@app.delete("/v1/sessions/{session_id}")
async def close_session(session_id: str):
    """Close an inference session"""
    await session_manager.close_session(session_id)
    return {"status": "closed", "session_id": session_id}

@app.get("/v1/sessions")
async def list_sessions():
    """List all active sessions"""
    sessions = await session_manager.get_all_sessions()
    return {
        "count": len(sessions),
        "max_sessions": config.max_concurrent_sessions,
        "sessions": [
            {
                "session_id": s.session_id,
                "request_count": s.request_count,
                "total_tokens": s.total_tokens,
                "avg_latency_ms": round(s.avg_latency_ms, 2)
            }
            for s in sessions
        ]
    }

@app.get("/v1/gpu/stats")
async def gpu_stats():
    """Get current GPU statistics"""
    return {
        "gpu_count": gpu_monitor.device_count,
        "gpus": gpu_monitor.get_gpu_stats()
    }

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    # Update GPU metrics before returning
    gpu_monitor.get_gpu_stats()
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )

@app.get("/v1/config")
async def get_config():
    """Get current server configuration"""
    return {
        "model_name": config.model_name,
        "max_concurrent_sessions": config.max_concurrent_sessions,
        "max_tokens": config.max_tokens,
        "target_ttft_ms": config.target_ttft_ms,
        "target_tps": config.target_tps,
        "gpu_memory_threshold": config.gpu_memory_threshold
    }

# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )

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
class TensorRTLLMConfig:
    """TensorRT-LLM specific performance settings"""
    kv_cache_dtype: str = "fp16"
    kv_cache_free_gpu_memory_fraction: float = 0.85
    enable_chunked_context: bool = True
    max_num_tokens: int = 4096
    use_paged_kv_cache: bool = True
    tokens_per_block: int = 64
    scheduler_policy: str = "max_utilization"
    enable_kv_cache_reuse: bool = True
    gpu_memory_utilization: float = 0.90
    streaming: bool = True
    streaming_interval: int = 1

@dataclass
class ServerConfig:
    model_name: str = "maintenance-assist"
    max_concurrent_sessions: int = 10
    max_tokens: int = 512
    temperature: float = 0.7
    gpu_memory_threshold: float = 0.85
    target_ttft_ms: float = 100.0
    target_ttft_p99_ms: float = 2000.0
    target_tps: float = 50.0
    max_queue_depth: int = 10
    # SKU-specific
    sku_name: str = "unknown"
    sku_description: str = ""
    quantization: str = "FP16"
    # TensorRT-LLM settings
    tensorrt_llm: TensorRTLLMConfig = field(default_factory=TensorRTLLMConfig)

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
            elif "Tesla P40" in gpu_name or "P40" in gpu_name:
                return "tesla_p40"
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
    config_dict["target_ttft_p99_ms"] = thresholds.get("target_ttft_p99_ms", 2000.0)
    config_dict["target_tps"] = thresholds.get("target_tps", 50.0)
    config_dict["max_queue_depth"] = thresholds.get("max_queue_depth", 10)

    # Apply TensorRT-LLM specific settings
    trtllm_settings = sku_profile.get("tensorrt_llm", {})
    config_dict["tensorrt_llm"] = TensorRTLLMConfig(
        kv_cache_dtype=trtllm_settings.get("kv_cache_dtype", "fp16"),
        kv_cache_free_gpu_memory_fraction=trtllm_settings.get("kv_cache_free_gpu_memory_fraction", 0.85),
        enable_chunked_context=trtllm_settings.get("enable_chunked_context", True),
        max_num_tokens=trtllm_settings.get("max_num_tokens", 4096),
        use_paged_kv_cache=trtllm_settings.get("use_paged_kv_cache", True),
        tokens_per_block=trtllm_settings.get("tokens_per_block", 64),
        scheduler_policy=trtllm_settings.get("scheduler_policy", "max_utilization"),
        enable_kv_cache_reuse=trtllm_settings.get("enable_kv_cache_reuse", True),
        gpu_memory_utilization=trtllm_settings.get("gpu_memory_utilization", 0.90),
        streaming=trtllm_settings.get("streaming", True),
        streaming_interval=trtllm_settings.get("streaming_interval", 1),
    )

    print(f"Configuration loaded for SKU: {sku_name}")
    print(f"  Max concurrent sessions: {config_dict['max_concurrent_sessions']}")
    print(f"  Memory threshold: {config_dict['gpu_memory_threshold']*100:.0f}%")
    print(f"  Target TTFT: {config_dict['target_ttft_ms']}ms (P99: {config_dict['target_ttft_p99_ms']}ms)")
    print(f"  KV Cache dtype: {config_dict['tensorrt_llm'].kv_cache_dtype}")
    print(f"  Paged KV Cache: {config_dict['tensorrt_llm'].use_paged_kv_cache}")
    print(f"  Scheduler: {config_dict['tensorrt_llm'].scheduler_policy}")

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

MAX_SESSIONS = Gauge(
    'forge_max_sessions',
    'Maximum allowed concurrent sessions'
)

QUEUE_DEPTH = Gauge(
    'forge_queue_depth',
    'Current request queue depth'
)

MAX_QUEUE_DEPTH = Gauge(
    'forge_max_queue_depth',
    'Maximum allowed queue depth before rejection'
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

# Performance target gauges (for Grafana thresholds)
TARGET_TTFT_MS = Gauge(
    'forge_target_ttft_ms',
    'Target TTFT in milliseconds'
)

TARGET_TTFT_P99_MS = Gauge(
    'forge_target_ttft_p99_ms',
    'Target P99 TTFT in milliseconds'
)

TARGET_TPS = Gauge(
    'forge_target_tps',
    'Target tokens per second'
)

# Thermal monitoring gauges
GPU_TEMPERATURE = Gauge(
    'forge_gpu_temperature_celsius',
    'GPU temperature in Celsius',
    ['gpu_id']
)

GPU_POWER_USAGE = Gauge(
    'forge_gpu_power_watts',
    'GPU power usage in Watts',
    ['gpu_id']
)

GPU_THERMAL_THROTTLE = Gauge(
    'forge_gpu_thermal_throttle',
    'GPU thermal throttling active (1=throttling, 0=normal)',
    ['gpu_id']
)

# ============================================================================
# Thermal Management Configuration
# ============================================================================

@dataclass
class ThermalConfig:
    """Thermal throttling thresholds and actions"""
    warning_temp_celsius: float = 75.0
    throttle_temp_celsius: float = 83.0
    critical_temp_celsius: float = 90.0
    polling_interval_seconds: float = 5.0
    # Actions
    reduce_batch_on_throttle: bool = True
    reduce_sessions_on_throttle: bool = True
    reject_on_critical: bool = True

thermal_config = ThermalConfig()

# ============================================================================
# GPU Monitoring
# ============================================================================

class GPUMonitor:
    def __init__(self):
        self.initialized = False
        self.thermal_state = {}  # Track thermal state per GPU
        try:
            pynvml.nvmlInit()
            self.device_count = pynvml.nvmlDeviceGetCount()
            self.handles = [pynvml.nvmlDeviceGetHandleByIndex(i) for i in range(self.device_count)]
            self.initialized = True
            # Initialize thermal state
            for i in range(self.device_count):
                self.thermal_state[i] = {
                    "is_throttling": False,
                    "is_critical": False,
                    "last_temp": 0.0
                }
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

                # Get thermal info
                try:
                    temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
                except Exception:
                    temp = 0

                # Get power info
                try:
                    power = pynvml.nvmlDeviceGetPowerUsage(handle) / 1000.0  # mW to W
                except Exception:
                    power = 0

                # Determine thermal state
                is_throttling = temp >= thermal_config.throttle_temp_celsius
                is_critical = temp >= thermal_config.critical_temp_celsius
                is_warning = temp >= thermal_config.warning_temp_celsius

                # Update thermal state tracking
                self.thermal_state[i] = {
                    "is_throttling": is_throttling,
                    "is_critical": is_critical,
                    "is_warning": is_warning,
                    "last_temp": temp
                }

                stat = {
                    "gpu_id": i,
                    "memory_used_gb": mem_info.used / (1024**3),
                    "memory_total_gb": mem_info.total / (1024**3),
                    "memory_percent": (mem_info.used / mem_info.total) * 100,
                    "gpu_utilization": util.gpu,
                    "memory_utilization": util.memory,
                    # Thermal stats
                    "temperature_celsius": temp,
                    "power_watts": power,
                    "thermal_state": "critical" if is_critical else "throttling" if is_throttling else "warning" if is_warning else "normal"
                }
                stats.append(stat)

                # Update Prometheus gauges
                GPU_MEMORY_USED.labels(gpu_id=str(i)).set(mem_info.used)
                GPU_MEMORY_TOTAL.labels(gpu_id=str(i)).set(mem_info.total)
                GPU_UTILIZATION.labels(gpu_id=str(i)).set(util.gpu)
                GPU_TEMPERATURE.labels(gpu_id=str(i)).set(temp)
                GPU_POWER_USAGE.labels(gpu_id=str(i)).set(power)
                GPU_THERMAL_THROTTLE.labels(gpu_id=str(i)).set(1 if is_throttling else 0)

            except Exception as e:
                print(f"Error getting stats for GPU {i}: {e}")

        return stats

    def is_any_gpu_throttling(self) -> bool:
        """Check if any GPU is in thermal throttling state"""
        return any(state.get("is_throttling", False) for state in self.thermal_state.values())

    def is_any_gpu_critical(self) -> bool:
        """Check if any GPU is in critical thermal state"""
        return any(state.get("is_critical", False) for state in self.thermal_state.values())

    def get_thermal_summary(self) -> Dict:
        """Get summary of thermal state across all GPUs"""
        if not self.initialized:
            return {"status": "unknown", "gpus": []}

        return {
            "status": "critical" if self.is_any_gpu_critical() else "throttling" if self.is_any_gpu_throttling() else "normal",
            "any_throttling": self.is_any_gpu_throttling(),
            "any_critical": self.is_any_gpu_critical(),
            "thresholds": {
                "warning_celsius": thermal_config.warning_temp_celsius,
                "throttle_celsius": thermal_config.throttle_temp_celsius,
                "critical_celsius": thermal_config.critical_temp_celsius
            },
            "gpus": [
                {
                    "gpu_id": i,
                    "temperature": state.get("last_temp", 0),
                    "state": "critical" if state.get("is_critical") else "throttling" if state.get("is_throttling") else "warning" if state.get("is_warning") else "normal"
                }
                for i, state in self.thermal_state.items()
            ]
        }

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
    print(f"SKU: {config.sku_name}")
    print(f"TensorRT-LLM KV Cache: {config.tensorrt_llm.kv_cache_dtype}")

    # Set initial gauge values for Grafana thresholds
    MAX_SESSIONS.set(config.max_concurrent_sessions)
    MAX_QUEUE_DEPTH.set(config.max_queue_depth)
    TARGET_TTFT_MS.set(config.target_ttft_ms)
    TARGET_TTFT_P99_MS.set(config.target_ttft_p99_ms)
    TARGET_TPS.set(config.target_tps)
    ACTIVE_SESSIONS.set(0)
    QUEUE_DEPTH.set(0)

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

@app.get("/v1/gpu/thermal")
async def gpu_thermal():
    """
    Get GPU thermal status and throttling information.
    Per kickoff slides: "Maximum achievable concurrency and parallelism will
    depend on the hardware's thermal throttling limits"
    """
    # Refresh stats
    gpu_monitor.get_gpu_stats()

    thermal_summary = gpu_monitor.get_thermal_summary()

    # Add recommendations based on thermal state
    recommendations = []
    if thermal_summary.get("any_critical"):
        recommendations.append("CRITICAL: Reject new requests, allow current to complete")
        recommendations.append("Check cooling system and ambient temperature")
    elif thermal_summary.get("any_throttling"):
        recommendations.append("Reduce max_concurrent_sessions temporarily")
        recommendations.append("Reduce batch size for new requests")
        recommendations.append("Monitor for sustained throttling")
    elif any(gpu.get("state") == "warning" for gpu in thermal_summary.get("gpus", [])):
        recommendations.append("Approaching thermal limits, monitor closely")

    return {
        **thermal_summary,
        "recommendations": recommendations,
        "actions_configured": {
            "reduce_batch_on_throttle": thermal_config.reduce_batch_on_throttle,
            "reduce_sessions_on_throttle": thermal_config.reduce_sessions_on_throttle,
            "reject_on_critical": thermal_config.reject_on_critical
        }
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
        "target_ttft_p99_ms": config.target_ttft_p99_ms,
        "target_tps": config.target_tps,
        "max_queue_depth": config.max_queue_depth,
        "gpu_memory_threshold": config.gpu_memory_threshold,
        "quantization": config.quantization,
    }

@app.get("/v1/tensorrt-llm/config")
async def get_tensorrt_llm_config():
    """
    Get TensorRT-LLM specific performance settings.
    These are the settings that would be passed to TensorRT-LLM at runtime.
    """
    trtllm = config.tensorrt_llm
    return {
        "sku": config.sku_name,
        "description": "TensorRT-LLM runtime configuration for this SKU",
        "kv_cache": {
            "dtype": trtllm.kv_cache_dtype,
            "free_gpu_memory_fraction": trtllm.kv_cache_free_gpu_memory_fraction,
            "use_paged_kv_cache": trtllm.use_paged_kv_cache,
            "tokens_per_block": trtllm.tokens_per_block,
            "enable_reuse": trtllm.enable_kv_cache_reuse,
        },
        "batching": {
            "enable_chunked_context": trtllm.enable_chunked_context,
            "max_num_tokens": trtllm.max_num_tokens,
        },
        "scheduling": {
            "policy": trtllm.scheduler_policy,
        },
        "memory": {
            "gpu_memory_utilization": trtllm.gpu_memory_utilization,
        },
        "streaming": {
            "enabled": trtllm.streaming,
            "interval": trtllm.streaming_interval,
        },
        "performance_impact": {
            "kv_cache_dtype_note": "FP8 uses 4x less memory than FP32 (45GB → 11GB for 20k context)",
            "paged_attention_note": "Reduces memory fragmentation, enables dynamic allocation",
            "chunked_context_note": "Better for long contexts (20k+ tokens)",
        }
    }

@app.get("/v1/performance/targets")
async def get_performance_targets():
    """Get performance targets for this SKU (for monitoring/alerting)"""
    return {
        "sku": config.sku_name,
        "latency": {
            "ttft_target_ms": config.target_ttft_ms,
            "ttft_p99_target_ms": config.target_ttft_p99_ms,
            "description": "Time to First Token targets"
        },
        "throughput": {
            "tokens_per_second_target": config.target_tps,
            "description": "Output token generation rate"
        },
        "capacity": {
            "max_concurrent_sessions": config.max_concurrent_sessions,
            "max_queue_depth": config.max_queue_depth,
            "description": "Request handling limits"
        },
        "memory": {
            "warning_threshold_percent": config.gpu_memory_threshold * 100 - 10,
            "critical_threshold_percent": config.gpu_memory_threshold * 100,
            "description": "GPU memory thresholds for alerting"
        }
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

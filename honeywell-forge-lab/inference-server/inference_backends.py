"""
Honeywell Forge Cognition - Inference Backend Abstraction
Supports multiple backends for flexibility:
  1. SimulatedBackend - No GPU, for API testing
  2. VLLMBackend - Real inference with vLLM (recommended for prototype)
  3. TensorRTLLMBackend - Production optimized (requires model conversion)
  4. OpenAICompatibleBackend - For testing with any OpenAI-compatible API

Usage:
    # Auto-select based on environment
    backend = create_inference_backend()

    # Force specific backend
    backend = create_inference_backend(backend_type="vllm")
"""

import asyncio
import os
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, Optional, AsyncIterator
import logging

logger = logging.getLogger(__name__)


@dataclass
class InferenceResult:
    """Standardized inference result across all backends"""
    text: str
    input_tokens: int
    output_tokens: int
    ttft_ms: float
    total_latency_ms: float
    tokens_per_second: float
    model: str
    backend: str


class InferenceBackend(ABC):
    """Abstract base class for inference backends"""

    @abstractmethod
    async def load_model(self) -> None:
        """Load the model into memory"""
        pass

    @abstractmethod
    async def generate(
        self,
        prompt: str,
        max_tokens: int = 256,
        temperature: float = 0.7,
        stream: bool = False
    ) -> InferenceResult:
        """Generate text from prompt"""
        pass

    @abstractmethod
    async def health_check(self) -> Dict:
        """Check backend health"""
        pass

    @property
    @abstractmethod
    def is_loaded(self) -> bool:
        """Check if model is loaded"""
        pass

    @property
    @abstractmethod
    def backend_name(self) -> str:
        """Return backend name"""
        pass


# =============================================================================
# Backend 1: Simulated (No GPU required)
# =============================================================================

class SimulatedBackend(InferenceBackend):
    """
    Simulated inference for testing without GPU.
    Useful for:
      - API structure testing
      - Load testing infrastructure
      - CI/CD pipeline validation
    """

    def __init__(self, model_name: str = "simulated-model"):
        self.model_name = model_name
        self._loaded = False
        self._base_latency_ms = 50
        self._token_latency_ms = 10

    async def load_model(self) -> None:
        logger.info(f"Loading simulated model: {self.model_name}")
        await asyncio.sleep(1)  # Simulate load time
        self._loaded = True
        logger.info("Simulated model loaded")

    async def generate(
        self,
        prompt: str,
        max_tokens: int = 256,
        temperature: float = 0.7,
        stream: bool = False
    ) -> InferenceResult:
        if not self._loaded:
            raise RuntimeError("Model not loaded")

        start_time = time.perf_counter()

        # Simulate TTFT
        await asyncio.sleep(self._base_latency_ms / 1000)
        ttft_time = time.perf_counter()
        ttft_ms = (ttft_time - start_time) * 1000

        # Simulate token generation
        input_tokens = len(prompt.split())
        output_tokens = min(max_tokens, input_tokens + 50)
        await asyncio.sleep((output_tokens * self._token_latency_ms) / 1000)

        end_time = time.perf_counter()
        total_latency_ms = (end_time - start_time) * 1000
        generation_time = end_time - ttft_time
        tps = output_tokens / generation_time if generation_time > 0 else 0

        response_text = f"[Simulated response] This is a test response for: {prompt[:100]}..."

        return InferenceResult(
            text=response_text,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            ttft_ms=round(ttft_ms, 2),
            total_latency_ms=round(total_latency_ms, 2),
            tokens_per_second=round(tps, 2),
            model=self.model_name,
            backend="simulated"
        )

    async def health_check(self) -> Dict:
        return {
            "backend": "simulated",
            "status": "healthy" if self._loaded else "not_loaded",
            "model": self.model_name
        }

    @property
    def is_loaded(self) -> bool:
        return self._loaded

    @property
    def backend_name(self) -> str:
        return "simulated"


# =============================================================================
# Backend 2: vLLM (Real GPU inference - recommended for prototype)
# =============================================================================

class VLLMBackend(InferenceBackend):
    """
    vLLM backend for real GPU inference.

    Requirements:
      - NVIDIA GPU with sufficient VRAM
      - vllm package installed
      - Model downloaded (HuggingFace or local)

    Recommended models for testing:
      - TinyLlama/TinyLlama-1.1B-Chat-v1.0 (1.1B, ~3GB VRAM)
      - microsoft/phi-2 (2.7B, ~6GB VRAM)
      - meta-llama/Llama-2-7b-chat-hf (7B, ~14GB VRAM)
    """

    def __init__(
        self,
        model_name: str = "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
        tensor_parallel_size: int = 1,
        gpu_memory_utilization: float = 0.85,
        max_model_len: int = 4096
    ):
        self.model_name = model_name
        self.tensor_parallel_size = tensor_parallel_size
        self.gpu_memory_utilization = gpu_memory_utilization
        self.max_model_len = max_model_len
        self._llm = None
        self._loaded = False

    async def load_model(self) -> None:
        logger.info(f"Loading vLLM model: {self.model_name}")

        try:
            from vllm import LLM, SamplingParams
            self._SamplingParams = SamplingParams

            # Load in executor to not block event loop
            loop = asyncio.get_event_loop()
            self._llm = await loop.run_in_executor(
                None,
                lambda: LLM(
                    model=self.model_name,
                    tensor_parallel_size=self.tensor_parallel_size,
                    gpu_memory_utilization=self.gpu_memory_utilization,
                    max_model_len=self.max_model_len,
                    trust_remote_code=True
                )
            )
            self._loaded = True
            logger.info(f"vLLM model loaded: {self.model_name}")

        except ImportError:
            raise RuntimeError("vLLM not installed. Run: pip install vllm")
        except Exception as e:
            logger.error(f"Failed to load vLLM model: {e}")
            raise

    async def generate(
        self,
        prompt: str,
        max_tokens: int = 256,
        temperature: float = 0.7,
        stream: bool = False
    ) -> InferenceResult:
        if not self._loaded or self._llm is None:
            raise RuntimeError("Model not loaded")

        start_time = time.perf_counter()

        sampling_params = self._SamplingParams(
            max_tokens=max_tokens,
            temperature=temperature
        )

        # Run inference in executor
        loop = asyncio.get_event_loop()
        outputs = await loop.run_in_executor(
            None,
            lambda: self._llm.generate([prompt], sampling_params)
        )

        end_time = time.perf_counter()

        output = outputs[0]
        generated_text = output.outputs[0].text

        # Calculate metrics
        input_tokens = len(output.prompt_token_ids)
        output_tokens = len(output.outputs[0].token_ids)
        total_latency_ms = (end_time - start_time) * 1000

        # Estimate TTFT (vLLM doesn't expose this directly in sync mode)
        # Approximate as latency / output_tokens * 1 token
        ttft_ms = total_latency_ms / output_tokens if output_tokens > 0 else total_latency_ms

        tps = output_tokens / (total_latency_ms / 1000) if total_latency_ms > 0 else 0

        return InferenceResult(
            text=generated_text,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            ttft_ms=round(ttft_ms, 2),
            total_latency_ms=round(total_latency_ms, 2),
            tokens_per_second=round(tps, 2),
            model=self.model_name,
            backend="vllm"
        )

    async def health_check(self) -> Dict:
        return {
            "backend": "vllm",
            "status": "healthy" if self._loaded else "not_loaded",
            "model": self.model_name,
            "tensor_parallel_size": self.tensor_parallel_size,
            "gpu_memory_utilization": self.gpu_memory_utilization
        }

    @property
    def is_loaded(self) -> bool:
        return self._loaded

    @property
    def backend_name(self) -> str:
        return "vllm"


# =============================================================================
# Backend 3: OpenAI-Compatible API (for external services)
# =============================================================================

class OpenAICompatibleBackend(InferenceBackend):
    """
    OpenAI-compatible API backend.
    Works with:
      - OpenAI API
      - Azure OpenAI
      - Local vLLM/TGI servers with OpenAI-compatible endpoints
      - Ollama with OpenAI compatibility

    Useful for testing when GPU is not available locally.
    """

    def __init__(
        self,
        base_url: str = "http://localhost:8080/v1",
        api_key: str = "dummy",
        model_name: str = "default"
    ):
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
        self.model_name = model_name
        self._loaded = False
        self._session = None

    async def load_model(self) -> None:
        import aiohttp
        self._session = aiohttp.ClientSession(
            headers={"Authorization": f"Bearer {self.api_key}"}
        )

        # Test connection
        try:
            async with self._session.get(f"{self.base_url}/models") as resp:
                if resp.status == 200:
                    self._loaded = True
                    logger.info(f"Connected to OpenAI-compatible API: {self.base_url}")
                else:
                    logger.warning(f"API returned status {resp.status}")
                    self._loaded = True  # Still mark as loaded, might work
        except Exception as e:
            logger.warning(f"Could not verify API connection: {e}")
            self._loaded = True  # Optimistically mark as loaded

    async def generate(
        self,
        prompt: str,
        max_tokens: int = 256,
        temperature: float = 0.7,
        stream: bool = False
    ) -> InferenceResult:
        if self._session is None:
            raise RuntimeError("Backend not initialized")

        start_time = time.perf_counter()

        payload = {
            "model": self.model_name,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": False
        }

        async with self._session.post(
            f"{self.base_url}/chat/completions",
            json=payload
        ) as resp:
            if resp.status != 200:
                error = await resp.text()
                raise RuntimeError(f"API error: {error}")

            data = await resp.json()

        end_time = time.perf_counter()

        # Extract response
        message = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})

        input_tokens = usage.get("prompt_tokens", len(prompt.split()))
        output_tokens = usage.get("completion_tokens", len(message.split()))
        total_latency_ms = (end_time - start_time) * 1000

        # Estimate TTFT
        ttft_ms = total_latency_ms * 0.1  # Rough estimate

        tps = output_tokens / (total_latency_ms / 1000) if total_latency_ms > 0 else 0

        return InferenceResult(
            text=message,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            ttft_ms=round(ttft_ms, 2),
            total_latency_ms=round(total_latency_ms, 2),
            tokens_per_second=round(tps, 2),
            model=self.model_name,
            backend="openai_compatible"
        )

    async def health_check(self) -> Dict:
        return {
            "backend": "openai_compatible",
            "status": "healthy" if self._loaded else "not_loaded",
            "base_url": self.base_url,
            "model": self.model_name
        }

    @property
    def is_loaded(self) -> bool:
        return self._loaded

    @property
    def backend_name(self) -> str:
        return "openai_compatible"

    async def close(self):
        if self._session:
            await self._session.close()


# =============================================================================
# Backend Factory
# =============================================================================

def create_inference_backend(
    backend_type: Optional[str] = None,
    **kwargs
) -> InferenceBackend:
    """
    Factory function to create inference backend.

    Args:
        backend_type: One of "simulated", "vllm", "openai_compatible"
                     If None, auto-selects based on environment
        **kwargs: Backend-specific configuration

    Returns:
        InferenceBackend instance
    """

    # Auto-detect backend type
    if backend_type is None:
        backend_type = os.environ.get("FORGE_INFERENCE_BACKEND", "auto")

    if backend_type == "auto":
        # Try to detect best available backend
        try:
            import torch
            if torch.cuda.is_available():
                try:
                    import vllm
                    backend_type = "vllm"
                    logger.info("Auto-selected vLLM backend (GPU available)")
                except ImportError:
                    backend_type = "simulated"
                    logger.info("Auto-selected simulated backend (vLLM not installed)")
            else:
                backend_type = "simulated"
                logger.info("Auto-selected simulated backend (no GPU)")
        except ImportError:
            backend_type = "simulated"
            logger.info("Auto-selected simulated backend (torch not available)")

    # Create backend
    if backend_type == "simulated":
        return SimulatedBackend(
            model_name=kwargs.get("model_name", "simulated-model")
        )

    elif backend_type == "vllm":
        return VLLMBackend(
            model_name=kwargs.get("model_name", "TinyLlama/TinyLlama-1.1B-Chat-v1.0"),
            tensor_parallel_size=kwargs.get("tensor_parallel_size", 1),
            gpu_memory_utilization=kwargs.get("gpu_memory_utilization", 0.85),
            max_model_len=kwargs.get("max_model_len", 4096)
        )

    elif backend_type == "openai_compatible":
        return OpenAICompatibleBackend(
            base_url=kwargs.get("base_url", "http://localhost:8080/v1"),
            api_key=kwargs.get("api_key", "dummy"),
            model_name=kwargs.get("model_name", "default")
        )

    else:
        raise ValueError(f"Unknown backend type: {backend_type}")


# =============================================================================
# Test
# =============================================================================

if __name__ == "__main__":
    import asyncio

    async def test_backend():
        # Test simulated backend
        backend = create_inference_backend("simulated")
        await backend.load_model()

        result = await backend.generate(
            prompt="What is the maintenance schedule for HVAC unit AHU-001?",
            max_tokens=100
        )

        print(f"Backend: {result.backend}")
        print(f"TTFT: {result.ttft_ms}ms")
        print(f"Total latency: {result.total_latency_ms}ms")
        print(f"TPS: {result.tokens_per_second}")
        print(f"Response: {result.text[:100]}...")

    asyncio.run(test_backend())

# Device Compatibility Matrix - Honeywell Forge Cognition

Last Updated: December 9, 2024

OVERVIEW

This document provides detailed compatibility information for the two target edge AI platforms:

  1. Jetson AGX Thor - ARM64 embedded platform with unified memory
  2. RTX Pro 4000 (Blackwell) - x86_64 discrete GPU workstation

Primary Inference Backend: TensorRT-LLM (confirmed by Quantiphi, Dec 9 2024)


ABBREVIATIONS AND TERMINOLOGY

  ARM64 (aarch64)     Advanced RISC Machine 64-bit architecture, used by Jetson
  x86_64              Intel/AMD 64-bit architecture, standard desktop/server CPUs
  SM                  Streaming Multiprocessor - NVIDIA GPU compute unit identifier
  VRAM                Video Random Access Memory - dedicated GPU memory
  TDP                 Thermal Design Power - maximum heat output in watts
  NVLink              NVIDIA high-speed GPU interconnect technology
  CUDA                Compute Unified Device Architecture - NVIDIA parallel computing platform
  cuDNN               CUDA Deep Neural Network library - optimized deep learning primitives
  TensorRT            NVIDIA inference optimizer and runtime engine
  TensorRT-LLM        TensorRT optimized for Large Language Models
  L4T                 Linux for Tegra - NVIDIA custom Linux for Jetson
  JetPack             NVIDIA SDK for Jetson including drivers, CUDA, TensorRT
  FP32                32-bit floating point (full precision)
  FP16                16-bit floating point (half precision)
  FP8                 8-bit floating point (quarter precision, 4x memory savings)
  BF16                Brain Float 16 - Google-developed 16-bit format
  INT8                8-bit integer quantization
  INT4                4-bit integer quantization (AWQ/GPTQ methods)
  KV Cache            Key-Value Cache - stores attention states for faster inference
  MHA                 Multi-Head Attention - transformer attention mechanism
  GQA                 Grouped Query Attention - memory-efficient attention variant
  MIG                 Multi-Instance GPU - hardware GPU partitioning (Ampere+)
  MPS                 Multi-Process Service - software GPU sharing
  TTFT                Time To First Token - latency until first output token
  TPS                 Tokens Per Second - inference throughput metric
  P99                 99th percentile latency - worst-case latency metric
  NGC                 NVIDIA GPU Cloud - container registry for GPU software
  GGUF                GPT-Generated Unified Format - llama.cpp model format
  AWQ                 Activation-aware Weight Quantization
  GPTQ                Post-Training Quantization for GPT models


================================================================================
DEVICE 1: NVIDIA JETSON AGX THOR
================================================================================

1.1 Hardware Specifications

Platform:               NVIDIA Jetson AGX Thor
                        Next-generation embedded AI compute module

Architecture:           ARM64 (aarch64)
                        Requires ARM64-specific binaries and container images

CPU:                    NVIDIA Custom ARM Cores
                        12+ high-performance cores expected

GPU:                    NVIDIA Thor GPU
                        Ampere-based architecture for AI inference

GPU Compute Capability: SM 8.7+
                        Ampere generation streaming multiprocessor
                        Note: Some TensorRT-LLM kernels missing for this SM version

Memory:                 128GB Unified
                        Shared between CPU and GPU (no separate VRAM)
                        Advantage: No memory copy between CPU/GPU
                        Disadvantage: Contention under heavy load

Memory Type:            LPDDR5X
                        Low-Power Double Data Rate 5X
                        High bandwidth, power efficient

Memory Bandwidth:       ~275 GB/s
                        Unified memory bus shared by CPU and GPU

TDP:                    15W - 100W
                        Thermal Design Power, configurable via nvpmodel
                        15W = Low power mode
                        50W = Balanced mode (default)
                        100W = Maximum performance

NVLink:                 Available
                        High-speed interconnect for multi-chip configurations
                        Enables tensor parallelism across multiple Thor modules

Form Factor:            Embedded Module
                        Designed for industrial and edge deployment
                        Requires carrier board and cooling solution


1.2 Software Stack - Jetson Thor

Operating System

JetPack SDK:            6.0 or higher (MANDATORY)
                        Complete software development kit from NVIDIA
                        Includes all drivers, CUDA, TensorRT in matched versions

L4T (Linux for Tegra):  36.x
                        NVIDIA custom Linux distribution for Jetson
                        Based on Ubuntu but with Tegra-specific kernel

Ubuntu Base:            22.04 LTS
                        Underlying distribution (Long Term Support)

Kernel:                 5.15 (Tegra)
                        NVIDIA custom kernel with Jetson-specific drivers

glibc:                  2.35+
                        GNU C Library, standard system library


NVIDIA Driver Stack

NVIDIA Driver:          Integrated with JetPack
                        Part of L4T, cannot be updated separately

CUDA Toolkit:           12.2
                        Included in JetPack 6.0
                        ARM64 build, not compatible with x86 CUDA

cuDNN:                  8.9.x
                        CUDA Deep Neural Network library
                        Optimized primitives for deep learning

TensorRT:               8.6.x
                        Inference optimizer and runtime
                        Included in JetPack, version locked

cuBLAS:                 12.2.x
                        CUDA Basic Linear Algebra Subroutines

cuSPARSE:               12.2.x
                        CUDA Sparse Matrix library

NCCL:                   2.18.x
                        NVIDIA Collective Communications Library
                        For multi-GPU communication


Inference Stack

TensorRT-LLM:           0.7.x or higher
                        MUST use ARM64 build from source or Jetson-specific branch
                        Standard pip package will NOT work
                        See CRITICAL ISSUES section below

Triton Inference Server: 24.01 or higher
                        Container: nvcr.io/nvidia/tritonserver:24.01-py3-igpu
                        Note the "-igpu" suffix for integrated GPU (Jetson)

PyTorch:                2.1 or higher (ARM64)
                        For model conversion if needed
                        Use NGC ARM64 container

Transformers:           4.35+
                        HuggingFace library for model loading

tokenizers:             0.15+
                        Fast tokenization library


Container Stack

Docker CE:              24.x
                        Or nvidia-docker runtime

containerd:             1.7.x
                        Container runtime used by K3s

nvidia-container-toolkit: 1.14.x or higher
                        Enables GPU access in containers

nvidia-container-runtime: 3.14.x
                        Runtime hook for GPU containers


Container Base Images for Jetson

TensorRT Base (Recommended):
  nvcr.io/nvidia/l4t-tensorrt:r36.2.0-devel

PyTorch Base:
  nvcr.io/nvidia/l4t-pytorch:r36.2.0-pth2.1

Triton Server:
  nvcr.io/nvidia/tritonserver:24.01-py3-igpu

CUDA Base:
  nvcr.io/nvidia/l4t-cuda:12.2.0-devel

MLC LLM (Recommended Alternative):
  dustynv/mlc:0.1.0-r36.2.0

llama.cpp:
  dustynv/llama_cpp:0.2.57-r36.2.0


1.3 TensorRT-LLM Feature Support - Jetson Thor

Quantization Support

FP32 Inference:         SUPPORTED
                        Full 32-bit precision, baseline accuracy
                        Highest memory usage

TF32 Inference:         SUPPORTED
                        Tensor Float 32, NVIDIA format
                        Same range as FP32, reduced precision

FP16 Inference:         SUPPORTED
                        Half precision, 2x memory savings vs FP32
                        Minimal accuracy loss for most models

BF16 Inference:         SUPPORTED
                        Brain Float 16, good for training
                        Same range as FP32

FP8 Inference:          SUPPORTED
                        Quarter precision, 4x memory savings vs FP32
                        Native support on Ampere architecture
                        Best for KV cache optimization

INT8 Inference:         SUPPORTED
                        8-bit integer quantization
                        Requires calibration for accuracy

INT4 (AWQ/GPTQ):        SUPPORTED
                        4-bit quantization methods
                        Maximum memory savings, some accuracy loss


TensorRT-LLM Features

Paged Attention:        SUPPORTED
                        Memory-efficient attention mechanism
                        Reduces memory fragmentation

In-flight Batching:     SUPPORTED
                        Dynamic batching of requests
                        Improves GPU utilization

KV Cache FP8:           SUPPORTED
                        8-bit key-value cache
                        4x memory savings for attention cache

KV Cache FP16:          SUPPORTED
                        16-bit key-value cache
                        Standard cache format

Chunked Context:        SUPPORTED
                        Process long contexts in chunks
                        Enables 20K+ token contexts

Speculative Decoding:   SUPPORTED
                        Use smaller model to predict tokens
                        Can speed up generation

Streaming Output:       SUPPORTED
                        Token-by-token output
                        Better user experience

Tensor Parallelism:     SUPPORTED (via NVLink)
                        Split model across multiple GPUs
                        Requires NVLink connection

Pipeline Parallelism:   SUPPORTED
                        Split model layers across GPUs

Grouped Query Attention: SUPPORTED
                        GQA models like Llama 2, Mistral
                        Memory-efficient attention


Memory Configuration - Jetson Thor

Total Unified Memory:   128GB
                        Shared between CPU and GPU

Recommended for Model:  80-90GB
                        Leave headroom for system and KV cache

KV Cache Allocation:    30-40GB
                        For 20 concurrent sessions with 20K context

System Reserve:         10-15GB
                        Operating system and background services

gpu_memory_utilization: 0.85 - 0.90
                        TensorRT-LLM memory limit setting


Recommended TensorRT-LLM Configuration - Jetson Thor

jetson_thor:
  tensorrt_llm:
    kv_cache_dtype: fp8                           # Use FP8 for 4x memory savings
    kv_cache_free_gpu_memory_fraction: 0.85       # 85% of memory for KV cache
    enable_chunked_context: true                  # Enable long context support
    max_num_tokens: 8192                          # Max tokens per batch
    use_paged_kv_cache: true                      # Enable paged attention
    tokens_per_block: 64                          # Block size for paging
    scheduler_policy: max_utilization             # Maximize GPU usage
    enable_kv_cache_reuse: true                   # Reuse cache for similar prompts
    gpu_memory_utilization: 0.90                  # 90% GPU memory limit
    max_batch_size: 16                            # Maximum batch size
    max_concurrent_sessions: 20                   # Target concurrent users


================================================================================
DEVICE 2: RTX PRO 4000 (BLACKWELL DGPU)
================================================================================

2.1 Hardware Specifications

Platform:               Workstation or Edge PC
                        Standard x86_64 system with PCIe GPU

Architecture:           x86_64
                        Intel/AMD 64-bit architecture
                        Standard binaries and containers work

GPU:                    NVIDIA RTX Pro 4000
                        Blackwell architecture (newest generation)
                        Professional workstation GPU

GPU Compute Capability: SM 9.0
                        Blackwell generation streaming multiprocessor
                        Full TensorRT-LLM kernel support

GPU Memory:             20GB GDDR6X
                        Dedicated VRAM (separate from system RAM)
                        CONSTRAINT: Model + KV cache must fit in 20GB

Memory Type:            GDDR6X
                        Graphics Double Data Rate 6X
                        High-speed discrete memory

Memory Bandwidth:       ~500 GB/s
                        Higher than Jetson due to dedicated memory bus

TDP:                    130W
                        Fixed thermal design power
                        Cannot be reduced like Jetson

NVLink:                 NOT AVAILABLE
                        Single GPU only
                        No tensor parallelism possible

Form Factor:            PCIe Card
                        Standard workstation GPU
                        Requires adequate power supply (650W+ PSU)


2.2 Software Stack - RTX Pro 4000

Operating System

Ubuntu:                 22.04 LTS (Recommended)
                        Long Term Support, stable

RHEL:                   8.x or 9.x
                        Red Hat Enterprise Linux for enterprise

Rocky Linux:            9.x
                        RHEL-compatible alternative

Kernel:                 5.15 or higher
                        Required for Blackwell GPU support

glibc:                  2.35+
                        Standard C library


NVIDIA Driver Stack

NVIDIA Driver:          545.x or higher (MINIMUM)
                        Recommended: 550.x or higher
                        Blackwell requires newest drivers

CUDA Toolkit:           12.3 or higher (MINIMUM)
                        Recommended: 12.4+
                        Blackwell-optimized CUDA

cuDNN:                  8.9.x or 9.0+
                        Deep learning primitives
                        Newer version has Blackwell optimizations

TensorRT:               9.0 or higher (MINIMUM)
                        Recommended: 9.2+
                        Blackwell-optimized inference

cuBLAS:                 12.3.x or 12.4.x
                        Linear algebra library

NCCL:                   2.19.x or 2.20.x
                        Collective communications


Inference Stack

TensorRT-LLM:           0.8.x or higher
                        Standard x86 build from NGC or pip
                        Blackwell-optimized kernels available

Triton Inference Server: 24.01 or higher
                        Container: nvcr.io/nvidia/tritonserver:24.01-py3
                        Standard x86 container

PyTorch:                2.2 or higher
                        For model conversion
                        Standard NGC or pip install

Transformers:           4.36+
                        HuggingFace library

tokenizers:             0.15+
                        Fast tokenization


Container Stack

Docker CE:              24.x
                        Standard Docker installation

containerd:             1.7.x
                        Container runtime for K3s

nvidia-container-toolkit: 1.14.x or higher
                        GPU container support

nvidia-container-runtime: 3.14.x
                        Runtime hook


Container Base Images for RTX Pro 4000

TensorRT-LLM Base (Recommended):
  nvcr.io/nvidia/tensorrt:24.01-py3

Triton Server:
  nvcr.io/nvidia/tritonserver:24.01-py3

PyTorch Base:
  nvcr.io/nvidia/pytorch:24.01-py3

CUDA Base:
  nvcr.io/nvidia/cuda:12.4.0-devel-ubuntu22.04


2.3 TensorRT-LLM Feature Support - RTX Pro 4000

Quantization Support

FP32 Inference:         SUPPORTED - Full precision baseline
FP16 Inference:         SUPPORTED - Half precision, 2x savings
TF32 Inference:         SUPPORTED - Tensor Float 32
BF16 Inference:         SUPPORTED - Brain Float 16
FP8 Inference:          SUPPORTED - Blackwell native support
INT8 Inference:         SUPPORTED - 8-bit quantization
INT4 (AWQ/GPTQ):        SUPPORTED - 4-bit quantization


TensorRT-LLM Features

Paged Attention:        SUPPORTED
In-flight Batching:     SUPPORTED
KV Cache FP8:           SUPPORTED
KV Cache FP16:          SUPPORTED
Chunked Context:        SUPPORTED
Speculative Decoding:   SUPPORTED
Streaming Output:       SUPPORTED
Tensor Parallelism:     NOT SUPPORTED (no NVLink)
Pipeline Parallelism:   NOT SUPPORTED (single GPU)
Grouped Query Attention: SUPPORTED
MPS (Multi-Process):    SUPPORTED - GPU sharing between processes


Memory Configuration - RTX Pro 4000

Total VRAM:             20GB
                        Dedicated GPU memory
                        CONSTRAINT: Everything must fit here

Recommended for Model:  14-16GB
                        Conservative allocation for stability

KV Cache Allocation:    3-4GB
                        Limited by VRAM, supports ~8 sessions

CUDA Context:           1-2GB
                        Driver and runtime overhead

gpu_memory_utilization: 0.80 - 0.85
                        More conservative than Jetson due to limited VRAM


Recommended TensorRT-LLM Configuration - RTX Pro 4000

rtx_pro_4000:
  tensorrt_llm:
    kv_cache_dtype: fp8                           # FP8 for memory savings
    kv_cache_free_gpu_memory_fraction: 0.80       # 80% for KV cache (conservative)
    enable_chunked_context: true                  # Long context support
    max_num_tokens: 4096                          # Smaller than Thor due to VRAM
    use_paged_kv_cache: true                      # Paged attention
    tokens_per_block: 32                          # Smaller blocks for tight memory
    scheduler_policy: guaranteed_no_evict         # Prevent OOM errors
    enable_kv_cache_reuse: true                   # Cache reuse
    gpu_memory_utilization: 0.85                  # 85% memory limit
    max_batch_size: 8                             # Limited by VRAM
    max_concurrent_sessions: 8                    # Target concurrent users


================================================================================
SIDE-BY-SIDE COMPARISON
================================================================================

Hardware Comparison

                        Jetson AGX Thor         RTX Pro 4000
                        ---------------         ------------
Architecture:           ARM64 (aarch64)         x86_64
GPU Generation:         Ampere (SM 8.7)         Blackwell (SM 9.0)
GPU Memory:             128GB Unified           20GB Dedicated
Memory Type:            LPDDR5X Unified         GDDR6X Discrete
Memory Bandwidth:       ~275 GB/s               ~500 GB/s
TDP:                    15-100W (configurable)  130W (fixed)
NVLink:                 Yes                     No
Form Factor:            Embedded Module         PCIe Card
Deployment:             Edge/Industrial         Workstation/Edge PC


Software Stack Comparison

                        Jetson AGX Thor         RTX Pro 4000
                        ---------------         ------------
OS Base:                L4T 36.x (Ubuntu 22.04) Ubuntu 22.04
Driver:                 JetPack Integrated      550.x+
CUDA:                   12.2 (JetPack)          12.4+
TensorRT:               8.6.x (JetPack)         9.2+
TensorRT-LLM:           0.7.x+ (ARM64 build)    0.8.x+ (x86 standard)
Container Image:        l4t-tensorrt:r36.2.0    tensorrt:24.01-py3


Feature Comparison

                        Jetson AGX Thor         RTX Pro 4000
                        ---------------         ------------
FP8 Quantization:       Yes                     Yes
FP16 Quantization:      Yes                     Yes
INT8 Quantization:      Yes                     Yes
INT4 (AWQ/GPTQ):        Yes                     Yes
Paged Attention:        Yes                     Yes
In-flight Batching:     Yes                     Yes
KV Cache FP8:           Yes                     Yes
Tensor Parallelism:     Yes (NVLink)            No
MPS (Multi-Process):    TBD                     Yes
MIG:                    No                      No
Time-Slicing:           Yes                     Yes


Performance Targets

                        Jetson AGX Thor         RTX Pro 4000
                        ---------------         ------------
Max Concurrent Sessions: 20                     8
Max Batch Size:         16                      8
Max Context Length:     20K tokens              8K tokens
Target TTFT:            < 500ms                 < 750ms
Target TPS:             60+                     50+
Target P99 Latency:     < 2000ms                < 3000ms


================================================================================
KUBERNETES / K3s COMPATIBILITY
================================================================================

K3s Support

                        Jetson AGX Thor         RTX Pro 4000
                        ---------------         ------------
K3s Version:            1.28.x (ARM64 build)    1.28.x (x86)
NVIDIA Device Plugin:   0.14.x                  0.14.x
GPU Operator:           23.9.x (ARM64)          23.9.x
Time-Slicing:           Supported               Supported
Helm:                   3.13.x                  3.13.x


Container Runtime

containerd:             1.7.x on both platforms
nvidia-container-toolkit: 1.14.x on both platforms
RuntimeClass:           nvidia on both platforms


================================================================================
VERIFICATION COMMANDS
================================================================================

Check System Information

  # Check architecture
  uname -m
  # Expected: aarch64 (Thor) or x86_64 (RTX)

  # Check OS version
  cat /etc/os-release

  # Check kernel version
  uname -r


Check NVIDIA Stack

  # Check driver version
  nvidia-smi --query-gpu=driver_version --format=csv,noheader

  # Check CUDA version
  nvcc --version
  # or
  nvidia-smi | grep "CUDA Version"

  # Check TensorRT version
  dpkg -l | grep tensorrt
  # or in Python
  python3 -c "import tensorrt; print(tensorrt.__version__)"

  # Check GPU info
  nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv

  # Full GPU details
  nvidia-smi -q


Check Container Stack

  # Docker version
  docker --version

  # NVIDIA Container Toolkit
  nvidia-ctk --version

  # Test GPU in container
  docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi


Check TensorRT-LLM

  # TensorRT-LLM version
  python3 -c "import tensorrt_llm; print(tensorrt_llm.__version__)"

  # Verify TensorRT-LLM is working
  python3 -c "from tensorrt_llm import Builder; print('TensorRT-LLM available')"


Check Jetson-Specific (Thor only)

  # Check JetPack version
  cat /etc/nv_tegra_release

  # Check power mode
  nvpmodel -q

  # Set power mode
  sudo nvpmodel -m 0   # Max performance (100W)
  sudo nvpmodel -m 2   # Balanced (50W)


================================================================================
MODEL COMPATIBILITY
================================================================================

Supported Model Architectures

                        Jetson AGX Thor         RTX Pro 4000
                        ---------------         ------------
LLaMA/LLaMA2:           Yes                     Yes
Mistral:                Yes                     Yes
Falcon:                 Yes                     Yes
GPT-2/GPT-J:            Yes                     Yes
BLOOM:                  Yes                     Yes
MPT:                    Yes                     Yes
Nemotron:               Yes                     Yes (NVIDIA SLM)
Phi-2/Phi-3:            Yes                     Yes (Microsoft SLM)
Qwen:                   Yes                     Yes (Alibaba)
ChatGLM:                Yes                     Yes (Chinese LLM)


Model Size Recommendations

Model Size              Jetson AGX Thor         RTX Pro 4000            Quantization
----------              ---------------         ------------            ------------
1-3B params:            Excellent               Excellent               FP16/FP8
7-8B params:            Excellent               Good                    FP8/INT8
13B params:             Good                    Tight (may need INT4)   FP8/INT8
30B+ params:            Possible                Too large               INT4 only
70B+ params:            INT4 only               Not supported           INT4 required


================================================================================
THERMAL AND POWER MANAGEMENT
================================================================================

Jetson AGX Thor

Power Modes:            15W, 30W, 50W, 100W (configurable)
Default Mode:           50W (balanced)
Max Sustained:          100W (full performance)
Throttle Temp:          83 degrees C (reduces clock speeds)
Max Temp:               95 degrees C (shutdown threshold)
Cooling:                Active fan required for 100W operation

Power mode commands:
  nvpmodel -q                    # Check current mode
  sudo nvpmodel -m 0             # Max performance (100W)
  sudo nvpmodel -m 2             # Balanced (50W)


RTX Pro 4000

TDP:                    130W (fixed, not configurable)
Idle Power:             ~15W
Peak Power:             130W under full load
Throttle Temp:          83 degrees C
Max Temp:               93 degrees C
Cooling:                Active GPU fan
PSU Requirement:        650W or higher recommended

Power and temperature check:
  nvidia-smi --query-gpu=power.draw,temperature.gpu --format=csv

Set power limit (requires root):
  sudo nvidia-smi -pl 120        # Limit to 120W


================================================================================
CRITICAL: TENSORRT-LLM JETSON COMPATIBILITY ISSUES
================================================================================

THE PROBLEM

TensorRT-LLM has significant compatibility issues with Jetson platforms.

As of December 2024, TensorRT-LLM on Jetson is in PREVIEW STATUS with known limitations:

Issue                   Description                                 Impact
-----                   -----------                                 ------
Missing SM_87 Kernels   Fused MHA kernels not compiled for Jetson   Falls back to slower unfused attention
Preview Release Only    v0.12.0-jetson branch is preview            Stability not guaranteed
Limited Testing         NVIDIA still validating various settings    May encounter unexpected issues
Accuracy Degradation    Users report accuracy drops (97% to 89-93%) Model quality may suffer


Specific Errors You May See

  [TensorRT-LLM][WARNING] Fall back to unfused MHA because of unsupported head size 128 in sm_87

This warning indicates the optimized attention kernels are NOT available, resulting in:
  - Slower inference (unfused attention is less efficient)
  - Higher memory usage
  - Potential accuracy issues


Root Cause

From NVIDIA GitHub Issue #1516:
  "TensorRT-LLM does not have the sm 87 fused mha kernels now."

The SM 8.7 (Jetson Orin/Thor) architecture kernels are simply not included in standard builds.

Source: https://github.com/NVIDIA/TensorRT-LLM/issues/1516


OUR MITIGATION STRATEGY

Option 1: Use MLC LLM (Recommended for Jetson)

MLC LLM is already optimized for Jetson and achieves near peak theoretical performance.

Framework               Jetson Support          Performance             Stability
---------               --------------          -----------             ---------
MLC LLM:                Excellent               Near peak               Production ready
llama.cpp:              Good                    Good                    Production ready
TensorRT-LLM:           Preview only            Best (when working)     Preview only
vLLM:                   Limited                 Good                    Compilation issues

Recommendation: Use MLC LLM as primary backend on Jetson, with TensorRT-LLM as optional
for specific models that work well.

Source: https://www.jetson-ai-lab.com/benchmarks.html


Option 2: Use TensorRT-LLM Preview with Caution

If TensorRT-LLM is required (per Quantiphi), follow these guidelines:

  Version:              0.12.0-jetson (Jetson-specific branch)
  JetPack:              6.1 (L4T r36.4 required)
  Container:            dustynv/tensorrt_llm:0.12-r36.4.0

  Workarounds:
    - Use smaller batch sizes to reduce memory pressure
    - Use FP16 instead of FP8 if accuracy issues occur
    - Test model accuracy thoroughly before production
    - Monitor logs for fallback warnings


Option 3: Hybrid Approach (Best)

Use different backends for different platforms:

  Platform              Primary Backend         Fallback Backend
  --------              ---------------         ----------------
  Jetson Thor:          MLC LLM                 TensorRT-LLM (if working)
  RTX Pro 4000:         TensorRT-LLM            vLLM

This ensures:
  - Production stability on Jetson with MLC
  - Maximum performance on x86 with TensorRT-LLM
  - Consistent API across platforms (both support OpenAI-compatible endpoints)


IMPLEMENTATION PLAN

Phase 1: Validate on Lab (Tesla P40)
  - Test TensorRT-LLM on x86 first
  - Establish baseline performance
  - Verify model conversion works

Phase 2: Test on RTX Pro 4000
  - Deploy TensorRT-LLM (should work well)
  - Benchmark performance
  - Validate accuracy

Phase 3: Test on Jetson Thor
  - Start with MLC LLM (stable)
  - Attempt TensorRT-LLM preview
  - Compare accuracy and performance
  - Make final decision on backend

Phase 4: Unified Deployment
  - Abstract backend behind common API
  - Use Triton Inference Server for both
  - Configure per-platform backend selection


JETSON-SPECIFIC ALTERNATIVES

MLC LLM Setup (Recommended)

  # Pull MLC container for Jetson
  docker pull dustynv/mlc:0.1.0-r36.2.0

  # Run with model
  docker run --runtime nvidia -it --rm \
    -v /path/to/models:/models \
    dustynv/mlc:0.1.0-r36.2.0 \
    python3 -m mlc_llm serve /models/llama-7b-q4f16_1


llama.cpp Setup (Stable Alternative)

  # Pull llama.cpp container for Jetson
  docker pull dustynv/llama_cpp:0.2.57-r36.2.0

  # Run server
  docker run --runtime nvidia -it --rm \
    -v /path/to/models:/models \
    -p 8080:8080 \
    dustynv/llama_cpp:0.2.57-r36.2.0 \
    --server -m /models/model.gguf --port 8080


Performance Comparison (Jetson AGX Orin 64GB)

Model                   MLC (tok/s)     llama.cpp (tok/s)       TensorRT-LLM (tok/s)
-----                   -----------     -----------------       --------------------
Llama-2-7B (INT4):      ~45             ~35                     ~50*
Llama-2-13B (INT4):     ~25             ~20                     ~30*
Mistral-7B (INT4):      ~48             ~38                     ~55*

*TensorRT-LLM performance when working correctly; may be lower with unfused MHA fallback.


QUESTIONS FOR HONEYWELL/QUANTIPHI

Before finalizing the Jetson deployment strategy:

  1. Is TensorRT-LLM mandatory? Or can we use MLC/llama.cpp on Jetson?
  2. What accuracy tolerance is acceptable? (TensorRT-LLM preview may have 5-8% accuracy drop)
  3. Have you tested TensorRT-LLM on Jetson Thor specifically?
  4. What JetPack version will be on the production devices?
  5. Is there a timeline for TensorRT-LLM SM_87 kernel support from NVIDIA?


================================================================================
KNOWN LIMITATIONS
================================================================================

Jetson AGX Thor Limitations

1. ARM64 Architecture
   - Requires ARM64-specific container images
   - Some x86 Python packages may not be available
   - TensorRT-LLM must be built from source or use Jetson branch

2. TensorRT-LLM Compatibility (CRITICAL)
   - SM_87 fused MHA kernels NOT available
   - Preview release only (v0.12.0-jetson)
   - May have accuracy degradation (5-8% reported)
   - Consider MLC LLM as production alternative

3. Unified Memory
   - CPU and GPU share memory pool
   - Memory contention possible under heavy load
   - Different allocation strategy than discrete GPUs

4. JetPack Dependency
   - Must match exact JetPack version for all components
   - Upgrades require full JetPack update
   - Limited to NVIDIA-provided CUDA/TensorRT versions

5. Thermal Constraints
   - Edge deployment may have limited cooling
   - Sustained 100W requires adequate airflow
   - May need to use lower power modes (50W, 30W)


RTX Pro 4000 Limitations

1. Limited VRAM
   - Only 20GB constrains model and batch sizes
   - Large models require aggressive quantization (INT4)
   - KV cache limited for many concurrent sessions

2. No NVLink
   - Single GPU only, no multi-GPU support
   - No tensor parallelism possible
   - Model must fit entirely in single GPU

3. Workstation Class
   - Not datacenter-grade reliability
   - Consumer/prosumer driver branch
   - May have different CUDA behavior than Tesla/A100/H100

4. New Architecture
   - Blackwell is newest generation
   - Some software may need updates for full support
   - Early driver versions may have bugs


================================================================================
ACTION ITEMS CHECKLIST
================================================================================

Before Deployment

  [ ] Verify JetPack version on Jetson Thor (requires 6.0+)
  [ ] Verify driver version on RTX Pro 4000 system (requires 545+)
  [ ] Confirm CUDA version matches TensorRT-LLM requirements
  [ ] Test container runtime with GPU access
  [ ] Validate TensorRT-LLM installation
  [ ] Check thermal solution adequacy
  [ ] Verify network connectivity for air-gapped deployment
  [ ] Confirm model format (HuggingFace, ONNX, or TensorRT engine)


During Deployment

  [ ] Build/obtain ARM64 TensorRT-LLM for Jetson (or use MLC)
  [ ] Convert model to TensorRT engine format
  [ ] Configure appropriate quantization (FP8/INT8)
  [ ] Set memory utilization parameters
  [ ] Configure K3s with GPU time-slicing if needed
  [ ] Deploy Triton Inference Server or chosen backend
  [ ] Validate health endpoints
  [ ] Configure monitoring (Prometheus metrics)


Post Deployment

  [ ] Run benchmark suite
  [ ] Verify latency targets met (TTFT, TPS, P99)
  [ ] Check memory utilization under load
  [ ] Monitor thermal behavior under sustained load
  [ ] Validate concurrent session handling
  [ ] Test failover and recovery
  [ ] Document any platform-specific issues found


================================================================================
SOURCES AND REFERENCES
================================================================================

NVIDIA Documentation:
  - JetPack SDK: https://developer.nvidia.com/embedded/jetpack
  - TensorRT-LLM: https://github.com/NVIDIA/TensorRT-LLM
  - Jetson AI Lab: https://www.jetson-ai-lab.com
  - NGC Containers: https://catalog.ngc.nvidia.com

Known Issues:
  - SM_87 Kernels: https://github.com/NVIDIA/TensorRT-LLM/issues/1516
  - Jetson TensorRT-LLM: https://github.com/NVIDIA/TensorRT-LLM/issues/62

Alternative Backends:
  - MLC LLM Benchmarks: https://www.jetson-ai-lab.com/benchmarks.html
  - Dusty NV Containers: https://github.com/dusty-nv/jetson-containers

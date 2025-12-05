#!/usr/bin/env python3
"""
Forge Cognition Hardware Detection Module
==========================================
Automatically detects the hardware SKU and loads appropriate optimization profile.

Supports:
- Jetson AGX Thor (ARM64, unified memory, NVLink)
- RTX Pro 4000 (x86_64, discrete GPU, PCIe)
- Development environments (Tesla P40, etc.)
"""

import os
import subprocess
import platform
import yaml
from dataclasses import dataclass
from typing import Optional, Dict, Any
from pathlib import Path


@dataclass
class HardwareProfile:
    """Hardware-specific optimization profile."""
    name: str
    arch: str
    gpu_name: str
    gpu_memory_gb: float
    nvlink: bool
    tensorrt_precision: str
    max_batch_size: int
    max_input_len: int
    max_output_len: int
    kv_cache_fraction: float
    power_mode: Optional[str] = None
    extra_config: Optional[Dict[str, Any]] = None


# Default profiles for each SKU
DEFAULT_PROFILES = {
    "jetson-thor": HardwareProfile(
        name="jetson-thor",
        arch="aarch64",
        gpu_name="Jetson AGX Thor",
        gpu_memory_gb=64.0,  # Unified memory
        nvlink=True,
        tensorrt_precision="fp16",
        max_batch_size=16,
        max_input_len=4096,
        max_output_len=1024,
        kv_cache_fraction=0.4,
        power_mode="MAXN",
        extra_config={
            "use_paged_kv_cache": True,
            "enable_chunked_context": True,
        }
    ),
    "rtx-pro-4000": HardwareProfile(
        name="rtx-pro-4000",
        arch="x86_64",
        gpu_name="RTX Pro 4000",
        gpu_memory_gb=20.0,
        nvlink=False,
        tensorrt_precision="fp16",
        max_batch_size=8,
        max_input_len=2048,
        max_output_len=512,
        kv_cache_fraction=0.3,
        extra_config={
            "use_paged_kv_cache": True,
        }
    ),
    "development": HardwareProfile(
        name="development",
        arch="x86_64",
        gpu_name="Development GPU",
        gpu_memory_gb=24.0,
        nvlink=False,
        tensorrt_precision="fp16",
        max_batch_size=8,
        max_input_len=2048,
        max_output_len=512,
        kv_cache_fraction=0.3,
    ),
}


def get_gpu_info() -> Dict[str, str]:
    """Get GPU information using nvidia-smi."""
    try:
        result = subprocess.run(
            [
                'nvidia-smi',
                '--query-gpu=name,memory.total,driver_version,compute_cap',
                '--format=csv,noheader,nounits'
            ],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(', ')
            return {
                'name': parts[0] if len(parts) > 0 else 'Unknown',
                'memory_mb': int(parts[1]) if len(parts) > 1 else 0,
                'driver': parts[2] if len(parts) > 2 else 'Unknown',
                'compute_cap': parts[3] if len(parts) > 3 else 'Unknown',
            }
    except Exception as e:
        print(f"Warning: Could not get GPU info: {e}")

    return {'name': 'Unknown', 'memory_mb': 0, 'driver': 'Unknown', 'compute_cap': 'Unknown'}


def detect_jetson() -> bool:
    """Detect if running on Jetson platform."""
    # Check for Jetson-specific files
    jetson_indicators = [
        '/etc/nv_tegra_release',
        '/proc/device-tree/compatible',
    ]

    for indicator in jetson_indicators:
        if os.path.exists(indicator):
            return True

    # Check for Jetson in platform info
    try:
        with open('/proc/device-tree/compatible', 'rb') as f:
            content = f.read().decode('utf-8', errors='ignore')
            if 'tegra' in content.lower() or 'jetson' in content.lower():
                return True
    except:
        pass

    return False


def detect_hardware() -> str:
    """
    Detect which Forge Cognition SKU we're running on.

    Returns:
        str: Hardware profile name ('jetson-thor', 'rtx-pro-4000', or 'development')
    """
    arch = platform.machine()  # aarch64 or x86_64

    # Check for Jetson platform
    if arch == 'aarch64' or detect_jetson():
        gpu_info = get_gpu_info()
        if 'Thor' in gpu_info['name']:
            return 'jetson-thor'
        # Could be Jetson Orin or other - treat as Thor-like
        return 'jetson-thor'

    # x86_64 platform
    gpu_info = get_gpu_info()
    gpu_name = gpu_info['name'].lower()

    if 'rtx' in gpu_name and ('pro' in gpu_name or '4000' in gpu_name):
        return 'rtx-pro-4000'

    # Known development GPUs
    dev_gpus = ['tesla', 'p40', 'v100', 'a100', 'h100', 'geforce', 'quadro']
    if any(dev_gpu in gpu_name for dev_gpu in dev_gpus):
        return 'development'

    # Default to development profile
    return 'development'


def load_profile(profile_name: str, config_path: Optional[str] = None) -> HardwareProfile:
    """
    Load optimization profile for the specified hardware.

    Args:
        profile_name: Name of the hardware profile
        config_path: Optional path to custom config file

    Returns:
        HardwareProfile: The loaded profile
    """
    # Try loading from config file first
    if config_path:
        config_file = Path(config_path)
    else:
        # Look in standard locations
        possible_paths = [
            Path('/config/hardware_profiles.yaml'),
            Path('./config/hardware_profiles.yaml'),
            Path('../config/hardware_profiles.yaml'),
        ]
        config_file = None
        for path in possible_paths:
            if path.exists():
                config_file = path
                break

    if config_file and config_file.exists():
        try:
            with open(config_file) as f:
                config = yaml.safe_load(f)
                if 'profiles' in config and profile_name in config['profiles']:
                    profile_data = config['profiles'][profile_name]
                    return HardwareProfile(
                        name=profile_name,
                        arch=profile_data.get('arch', 'x86_64'),
                        gpu_name=profile_data.get('gpu_name', 'Unknown'),
                        gpu_memory_gb=profile_data.get('gpu_memory', 16.0),
                        nvlink=profile_data.get('nvlink', False),
                        tensorrt_precision=profile_data.get('tensorrt_precision', 'fp16'),
                        max_batch_size=profile_data.get('max_batch_size', 8),
                        max_input_len=profile_data.get('max_input_len', 2048),
                        max_output_len=profile_data.get('max_output_len', 512),
                        kv_cache_fraction=profile_data.get('kv_cache_fraction', 0.3),
                        power_mode=profile_data.get('power_mode'),
                        extra_config=profile_data.get('extra_config'),
                    )
        except Exception as e:
            print(f"Warning: Could not load config from {config_file}: {e}")

    # Fall back to default profiles
    return DEFAULT_PROFILES.get(profile_name, DEFAULT_PROFILES['development'])


def get_gpu_capabilities() -> Dict[str, Any]:
    """Get detailed GPU capabilities for the current hardware."""
    gpu_info = get_gpu_info()

    capabilities = {
        'gpu_name': gpu_info['name'],
        'gpu_memory_mb': gpu_info['memory_mb'],
        'driver_version': gpu_info['driver'],
        'compute_capability': gpu_info['compute_cap'],
        'architecture': platform.machine(),
        'is_jetson': detect_jetson(),
    }

    # Check for specific features
    try:
        # Check CUDA version
        result = subprocess.run(
            ['nvcc', '--version'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'release' in line.lower():
                    capabilities['cuda_version'] = line.strip()
                    break
    except:
        pass

    return capabilities


def get_tensorrt_build_args(profile: HardwareProfile) -> Dict[str, Any]:
    """
    Get TensorRT-LLM build arguments for the hardware profile.

    Returns arguments suitable for trtllm-build command.
    """
    args = {
        'dtype': profile.tensorrt_precision,
        'max_batch_size': profile.max_batch_size,
        'max_input_len': profile.max_input_len,
        'max_output_len': profile.max_output_len,
    }

    # Add profile-specific optimizations
    if profile.extra_config:
        if profile.extra_config.get('use_paged_kv_cache'):
            args['use_paged_kv_cache'] = True
        if profile.extra_config.get('enable_chunked_context'):
            args['enable_chunked_context'] = True

    # Jetson-specific optimizations
    if profile.nvlink:
        args['enable_multi_block_mode'] = True

    return args


def print_hardware_summary():
    """Print a summary of detected hardware configuration."""
    hardware = detect_hardware()
    profile = load_profile(hardware)
    capabilities = get_gpu_capabilities()

    print("=" * 60)
    print("  FORGE COGNITION HARDWARE DETECTION")
    print("=" * 60)
    print(f"  Detected Hardware:    {hardware}")
    print(f"  Architecture:         {profile.arch}")
    print(f"  GPU:                  {capabilities['gpu_name']}")
    print(f"  GPU Memory:           {capabilities['gpu_memory_mb']} MB")
    print(f"  NVLink:               {profile.nvlink}")
    print(f"  TensorRT Precision:   {profile.tensorrt_precision}")
    print(f"  Max Batch Size:       {profile.max_batch_size}")
    print(f"  Max Input Length:     {profile.max_input_len}")
    print(f"  KV Cache Fraction:    {profile.kv_cache_fraction}")
    if profile.power_mode:
        print(f"  Power Mode:           {profile.power_mode}")
    print("=" * 60)


if __name__ == "__main__":
    print_hardware_summary()

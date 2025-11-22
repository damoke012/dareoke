#!/usr/bin/env python3
"""
GPU Detection and Statistics Test Script
Tests GPU availability and reports detailed statistics for OpenShift/ROSA environments
"""

import subprocess
import sys
import os
import json
from datetime import datetime

def print_header(title):
    """Print formatted section header"""
    print("\n" + "=" * 60)
    print(f"  {title}")
    print("=" * 60)

def check_nvidia_smi():
    """Check GPU availability using nvidia-smi"""
    print_header("GPU DETECTION TEST")
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Hostname: {os.uname().nodename}")

    try:
        # Basic nvidia-smi check
        result = subprocess.run(
            ['nvidia-smi'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            print("\n[SUCCESS] NVIDIA GPU(s) detected!")
            print("\n--- nvidia-smi output ---")
            print(result.stdout)
            return True
        else:
            print("\n[ERROR] nvidia-smi failed")
            print(result.stderr)
            return False

    except FileNotFoundError:
        print("\n[ERROR] nvidia-smi not found - NVIDIA drivers not installed")
        return False
    except subprocess.TimeoutExpired:
        print("\n[ERROR] nvidia-smi timed out")
        return False
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}")
        return False

def get_gpu_count():
    """Get the number of available GPUs"""
    try:
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=count', '--format=csv,noheader,nounits'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            # Get first line (all GPUs report same count)
            count = int(result.stdout.strip().split('\n')[0])
            return count
    except:
        pass
    return 0

def get_gpu_details():
    """Get detailed GPU information in JSON format"""
    print_header("GPU DETAILED STATISTICS")

    try:
        # Query specific GPU properties
        query = ','.join([
            'index',
            'name',
            'uuid',
            'memory.total',
            'memory.used',
            'memory.free',
            'utilization.gpu',
            'utilization.memory',
            'temperature.gpu',
            'power.draw',
            'power.limit',
            'driver_version',
            'cuda_version'
        ])

        result = subprocess.run(
            ['nvidia-smi', f'--query-gpu={query}', '--format=csv,noheader,nounits'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            gpu_count = 0
            for line in result.stdout.strip().split('\n'):
                if line:
                    gpu_count += 1
                    values = [v.strip() for v in line.split(',')]

                    print(f"\n--- GPU {values[0]} ---")
                    print(f"  Name:              {values[1]}")
                    print(f"  UUID:              {values[2]}")
                    print(f"  Memory Total:      {values[3]} MiB")
                    print(f"  Memory Used:       {values[4]} MiB")
                    print(f"  Memory Free:       {values[5]} MiB")
                    print(f"  GPU Utilization:   {values[6]}%")
                    print(f"  Memory Util:       {values[7]}%")
                    print(f"  Temperature:       {values[8]}°C")
                    print(f"  Power Draw:        {values[9]} W")
                    print(f"  Power Limit:       {values[10]} W")
                    print(f"  Driver Version:    {values[11]}")
                    print(f"  CUDA Version:      {values[12]}")

            return gpu_count
        else:
            print("[ERROR] Could not query GPU details")
            return 0

    except Exception as e:
        print(f"[ERROR] {e}")
        return 0

def check_cuda_toolkit():
    """Check CUDA toolkit availability"""
    print_header("CUDA TOOLKIT CHECK")

    try:
        result = subprocess.run(
            ['nvcc', '--version'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            print("[SUCCESS] CUDA Toolkit found")
            print(result.stdout)
            return True
        else:
            print("[INFO] CUDA Toolkit (nvcc) not found")
            print("This is normal if only using nvidia-smi for GPU detection")
            return False

    except FileNotFoundError:
        print("[INFO] nvcc not in PATH - CUDA Toolkit may not be installed")
        return False

def run_simple_gpu_compute():
    """Run a simple GPU compute test if PyTorch/TensorFlow available"""
    print_header("GPU COMPUTE TEST")

    # Try PyTorch
    try:
        import torch
        if torch.cuda.is_available():
            device_count = torch.cuda.device_count()
            print(f"[SUCCESS] PyTorch CUDA available - {device_count} GPU(s)")

            for i in range(device_count):
                props = torch.cuda.get_device_properties(i)
                print(f"\n  GPU {i}: {props.name}")
                print(f"    Compute Capability: {props.major}.{props.minor}")
                print(f"    Total Memory: {props.total_memory / 1024**3:.2f} GB")
                print(f"    Multi-Processors: {props.multi_processor_count}")

            # Simple compute test
            print("\n  Running matrix multiplication test...")
            a = torch.randn(1000, 1000, device='cuda')
            b = torch.randn(1000, 1000, device='cuda')

            import time
            start = time.time()
            for _ in range(100):
                c = torch.matmul(a, b)
            torch.cuda.synchronize()
            elapsed = time.time() - start

            print(f"  [SUCCESS] 100x matrix multiplications: {elapsed:.3f}s")
            return True
        else:
            print("[INFO] PyTorch found but CUDA not available")
            return False

    except ImportError:
        print("[INFO] PyTorch not installed - skipping compute test")

    # Try TensorFlow
    try:
        import tensorflow as tf
        gpus = tf.config.list_physical_devices('GPU')
        if gpus:
            print(f"[SUCCESS] TensorFlow GPU available - {len(gpus)} GPU(s)")
            for gpu in gpus:
                print(f"  {gpu}")
            return True
        else:
            print("[INFO] TensorFlow found but no GPUs detected")
            return False

    except ImportError:
        print("[INFO] TensorFlow not installed - skipping compute test")

    return False

def generate_summary(gpu_count):
    """Generate final summary"""
    print_header("TEST SUMMARY")

    if gpu_count > 0:
        print(f"""
  Status:     PASSED
  GPU Count:  {gpu_count}
  Result:     GPU resources successfully detected and available

  This node is ready for GPU workloads!
""")
        return 0  # Success exit code
    else:
        print("""
  Status:     FAILED
  GPU Count:  0
  Result:     No GPU resources detected

  Possible causes:
  - Node does not have GPU hardware
  - NVIDIA drivers not installed
  - GPU not allocated to this pod (check resource requests)
  - GPU Operator not configured
""")
        return 1  # Failure exit code

def main():
    """Main execution"""
    print("\n" + "#" * 60)
    print("#" + " " * 58 + "#")
    print("#    OPENSHIFT/ROSA GPU DETECTION & STATISTICS TEST    #")
    print("#" + " " * 58 + "#")
    print("#" * 60)

    # Run all checks
    nvidia_available = check_nvidia_smi()
    gpu_count = get_gpu_details() if nvidia_available else 0
    check_cuda_toolkit()
    run_simple_gpu_compute()

    # Generate summary and exit
    exit_code = generate_summary(gpu_count)

    print("=" * 60)
    print(f"Test completed at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60 + "\n")

    sys.exit(exit_code)

if __name__ == "__main__":
    main()

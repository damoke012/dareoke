#!/usr/bin/env python3
"""
Honeywell Forge Cognition - GPU Metrics Monitor
Real-time GPU monitoring for edge inference optimization

Features:
- Real-time GPU memory tracking
- Utilization monitoring
- Memory per-session estimation
- Threshold alerts
- CSV export for analysis

Usage:
    python gpu-metrics.py                    # Live monitoring
    python gpu-metrics.py --export results/  # Export to CSV
    python gpu-metrics.py --interval 0.5     # 500ms sample rate
"""

import argparse
import csv
import os
import sys
import time
from datetime import datetime
from dataclasses import dataclass
from typing import List, Optional

try:
    import pynvml
    NVML_AVAILABLE = True
except ImportError:
    NVML_AVAILABLE = False
    print("Warning: pynvml not available. Install with: pip install pynvml")


@dataclass
class GPUSnapshot:
    """Single point-in-time GPU measurement"""
    timestamp: datetime
    gpu_id: int
    name: str
    memory_used_mb: float
    memory_total_mb: float
    memory_percent: float
    gpu_utilization: int
    memory_utilization: int
    temperature: int
    power_draw_w: float
    power_limit_w: float


class GPUMonitor:
    """Real-time GPU monitoring for Forge Cognition"""

    def __init__(self):
        if not NVML_AVAILABLE:
            raise RuntimeError("pynvml required for GPU monitoring")

        pynvml.nvmlInit()
        self.device_count = pynvml.nvmlDeviceGetCount()
        self.handles = []
        self.device_names = []

        for i in range(self.device_count):
            handle = pynvml.nvmlDeviceGetHandleByIndex(i)
            self.handles.append(handle)
            self.device_names.append(pynvml.nvmlDeviceGetName(handle))

        print(f"Initialized monitoring for {self.device_count} GPU(s)")
        for i, name in enumerate(self.device_names):
            print(f"  GPU {i}: {name}")

    def get_snapshot(self) -> List[GPUSnapshot]:
        """Get current GPU metrics snapshot"""
        snapshots = []
        timestamp = datetime.now()

        for i, handle in enumerate(self.handles):
            try:
                mem_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
                util = pynvml.nvmlDeviceGetUtilizationRates(handle)

                try:
                    temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
                except:
                    temp = 0

                try:
                    power = pynvml.nvmlDeviceGetPowerUsage(handle) / 1000  # mW to W
                    power_limit = pynvml.nvmlDeviceGetPowerManagementLimit(handle) / 1000
                except:
                    power = 0
                    power_limit = 0

                snapshot = GPUSnapshot(
                    timestamp=timestamp,
                    gpu_id=i,
                    name=self.device_names[i],
                    memory_used_mb=mem_info.used / (1024 * 1024),
                    memory_total_mb=mem_info.total / (1024 * 1024),
                    memory_percent=(mem_info.used / mem_info.total) * 100,
                    gpu_utilization=util.gpu,
                    memory_utilization=util.memory,
                    temperature=temp,
                    power_draw_w=power,
                    power_limit_w=power_limit
                )
                snapshots.append(snapshot)

            except Exception as e:
                print(f"Error reading GPU {i}: {e}")

        return snapshots

    def shutdown(self):
        """Clean shutdown"""
        pynvml.nvmlShutdown()


class MetricsExporter:
    """Export GPU metrics to CSV"""

    def __init__(self, output_dir: str):
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.filepath = os.path.join(output_dir, f"gpu_metrics_{timestamp}.csv")

        self.file = open(self.filepath, 'w', newline='')
        self.writer = csv.writer(self.file)
        self.writer.writerow([
            'timestamp', 'gpu_id', 'name',
            'memory_used_mb', 'memory_total_mb', 'memory_percent',
            'gpu_utilization', 'memory_utilization',
            'temperature', 'power_draw_w', 'power_limit_w'
        ])
        print(f"Exporting metrics to: {self.filepath}")

    def write(self, snapshot: GPUSnapshot):
        self.writer.writerow([
            snapshot.timestamp.isoformat(),
            snapshot.gpu_id,
            snapshot.name,
            round(snapshot.memory_used_mb, 2),
            round(snapshot.memory_total_mb, 2),
            round(snapshot.memory_percent, 2),
            snapshot.gpu_utilization,
            snapshot.memory_utilization,
            snapshot.temperature,
            round(snapshot.power_draw_w, 2),
            round(snapshot.power_limit_w, 2)
        ])
        self.file.flush()

    def close(self):
        self.file.close()
        print(f"\nMetrics saved to: {self.filepath}")


def print_live_metrics(snapshots: List[GPUSnapshot], thresholds: dict):
    """Pretty print GPU metrics with threshold alerts"""
    # Clear screen (works on most terminals)
    print("\033[2J\033[H", end="")

    print("=" * 70)
    print("FORGE COGNITION GPU MONITOR")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)

    for snap in snapshots:
        # Memory bar
        bar_width = 40
        filled = int(snap.memory_percent / 100 * bar_width)
        bar = "█" * filled + "░" * (bar_width - filled)

        # Memory alert
        mem_alert = ""
        if snap.memory_percent > thresholds.get('memory_critical', 90):
            mem_alert = " ⚠️  CRITICAL"
        elif snap.memory_percent > thresholds.get('memory_warning', 80):
            mem_alert = " ⚡ WARNING"

        # GPU util alert
        util_alert = ""
        if snap.gpu_utilization > thresholds.get('util_high', 95):
            util_alert = " 🔥 HIGH"

        print(f"\nGPU {snap.gpu_id}: {snap.name}")
        print("-" * 50)
        print(f"Memory:      [{bar}] {snap.memory_percent:.1f}%{mem_alert}")
        print(f"             {snap.memory_used_mb:.0f} / {snap.memory_total_mb:.0f} MB")
        print(f"GPU Util:    {snap.gpu_utilization}%{util_alert}")
        print(f"Mem Util:    {snap.memory_utilization}%")
        print(f"Temperature: {snap.temperature}°C")
        print(f"Power:       {snap.power_draw_w:.1f}W / {snap.power_limit_w:.1f}W")

    # Session estimation (for Forge Cognition planning)
    if snapshots:
        snap = snapshots[0]
        available_mb = snap.memory_total_mb - snap.memory_used_mb

        # Estimate based on typical LLM session footprint
        # ~2GB base model + ~500MB per session for KV cache
        base_model_mb = 2000
        per_session_mb = 500

        if available_mb > base_model_mb:
            max_sessions = int((available_mb - base_model_mb) / per_session_mb)
        else:
            max_sessions = 0

        print("\n" + "-" * 50)
        print("SESSION CAPACITY ESTIMATE (Forge Cognition)")
        print(f"Available Memory:     {available_mb:.0f} MB")
        print(f"Est. Model Footprint: {base_model_mb} MB")
        print(f"Est. Per-Session:     {per_session_mb} MB")
        print(f"Max Concurrent:       ~{max_sessions} sessions")

    print("\n" + "=" * 70)
    print("Press Ctrl+C to stop")


def main():
    parser = argparse.ArgumentParser(
        description="Forge Cognition GPU Metrics Monitor"
    )
    parser.add_argument(
        '--interval', '-i',
        type=float,
        default=1.0,
        help='Sampling interval in seconds (default: 1.0)'
    )
    parser.add_argument(
        '--export', '-e',
        type=str,
        default=None,
        help='Export metrics to CSV in specified directory'
    )
    parser.add_argument(
        '--duration', '-d',
        type=int,
        default=None,
        help='Run for specified duration in seconds (default: infinite)'
    )
    parser.add_argument(
        '--memory-warning',
        type=float,
        default=80.0,
        help='Memory usage warning threshold %% (default: 80)'
    )
    parser.add_argument(
        '--memory-critical',
        type=float,
        default=90.0,
        help='Memory usage critical threshold %% (default: 90)'
    )

    args = parser.parse_args()

    if not NVML_AVAILABLE:
        print("Error: pynvml not available. Install with: pip install pynvml")
        sys.exit(1)

    thresholds = {
        'memory_warning': args.memory_warning,
        'memory_critical': args.memory_critical,
        'util_high': 95
    }

    monitor = GPUMonitor()
    exporter = MetricsExporter(args.export) if args.export else None

    start_time = time.time()
    sample_count = 0

    try:
        while True:
            snapshots = monitor.get_snapshot()

            if exporter:
                for snap in snapshots:
                    exporter.write(snap)

            print_live_metrics(snapshots, thresholds)

            sample_count += 1

            # Check duration limit
            if args.duration and (time.time() - start_time) >= args.duration:
                print(f"\nDuration limit reached ({args.duration}s)")
                break

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print("\n\nStopping monitor...")

    finally:
        monitor.shutdown()
        if exporter:
            exporter.close()
        print(f"Collected {sample_count} samples")


if __name__ == "__main__":
    main()

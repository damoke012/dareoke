#!/usr/bin/env python3
"""
GPU Profiler Service
Exposes GPU metrics via Prometheus-compatible HTTP endpoint
"""

import os
import time
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
import torch

PORT = int(os.environ.get('PROMETHEUS_PORT', 8000))

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            metrics = self.get_gpu_metrics()
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(metrics.encode())
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

    def get_gpu_metrics(self):
        metrics = []

        # PyTorch GPU info
        if torch.cuda.is_available():
            for i in range(torch.cuda.device_count()):
                props = torch.cuda.get_device_properties(i)

                # Memory metrics
                allocated = torch.cuda.memory_allocated(i) / 1e9
                reserved = torch.cuda.memory_reserved(i) / 1e9
                total = props.total_memory / 1e9

                metrics.append(f'gpu_memory_allocated_gb{{gpu="{i}"}} {allocated:.2f}')
                metrics.append(f'gpu_memory_reserved_gb{{gpu="{i}"}} {reserved:.2f}')
                metrics.append(f'gpu_memory_total_gb{{gpu="{i}"}} {total:.2f}')

                # Device info
                metrics.append(f'gpu_info{{gpu="{i}",name="{props.name}",compute_capability="{props.major}.{props.minor}"}} 1')

        # nvidia-smi metrics
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=index,utilization.gpu,utilization.memory,temperature.gpu,power.draw',
                 '--format=csv,noheader,nounits'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    parts = [p.strip() for p in line.split(',')]
                    if len(parts) >= 5:
                        idx, gpu_util, mem_util, temp, power = parts[:5]
                        metrics.append(f'gpu_utilization_percent{{gpu="{idx}"}} {gpu_util}')
                        metrics.append(f'gpu_memory_utilization_percent{{gpu="{idx}"}} {mem_util}')
                        metrics.append(f'gpu_temperature_celsius{{gpu="{idx}"}} {temp}')
                        try:
                            metrics.append(f'gpu_power_watts{{gpu="{idx}"}} {float(power):.2f}')
                        except:
                            pass
        except Exception as e:
            metrics.append(f'# Error getting nvidia-smi metrics: {e}')

        return '\n'.join(metrics) + '\n'

    def log_message(self, format, *args):
        # Suppress default logging
        pass

def main():
    import sys
    # Force unbuffered output for logs
    sys.stdout = sys.stderr

    print(f"Starting GPU Profiler Service on port {PORT}", flush=True)
    print(f"PyTorch version: {torch.__version__}", flush=True)
    print(f"CUDA available: {torch.cuda.is_available()}", flush=True)
    if torch.cuda.is_available():
        print(f"GPU count: {torch.cuda.device_count()}", flush=True)
        for i in range(torch.cuda.device_count()):
            print(f"  GPU {i}: {torch.cuda.get_device_name(i)}", flush=True)

    server = HTTPServer(('0.0.0.0', PORT), MetricsHandler)
    print(f"Metrics available at http://localhost:{PORT}/metrics", flush=True)
    print(f"Health check at http://localhost:{PORT}/health", flush=True)
    server.serve_forever()

if __name__ == '__main__':
    main()

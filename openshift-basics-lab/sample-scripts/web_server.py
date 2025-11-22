#!/usr/bin/env python3
"""
Simple web service simulation for demonstration.
This keeps running and reports status periodically.
"""

import time
import random
import socket
from datetime import datetime

def main():
    hostname = socket.gethostname()

    print("=" * 60)
    print("WEB SERVICE STARTED")
    print("=" * 60)
    print(f"Pod: {hostname}")
    print(f"Start Time: {datetime.now()}")
    print()
    print("Service is running and ready to handle requests...")
    print()

    # Keep running forever (like a web server)
    while True:
        connections = random.randint(10, 50)
        memory = random.randint(30, 70)
        cpu = random.randint(20, 80)

        print(f"[{datetime.now()}] Heartbeat - Pod {hostname} is healthy")
        print(f"[{datetime.now()}] Active connections: {connections}")
        print(f"[{datetime.now()}] Memory usage: {memory}%")
        print(f"[{datetime.now()}] CPU usage: {cpu}%")
        print("---")

        time.sleep(30)

if __name__ == "__main__":
    main()

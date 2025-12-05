#!/bin/bash
#
# Forge Cognition Benchmark Runner
# =================================
# Runs the LLM benchmark suite against the deployed inference server
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="forge-inference"
OUTPUT_DIR="${SCRIPT_DIR}/results"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Parse arguments
CONCURRENCY="${CONCURRENCY:-1,2,4,8}"
REQUESTS="${REQUESTS:-20}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --concurrency)
            CONCURRENCY="$2"
            shift 2
            ;;
        --requests)
            REQUESTS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--concurrency 1,2,4,8] [--requests 20]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  Forge Cognition Benchmark"
echo "=========================================="
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Get Triton endpoint
log_info "Getting Triton endpoint..."
TRITON_SVC=$(oc get svc triton-inference-server -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

if [[ -z "$TRITON_SVC" ]]; then
    log_warn "Triton service not found. Is the deployment running?"
    exit 1
fi

ENDPOINT="http://${TRITON_SVC}:8000"
log_info "Endpoint: ${ENDPOINT}"

# Check if we can run locally or need to run in cluster
if curl -sf "${ENDPOINT}/v2/health/ready" &>/dev/null; then
    log_info "Endpoint is accessible from this machine"
    RUN_MODE="local"
else
    log_info "Endpoint not accessible locally, will run in cluster"
    RUN_MODE="cluster"
fi

# Generate timestamp for output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/benchmark_${TIMESTAMP}.json"

if [[ "$RUN_MODE" == "local" ]]; then
    # Run locally
    log_info "Running benchmark locally..."

    # Check for dependencies
    if ! python3 -c "import aiohttp" &>/dev/null; then
        log_warn "Installing aiohttp..."
        pip install aiohttp --quiet
    fi

    python3 "${SCRIPT_DIR}/benchmark_llm.py" \
        --endpoint "${ENDPOINT}" \
        --concurrency "${CONCURRENCY}" \
        --requests "${REQUESTS}" \
        --output "${OUTPUT_FILE}"
else
    # Run in cluster
    log_info "Running benchmark in cluster..."

    # Create a job to run the benchmark
    cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: llm-benchmark-${TIMESTAMP}
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: benchmark
        image: python:3.10-slim
        command: ["/bin/bash", "-c"]
        args:
        - |
          pip install --quiet aiohttp
          cat > /tmp/benchmark.py << 'PYEOF'
$(cat "${SCRIPT_DIR}/benchmark_llm.py")
PYEOF
          python3 /tmp/benchmark.py \
            --endpoint http://triton-inference-server:8000 \
            --concurrency ${CONCURRENCY} \
            --requests ${REQUESTS} \
            --output /tmp/results.json
          cat /tmp/results.json
EOF

    # Wait for job and get results
    log_info "Waiting for benchmark job to complete..."
    oc wait --for=condition=complete job/llm-benchmark-${TIMESTAMP} -n ${NAMESPACE} --timeout=600s

    # Get results from logs
    oc logs job/llm-benchmark-${TIMESTAMP} -n ${NAMESPACE} > "${OUTPUT_FILE}"

    # Cleanup
    oc delete job llm-benchmark-${TIMESTAMP} -n ${NAMESPACE} --ignore-not-found=true
fi

echo ""
log_info "Benchmark complete!"
log_info "Results saved to: ${OUTPUT_FILE}"
echo ""

# Display results
if [[ -f "${OUTPUT_FILE}" ]]; then
    cat "${OUTPUT_FILE}"
fi

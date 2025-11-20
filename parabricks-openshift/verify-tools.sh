#!/bin/bash

echo "=============================================="
echo "Parabricks Workbench - Genomics Tools Verification"
echo "Version 1.3.0"
echo "=============================================="
echo ""

# Function to check tool
check_tool() {
    local tool_name=$1
    local command=$2

    echo -n "Checking $tool_name... "
    if eval "$command" &> /dev/null; then
        echo "✓ INSTALLED"
        eval "$command" 2>&1 | head -1
    else
        echo "✗ NOT FOUND"
        return 1
    fi
    echo ""
}

# Check all genomics tools
echo "=== Core Genomics Tools ==="
echo ""

check_tool "samtools" "samtools --version"
check_tool "bcftools" "bcftools --version"
check_tool "bwa" "bwa 2>&1 | head -1"
check_tool "GATK" "gatk --version"

echo "=== Data Download Tools ==="
echo ""

check_tool "SRA Toolkit (fastq-dump)" "fastq-dump --version"
check_tool "SRA Toolkit (prefetch)" "prefetch --version"
check_tool "EDirect (esearch)" "which esearch"
check_tool "EDirect (efetch)" "which efetch"

echo "=== Parabricks ==="
echo ""

check_tool "Parabricks" "pbrun --version"

echo "=== Python Genomics Libraries ==="
echo ""

python3 -c "
import sys
packages = {
    'BioPython': 'Bio',
    'PySam': 'pysam',
    'pandas': 'pandas',
    'numpy': 'numpy',
    'matplotlib': 'matplotlib',
    'seaborn': 'seaborn'
}

for name, module in packages.items():
    try:
        exec(f'import {module}')
        mod = sys.modules[module]
        version = getattr(mod, '__version__', 'unknown')
        print(f'✓ {name}: {version}')
    except ImportError:
        print(f'✗ {name}: NOT FOUND')
"

echo ""
echo "=============================================="
echo "Verification Complete!"
echo "=============================================="
echo ""
echo "Available genomics workflows:"
echo ""
echo "1. Download data from SRA:"
echo "   prefetch SRR123456"
echo "   fastq-dump --split-files SRR123456"
echo ""
echo "2. Search NCBI databases:"
echo "   esearch -db nucleotide -query 'E. coli' | efetch -format fasta"
echo ""
echo "3. Index reference genome:"
echo "   samtools faidx reference.fasta"
echo "   bwa index reference.fasta"
echo ""
echo "4. Run GATK workflows:"
echo "   gatk HaplotypeCaller -R reference.fasta -I sample.bam -O variants.vcf"
echo ""
echo "5. Run Parabricks GPU-accelerated pipelines:"
echo "   pbrun fq2bam --ref reference.fasta --in-fq sample_1.fq sample_2.fq --out-bam output.bam"
echo ""

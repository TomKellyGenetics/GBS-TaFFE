# 2022 Benjamin J Perry
# MIT License
# Copyright (c) 2022 Benjamin J Perry
# Version: 1.0
# Maintainer: Benjamin J Perry
# Email: ben.perry@agresearch.co.nz

configfile: "config/config.yaml"

import os

onstart:
    print(f"Working directory: {os.getcwd()}")
    print("TOOLS: ")
    os.system('echo "  bash: $(which bash)"')
    os.system('echo "  PYTHON: $(which python)"')
    os.system('echo "  CONDA: $(which conda)"')
    os.system('echo "  SNAKEMAKE: $(which snakemake)"')
    os.system('echo "  PYTHON VERSION: $(python --version)"')
    os.system('echo "  CONDA VERSION: $(conda --version)"')
    print(f"Env TMPDIR={os.environ.get('TMPDIR', '<n/a>')}")

# Define samples from data directory using wildcards
SAMPLES, = glob_wildcards('fastq/{samples}.fastq.gz')


rule all:
    expand('completed/{samples}.fasta', samples=SAMPLES) #TODO: Update to functional targets


rule cutadapt:
    input:
        'fastq/{samples}.fastq.gz'
    output:
        '02_cutadapt/{samples}.chop.primer.fastq.gz'
    threads:4
    log:
        'logs/{samples}/cutadapt.primers.log'
    container: 
        'docker://quay.io/biocontainers/cutadapt:4.1--py310h1425a21_1'
    params:
        fwdPrimer=config['cutadapt']['fwd'],
        revPrimer=config['cutadapt']['rev'],
    resources:
        tempdir=config['TMPDIR']
    message:
        'removing primers: {wildcards.samples}\n'
        'TMPDIR: {resources.tempdir}'
    shell:
        'cutadapt '
        '--discard-untrimmed '
        '--action=retain '
        '-j {threads} '
        '--error-rate 0.2 '
        '-g {params.fwdPrimer} '
        '-a {params.revPrimer} '
        '-o {output} '
        '{input} '
        '2>&1 | tee {log}'


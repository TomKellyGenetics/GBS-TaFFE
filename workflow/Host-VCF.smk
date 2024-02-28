# 2024 Benjamin J Perry
# MIT License
# Copyright (c) 2024 Benjamin J Perry
# Version: 1.0
# Maintainer: Benjamin J Perry
# Email: ben.perry@agresearch.co.nz

# Based off of Rudi's Homebrew pipeline

configfile: "config/config.yaml"


import os
import pandas as pd


wildcard_constraints:
    samples="\w+"


# Just declaring, in practise this is passed on the CLI by --config LIBRARY=SQ####
LIBRARY = config["LIBRARY"]


input_fastq_pattern = os.path.join('results', config["LIBRARY"], '02_kneaddata', '{samples}.fastq.gz')
print(input_fastq_pattern)
FIDs, = glob_wildcards(input_fastq_pattern)


onstart:
    print(f"Working directory: {os.getcwd()}")
    print("TOOLS: ")
    os.system('echo "  bash: $(which bash)"')
    os.system('echo "  PYTHON: $(which python)"')
    os.system('echo "  CONDA: $(which conda)"')
    os.system('echo "  SNAKEMAKE: $(which snakemake)"')
    print(f"Env TMPDIR = {os.environ.get('TMPDIR', '<n/a>')}")
    os.system('echo "  PYTHON VERSION: $(python --version)"')
    os.system('echo "  CONDA VERSION: $(conda --version)"')


rule all:
    input:
        expand("results/{library}/06_host_alignment/{library}.merged.host.vcf", library = LIBRARY),
        os.path.join("results", LIBRARY, "06_host_alignment", (LIBRARY + ".merged.host.samtools.bam")),
        os.path.join("results", LIBRARY, "06_host_alignment", (LIBRARY + ".merged.host.bamtools.bam"))


localrules: get_genome, bcftools_index


rule kraken2_host_filter:
    input:
        preprocessed_reads = "results/{library}/02_kneaddata/{samples}.fastq.gz",
    output:
        k2OutputHosts = temp("results/{library}/04_k2_filtering/{samples}.hosts.k2"),
        k2_filtered_reads = temp("results/{library}/04_k2_filtering/{samples}.nonhost.fastq"),
        k2_host_reads = temp("results/{library}/04_k2_filtering/{samples}.host.fastq"),
    log:
        os.path.join("results", "{library}", "logs", "kraken2", "kraken2_host_filter.{samples}.log"),
    benchmark:
        os.path.join("results", "{library}", "benchmarks", "kraken2_host_filter.{samples}.txt"),
    conda:
        "kraken2"
    threads: 8
    resources:
        mem_gb = lambda wildcards, attempt: 32 + ((attempt - 1) * 32), #TODO benchmark and tweak
        time = lambda wildcards, attempt: 30 + ((attempt - 1) * 30),
        partition = "compute,hugemem"
    shell:
        "kraken2 "
        "--gzip-compressed "
        "--unclassified-out {output.k2_filtered_reads} "
        "--classified-out {output.k2_host_reads} "
        "--db /agr/scratch/projects/2022-bjp-gtdb/build-GTDB-DBs/GTDB/kraken2-hosts " 
        "-t {threads} "
        "--output {output.k2OutputHosts} "
        "{input.preprocessed_reads} "
        "2>&1 | tee {log} "


rule kraken2_host_filter_gz:
    input:
        k2_filtered_reads = "results/{library}/04_k2_filtering/{samples}.nonhost.fastq",
        k2_host_reads = "results/{library}/04_k2_filtering/{samples}.host.fastq",
    output:
        k2_filtered_reads_gz = "results/{library}/04_k2_filtering/{samples}.nonhost.fastq.gz",
        k2_host_reads_gz = "results/{library}/04_k2_filtering/{samples}.host.fastq.gz",
    log:
        os.path.join("results", "{library}", "logs", "kraken2", "kraken2_host_filter_gz.{samples}.log"),
    benchmark:
        os.path.join("results", "{library}", "benchmarks", "kraken2_host_filter_gz.{samples}.txt"),
    conda:
        "pigz"
    threads: 8
    resources:
        mem_gb = lambda wildcards, attempt: 4 + ((attempt - 1) * 4),
        time = lambda wildcards, attempt: 5 + ((attempt - 1) * 5),
        partition = "compute,hugemem"
    shell:
        """

        pigz -p {threads} -c {input.k2_filtered_reads} > {output.k2_filtered_reads_gz} && 
        pigz -p {threads} -c {input.k2_host_reads} > {output.k2_host_reads_gz} &&

        rm {input.k2_filtered_reads} {input.k2_host_reads};

        """


rule get_genome:
    output:
        genome_gz = protected('resources/ref/GCF_000298735.2_genomic.fna.gz'),
    threads: 2
    resources:
        partition='compute'
    resources:
        time = lambda wildcards, attempt: attempt * 7 * 24 * 60
    params:
        genome=config['genome'],
    shell:
        "wget -c -O {output.genome_gz} {params.genome} "


rule build_b2_index:
    input:
        genome_gz = 'resources/ref/GCF_000298735.2_genomic.fna.gz',
    output:
        bt2_index_semaphore = "resources/ref/BT2INDEX.rev.1.bt2"
    conda:
        "bowtie2-2.5.1"
    threads: 12
    resources:
        mem_gb = lambda wildcards, attempt: 16 + ((attempt - 1) * 16), #TODO benchmark and tweak
        time = lambda wildcards, attempt: 60 + ((attempt - 1) * 60),
        partition = "compute"
    shell:
        """
        
        bowtie2 -f --threads {threads} --seed 1953 {input.genome_gz} resources/ref/BT2INDEX 
        bowtie2-inspect -s resources/ref/BT2INDEX

        """


rule bowtie2_alignment:
    input:
        k2_host_reads_gz = "results/{library}/04_k2_filtering/{samples}.host.fastq.gz",
        bt2_index_semaphore = "resources/ref/BT2INDEX.rev.1.bt2"
    output:
        host_sam = temp("results/{library}/06_host_alignment/{samples}.sam"),
    log:
        os.path.join("results", "{library}", "logs", "bowtie2", "bowtie2_alignment.{samples}.log"),
    benchmark:
        os.path.join("results", "{library}", "benchmarks", "bowtie2_alignment.{samples}.txt"),
    conda:
        "bowtie2-2.5.1"
    threads: 6
    resources:
        mem_gb = lambda wildcards, attempt: 8 + ((attempt - 1) * 84),
        time = lambda wildcards, attempt: 20 + ((attempt - 1) * 20),
        partition = "compute,hugemem"
    shell:
        "bowtie2 "
        "--very-fast-local "
        "-p {threads} "
        "--rg-id {wildcards.samples} "
        "--rg SM:{wildcards.samples} "
        "--rg LB:{wildcards.library} "
        "--rg PU:{wildcards.library} " #TODO add flowcell here
        "--rg PL:ILLUMINA " 
        "-x resources/ref/BT2INDEX "
        "-U {input.k2_host_reads_gz} "
        "-S {output.host_sam} "
        "2> {log} "



rule prepare_bams:
    input:
        host_sam = "results/{library}/06_host_alignment/{samples}.sam",
    output:
        host_bam = "results/{library}/06_host_alignment/{samples}.sorted.bam",
    log:
        os.path.join("results", "{library}", "logs", "samtools", "prepare_bams.{samples}.log"),
    benchmark:
        os.path.join("results", "{library}", "benchmarks", "prepare_bams.{samples}.txt"),
    conda:
        "samtools-1.17"
    threads: 6
    resources:
        mem_gb = lambda wildcards, attempt: 8 + ((attempt - 1) * 8),
        time = lambda wildcards, attempt: 20 + ((attempt - 1) * 60),
        partition = "compute,hugemem"
    shell:
        """
        samtools view --threads 6 -bS  {input.host_sam} | samtools sort > {output.host_bam} 2> {log}


        """


rule bcftools_merge_bams:
    input:
        host_bams = expand("results/{library}/06_host_alignment/{samples}.sorted.bam", library = LIBRARY, samples = FIDs),
    output:
        merged_bams = os.path.join("results", LIBRARY, "06_host_alignment", (LIBRARY + ".merged.host.bamtools.bam"))
    log:
        os.path.join("results", LIBRARY, "logs", "bamtools", "bcftools_merge_bams.log"),
    benchmark:
        os.path.join("results", LIBRARY, "benchmarks", "bcftools_merge_bams.txt"),
    conda:
        "bamtools-2.5.2"
    threads: 12
    resources:
        mem_gb = lambda wildcards, attempt: 32 + ((attempt - 1) * 32),
        time = lambda wildcards, attempt: 720 + ((attempt - 1) * 720),
        partition = "compute"
    shell:
        "bamtools "
        "-in {input.host_bams} "
        "-out {output.merged_bams} "


rule samtools_merge_bams:
    input:
        host_bams = expand("results/{library}/06_host_alignment/{samples}.sorted.bam", library = LIBRARY, samples = FIDs),
        bcf_index = 'resources/ref/GCF_000298735.2_genomic.fna' #TODO automate the file name expansion to add .fai
    output:
        merged_bams = os.path.join("results", LIBRARY, "06_host_alignment", (LIBRARY + ".merged.host.samtools.bam"))
    log:
        os.path.join("results", LIBRARY, "logs", "bamtools", "samtools_merge_bams.log"),
    benchmark:
        os.path.join("results", LIBRARY, "benchmarks", "samtools_merge_bams.txt"),
    conda:
        "samtools-1.17"
    threads: 12
    resources:
        mem_gb = lambda wildcards, attempt: 32 + ((attempt - 1) * 32),
        time = lambda wildcards, attempt: 720 + ((attempt - 1) * 720),
        partition = "compute"
    shell:
        "samtools "
        "-o {output.merged_bams} "
        "-u "
        "-O BAM "
        "--reference {input.bcf_index} "
        "--threads {threads} "
        "--write-index "
        "{input.host_bams} "


rule bcftools_index:
    input:
        genome_gz = 'resources/ref/GCF_000298735.2_genomic.fna.gz',
    output:
        bcf_index = 'resources/ref/GCF_000298735.2_genomic.fna' #TODO automate the file name expansion to add .fai
    conda:
        "samtools-1.17"
    threads: 1
    shell:
        """
        wget -k {input.genome_gz};
        samtools faidx resources/ref/GCF_000298735.2_genomic.fna
        
        """


rule bcftools_VCF: #TODO
    input:
        host_bams = expand("results/{library}/06_host_alignment/{samples}.sorted.bam", library = LIBRARY, samples = FIDs),
        bcf_index = 'resources/ref/GCF_000298735.2_genomic.fna',
    output:
        host_vcf = os.path.join("results", LIBRARY, "06_host_alignment", (LIBRARY + ".merged.host.vcf")),
    log:
        os.path.join("results", LIBRARY, "logs", "bcftools", "bcftools_VCF.log"),
    benchmark:
        os.path.join("results", LIBRARY, "benchmarks", "bcftools_VCF.txt"),
    conda:
        "bcftools-1.19"
    threads: 24
    resources:
        mem_gb = lambda wildcards, attempt: 32 + ((attempt - 1) * 32),
        time = lambda wildcards, attempt: 720 + ((attempt - 1) * 720),
        partition = "compute"
    shell:
        "bcftools mpileup --threads {threads} --skip-indels --annotate AD --output-type u --fasta-ref {input.bcf_index} {input.host_bams} "
        "| bcftools call --consensus-caller --variants-only - "
        "| bcftools view --max-alleles 2 - "
        "> {output.host_vcf} "


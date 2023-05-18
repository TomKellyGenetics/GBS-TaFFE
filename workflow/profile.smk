# 2022 Benjamin J Perry
# MIT License
# Copyright (c) 2022 Benjamin J Perry
# Version: 1.0
# Maintainer: Benjamin J Perry
# Email: ben.perry@agresearch.co.nz


configfile: "config/config.yaml"


import os


wildcard_constraints:
     sample="[a-zA-Z0-9]+"


def get_passing_FIDs(seqkitRawOut):
    import pandas as pd
    qc_stats = pd.read_csv(seqkitRawOut, delimiter = "\s+")
    qc_stats["num_seqs"] = qc_stats["num_seqs"].str.replace(",", "").astype(int)
    qc_passed = qc_stats.loc[qc_stats["num_seqs"].astype(int) > 50000]
    return qc_passed['file'].str.split("/").str[-1].str.split(".").str[0].tolist()


(FIDs,) = glob_wildcards("results/02_kneaddata/{sample}.fastq")

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
        "results/kraken2.counts.tsv",
        "results/bracken.k2.counts.tsv",
        "results/centrifuge.counts.tsv",

        "results/centrifuge.counts.biom",
        "results/kraken2.counts.biom",
        "results/bracken.k2.counts.biom",

        expand("results/03_humann3Uniref50EC/{sample}_pathcoverage.tsv", sample=FID),


localrules:
    generateCentrifugeSampleSheet,


rule generateCentrifugeSampleSheet:
    output:
        sampleSheet = "resources/centrifugeSampleSheet.tsv",
    threads: 2
    shell:
        "./workflow/scripts/generate_centrifuge_sample_sheet.sh -d results/02_kneaddata -p fastq -o {output.sampleSheet} "


rule centrifugeGTDB:
    input:
        sampleSheet = "resources/centrifugeSampleSheet.tsv",
    output:
        out = expand("results/03_centrifuge/{sample}.GTDB.centrifuge", sample = FIDs),
        report = expand("results/03_centrifuge/{sample}.GTDB.centrifuge.report", sample = FIDs),
    log:
        "logs/centrifuge.GTDB.multi.log",
    benchmark:
        "benchmarks/centrifugeGTDB.txt"
    conda:
        "centrifuge"
    threads: 32
    resources:
        mem_gb = lambda wildcards, attempt: 140 + ((attempt - 1) + 20),
        time = "06:00:00",
    shell:
        "centrifuge "
        "-x /bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/centrifuge/GTDB "
        "--sample-sheet {input.sampleSheet} "
        "-t "
        "--threads {threads} "
        "2>&1 | tee {log}"


rule centrifugeKrakenReport:
    input:
        centrifuge = "results/03_centrifuge/{sample}.GTDB.centrifuge",
    output:
        centrifugeKraken2 = "results/03_centrifuge/{sample}.centrifuge",
    log:
        "logs/centrifugeKrakenReport/{sample}.centrifuge.to.kraken2.log",
    benchmark:
        "benchmarks/centrifugeKrakenReport.{sample}.txt"
    conda:
        "centrifuge"
    threads: 2
    shell:
        "centrifuge-kreport "
        "-x /bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/centrifuge/GTDB "
        "{input.centrifuge} > "
        "{output.centrifugeKraken2}"


rule taxpastaCentrifugeTable:
    input:
        expand("results/03_centrifuge/{sample}.centrifuge", sample = FIDs),
    output:
        "results/centrifuge.counts.tsv",
    benchmark:
        "benchmarks/taxpastaCentrifugeTable.{sample}.txt"
    conda:
        "taxpasta"
    threads: 2
    shell:
        "taxpasta merge "
        "-p centrifuge "
        "-o {output} "
        "--output-format TSV "
        "--taxonomy /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/centrifuge "
        "--add-name "
        "--add-rank "
        "--add-lineage "
        "--summarise-at genus "
        "{input} "


rule taxpastaCentrifugeBiom:
    input:
        expand("results/03_centrifuge/{sample}.centrifuge", sample = FIDs),
    output:
        "results/centrifuge.counts.biom",
    benchmark:
        "benchmarks/taxpastaCentrifugeBiom.{sample}.txt"
    conda:
        "taxpasta"
    threads: 2
    shell:
        "taxpasta merge "
        "-p centrifuge "
        "-o {output} "
        "--output-format BIOM "
        "--taxonomy /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/centrifuge "
        "--add-name "
        "--summarise-at genus "
        "{input} "


rule brackenCentrifugeSpecies:
    input:
        centrifugeKraken2='results/03_centrifuge/{sample}.GTDB.centrifuge.k2report',
    output:
        braken='results/04_braken/{sample}.GTDB.centrifuge.k2report.T1.bracken.species',
        brakenReport='results/04_braken/{sample}.GTDB.centrifuge.k2report.T1.bracken.species.report',
    log:
        'logs/centrifuge.bracken.species.{sample}.GTDB.log'
    benchmark:
        "benchmarks/brackenCentrifugeSpecies.{sample}.txt"
    conda:
        'kraken2'
    threads: 2 
    shell:
        'bracken '
        '-d /bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/kraken/GTDB ' #TODO config
        '-i {input.centrifugeKraken2} '
        '-o {output.braken} '
        '-w {output.brakenReport} '
        '-r 80 '
        '-l S '
        '-t 1 '
        '&> {log} '


#KRAKEN2 RULES
rule kraken2GTDB:
    input:
        KDRs = "results/02_kneaddata/{sample}.fastq",
    output:
        k2OutputGTDB = "results/03_kraken2GTDB/{sample}.k2",
        k2ReportGTDB = "results/03_kraken2GTDB/{sample}.kraken2",
    log:
        "logs/kraken2GTDB.{sample}.GTDB.log",
    benchmark:
        "benchmarks/kraken2GTDB.{sample}.txt"
    conda:
        "kraken2"
    threads: 18
    resources:
        # dynamic memory allocation: start with 400G and increment by 20G with every failed attempt 
        mem_gb = lambda wildcards, attempt: 360 + ((attempt - 1) * 20),
    shell:
        "kraken2 "
        "--use-names "
        "--quick "
        "--db /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/kraken/GTDB " #TODO config
        "-t {threads} "
        "--report {output.k2ReportGTDB} "
        "--report-minimizer-data "
        "{input.KDRs} "
        "--output {output.k2OutputGTDB} "
        "2>&1 | tee {log} "


rule taxpastaKraken2:
    input:
        expand("results/03_kraken2GTDB/{sample}.kraken2", sample = FIDs),
    output:
        "results/kraken2.counts.tsv",
    benchmark:
        "benchmarks/taxpastaKraken2.{sample}.txt"
    conda:
        "taxpasta"
    shell:
        "taxpasta merge "
        "-p kraken2 "
        "-o {output} "
        "--output-format TSV "
        "--taxonomy /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/kraken/GTDB/taxonomy " #TODO config
        "--add-name "
        "--add-rank "
        "--add-lineage "
        "--summarise-at genus "
        "{input} "


rule taxpastaKraken2Biom:
    input:
        expand("results/03_kraken2GTDB/{sample}.kraken2", sample = FIDs),
    output:
        "results/kraken2.counts.biom",
    benchmark:
        "benchmarks/taxpastaKraken2Biom.{sample}.txt"
    conda:
        "taxpasta"
    shell:
        "taxpasta merge "
        "-p kraken2 "
        "-o {output} "
        "--output-format BIOM "
        "--taxonomy /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/kraken/GTDB/taxonomy " #TODO config
        "--add-name "
        "--summarise-at genus "
        "{input} "

# BRACKEN RULES
rule brackenSpecies:
    input:
        k2ReportGTDB = "results/03_kraken2GTDB/{sample}.kraken2",
    output:
        bOutput = "results/03_brackenSpecies/{sample}.bracken",
        bReport = "results/03_brackenSpecies/{sample}.br",
    log:
        "logs/brackenSpecies.{sample}.log",
    benchmark:
        "benchmarks/brackenSpecies.{sample}.txt"
    conda:
        "kraken2"
    threads: 2
    shell:
        "bracken "
        "-d /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/kraken/GTDB " #TODO config
        "-i {input.k2ReportGTDB} "
        "-o {output.bOutput} "
        "-w {output.bReport} "
        "-r 80 "
        "-l S "
        "-t 10 " # Necessary to get floating point counts to sum to 1.0 in taxpasta
        "&> {log} "


rule taxpastaKraken2Bracken:
    input:
        expand("results/03_brackenSpecies/{sample}.bracken", sample = FIDs),
    output:
        "results/bracken.k2.counts.tsv",
    benchmark:
        "benchmarks/taxpastaKraken2Bracken.{sample}.txt"
    conda:
        "taxpasta"
    shell:
        "taxpasta merge "
        "-p bracken "
        "-o {output} "
        "--output-format TSV "
        "--taxonomy /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/kraken/GTDB/taxonomy " #TODO config
        "--add-name "
        "--add-rank "
        "--add-lineage "
        "--summarise-at species "
        "{input} "


rule taxpastaKraken2BrackenBiom:
    input:
        expand("results/03_brackenSpecies/{sample}.bracken", sample = FIDs),
    output:
        "results/bracken.k2.counts.biom",
    benchmark:
        "benchmarks/taxpastaKraken2BrackenBiom.{sample}.txt"
    conda:
        "taxpasta"
    shell:
        "taxpasta merge "
        "-p bracken "
        "-o {output} "
        "--output-format BIOM "
        "--taxonomy /dataset/2022-BJP-GTDB/scratch/2022-BJP-GTDB/kraken/GTDB/taxonomy " #TODO config
        "--add-name "
        "--summarise-at species "
        "{input} "


# HUMANN# RULES
rule humann3Uniref50EC:
    input:
        kneaddataReads = "results/02_kneaddata/{sample}.fastq",
    output:
        genes = "results/03_humann3Uniref50EC/{sample}_genefamilies.tsv",
        pathways = "results/03_humann3Uniref50EC/{sample}_pathabundance.tsv",
        pathwaysCoverage = "results/03_humann3Uniref50EC/{sample}_pathcoverage.tsv",
    log:
        "logs/humann3.{sample}.uniref50EC.log",
    benchmark:
        "benchmarks/humann3Uniref50EC.{sample}.txt"
    conda:
        "biobakery"
    threads: 16
    resources:
        mem_gb = lambda wildcards, attempt: 24 + ((attempt - 1) + 12),
    message:
        "humann3 profiling with uniref50EC: {wildcards.sample}\n"
    shell:
        "humann3 "
        "--memory-use maximum "
        "--threads {threads} "
        "--bypass-nucleotide-search "
        "--search-mode uniref50 "
        "--protein-database /bifo/scratch/2022-BJP-GTDB/biobakery/humann3/unirefECFilt " #TODO config
        "--input-format fastq "
        "--output results/03_humann3Uniref50EC "
        "--input {input.kneaddataReads} "
        "--output-basename {wildcards.sample} "
        "--o-log {log} "
        "--remove-temp-output "

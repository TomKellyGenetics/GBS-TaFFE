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
    print(f"Env TMPDIR = {os.environ.get('TMPDIR', '<n/a>')}")
    os.system('echo "  PYTHON VERSION: $(python --version)"')
    os.system('echo "  CONDA VERSION: $(conda --version)"')

library_keyfile=f"resources/{config['gquery']['libraries']}.keyfile.tsv"
# if no keyfile present in resources/, spew keyfile for GBS library
if not os.path.isfile(library_keyfile):
    print("Generating Keyfile: " + library_keyfile)
    shell("mkdir -p resources")
    shell(f"gquery -p no_unpivot -t gbs_keyfile -b library {config['gquery']['libraries']} > {library_keyfile}")

# Extracthe unique factids for samples to use as 'wildcards'
def getFIDs(keyfile):
    '''
    :param keyfile: gquery generated for library
    :return: list of FIDs
    '''
    import pandas as pd
    keys=pd.read_csv(keyfile, sep='\t', header=0)
    return keys['factid'].tolist()

print(f"Extracting factid for {config['gquery']['libraries']}...")
FIDs = getFIDs(library_keyfile)

print("Found: ")
for entry in FIDs:
    print(entry)

rule all:
    input:
        expand('results/04_brakenGTDB/{samples}.GTDB.k2report.bracken.report', samples = FIDs),
        expand('results/04_humannUniref50EC/{samples}_kneaddata_pathabundance.tsv', samples = FIDs),
        # expand('results/04_centrifugeGTDB/{samples}.GTDB.centrifuge.report', samples = FIDs),
        expand('results/04_kmcpGTDB/{samples}.search.tsv.gz', samples = FIDs),
        'results/00_qc/ReadsMultiQCReport.html',
        'results/00_qc/KDRReadsMultiQCReport.html'



localrules: generateBarcodes
rule generateBarcodes:
    output:
        barcodes = 'resources/gquery.barcodes.fasta'
    threads: 2
    log:
        'logs/1_gqueryGenerateBarcodes.log'
    params:
        libraries = config['gquery']['libraries'],
    message:
        'Generating barcode file for: {params.libraries}...\n'
    shell:
        'gquery '
        '-t gbs_keyfile '
        '-b library -p "columns=factid,barcode;fasta;noheading;no_unpivot" '
        '{params.libraries} > '
        '{output.barcodes} 2> '
        '{log}'



rule cutadapt: # demultiplexing GBS reads
    input:
        barcodes = rules.generateBarcodes.output.barcodes,
        lane01 = config['novaseq']['lane01'],
        lane02 = config['novaseq']['lane02'],
    output:
        expand('results/01_cutadapt/{samples}.fastq.gz', samples = FIDs),
    conda:
        'cutadapt'
        # 'docker://quay.io/biocontainers/cutadapt:4.1--py310h1425a21_1'
    threads: 16
    resources:
        mem_gb=32,
    message:
        'Demultiplexing lanes...'
    shell:
        'zcat {input.lane01} {input.lane02} | '
        'cutadapt '
        '-j {threads} '
        '--discard-untrimmed '
        '--no-indels '
        '-g ^file:{input.barcodes} '
        r'-o "results/01_cutadapt/{{name}}.fastq.gz" '
        '-' # indicates stdin



rule fastqc:
    input:
        fastq = 'results/01_cutadapt/{samples}.fastq.gz'
    output:
        html = 'results/00_qc/fastqc/{samples}_fastqc.html',
        zip = 'results/00_qc/fastqc/{samples}_fastqc.zip'
    conda:
        'fastqc'
        # 'docker://biocontainers/fastqc:v0.11.9_cv8'
    threads: 2
    message:
        'Running QC on reads: {wildcards.samples}\n'
    shell:
        'fastqc '
        '-o results/00_qc/fastqc/ '
        '-q '
        '-t {threads} '
        '{input.fastq}'



rule multiQC:
    input:
        fastqc= expand('results/00_qc/fastqc/{samples}_fastqc.zip', samples = FIDs)
    output:
        multiQC='results/00_qc/ReadsMultiQCReport.html'
    conda:
        'multiqc'
        # 'docker://quay.io/biocontainers/multiqc:1.12--pyhdfd78af_0'
    shell:
        'multiqc '
        '-n results/00_qc/ReadsMultiQCReport '
        '-s '
        '-f '
        '--interactive '
        '{input.fastqc}'



#TODO Rule to Build Rambv2 index



rule kneaddata:
    input:
        reads = 'results/01_cutadapt/{samples}.fastq.gz',
    output:
        trimReads = temp('results/02_kneaddata/{samples}_kneaddata.trimmed.fastq'),
        trfReads = temp('results/02_kneaddata/{samples}_kneaddata.repeats.removed.fastq'),
        ovineReads = temp('results/02_kneaddata/{samples}_kneaddata_GCF_016772045.1-ARS-UI-Ramb-v2.0_bowtie2_contam.fastq'),
        KDRs = 'results/02_kneaddata/{samples}_kneaddata.fastq',
        readStats = 'results/02_kneaddata/{samples}.read.stats.txt'
    conda:
        'biobakery'
    log:
        'logs/kneaddata/{samples}.kneaddata.log'
    threads: 6
    resources:
        mem_gb=8,
        time='02:00:00'
    message:
        'kneaddata: {wildcards.samples}\n'
    shell:
        'kneaddata '
        '--trimmomatic-options "MINLEN:60 ILLUMINACLIP:/home/perrybe/conda-envs/biobakery/share/trimmomatic-0.39-2/adapters/illuminaAdapters.fa:2:30:10 SLIDINGWINDOW:4:20 MINLEN:50 CROP:80" '
        '--input {input.reads} '
        '-t {threads} '
        '--log-level INFO '
        '--log {log} '
        '--trimmomatic /home/perrybe/conda-envs/biobakery/share/trimmomatic '
        '--sequencer-source TruSeq3 '
        '-db ref/Rambv2/GCF_016772045.1-ARS-UI-Ramb-v2.0 '
        '-o results/02_kneaddata && '
        'seqkit stats -j {threads} -a results/02_kneaddata/{wildcards.samples}*.fastq > {output.readStats}'



#TODO Compress output reads



rule fastqcKDRs:
    input:
        fastq = 'results/02_kneaddata/{samples}_kneaddata.fastq'
    output:
        'results/00_qc/fastqcKDR/{samples}_kneaddata_fastqc.zip'
    conda:
        'fastqc'
        # 'docker://biocontainers/fastqc:v0.11.9_cv8'
    threads: 2
    message:
        'Running QC on reads: {wildcards.samples}\n'
    shell:
        'fastqc '
        '-o results/00_qc/fastqcKDR/ '
        '-q '
        '-t {threads} '
        '{input.fastq}'



rule multiQCKDRs:
    input:
        fastqc= expand('results/00_qc/fastqcKDR/{samples}_kneaddata_fastqc.zip', samples = FIDs)
    output:
        'results/00_qc/KDRReadsMultiQCReport.html'
    conda:
        'multiqc'
        # 'docker://quay.io/biocontainers/multiqc:1.12--pyhdfd78af_0'
    shell:
        'multiqc '
        '-n results/00_qc/KDRReadsMultiQCReport '
        '-s '
        '-f '
        '--interactive '
        '{input.fastqc}'



rule kraken2GTDB:
    input:
        KDRs=rules.kneaddata.output.KDRs,
        GTDB='/bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/kraken/GTDB',        
    output:
        k2OutGTDB='results/04_kraken2GTDB/{samples}.GTDB.k2',
        k2ReportGTDB='results/04_kraken2GTDB/{samples}.GTDB.k2report'
    log:
        'logs/{samples}.kraken2.GTDB.log'
    conda:
        'kraken2'
    threads: 20 
    resources: 
        partition = "inv-bigmem,inv-bigmem-fast",
        mem_gb = lambda wildcards, attempt: 325 + ((attempt -1) * 50)
    shell:
        'kraken2 '
        '--db {input.GTDB} '
        '--threads {threads} '
        '--report {output.k2ReportGTDB} '
        '--report-minimizer-data '
        '{input.KDRs} > {output.k2OutGTDB}'



rule brackenGTDB:
    input:
        k2report=rules.kraken2GTDB.output.k2ReportGTDB,
    output:
        braken='results/04_brakenGTDB/{samples}.GTDB.k2report.bracken',
        brakenReport='results/04_brakenGTDB/{samples}.GTDB.k2report.bracken.report',
    log:
        'logs/{samples}.bracken.GTDB.log'
    conda:
        'kraken2'
    threads: 2 
    shell:
        'bracken '
        '-d /bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/kraken/GTDB '
        '-i {input.k2report} '
        '-o {output.braken} '
        '-w {output.brakenReport} '
        '-r 80 '
        '-l S '
        '-t 10 '
        '&> {log} '



rule humann3Uniref50EC:
    input:
        KDRs=rules.kneaddata.output.KDRs
    output:
        genes = 'results/04_humann3Uniref50EC/{samples}_kneaddata_genefamilies.tsv',
        pathways = 'results/04_humann3Uniref50EC/{samples}_kneaddata_pathabundance.tsv',
        pathwaysCoverage = 'results/04_humann3Uniref50EC/{samples}_kneaddata_pathcoverage.tsv'
    log:
        'logs/{samples}.human3.log'
    conda:
        'biobakery'
    threads: 18
    resources:
        mem_gb= lambda wildcards, attempts: 24 + ((attempts - 1) + 12) 
    message:
        'humann3 profiling with uniref50EC: {wildcards.samples}\n'
    shell:
        'humann3 '
        '--memory-use minimum '
        '--threads {threads} '
        '--bypass-nucleotide-search '
        '--search-mode uniref50 '
        '--protein-database /bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/biobakery/humann3/unirefECFilt '
        '--input-format fastq '
        '--output results/04_humann3Uniref50EC '
        '--input {input.KDRs} '
        '--output-basename {wildcards.samples} '
        '--o-log {log} '



rule kmcpGTDBSearch:
    input:
        kmcpGTDB='/bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/kmcp/gtdb.kmcp',
	KDRs=rules.kneaddata.output.KDRs,
    output:
        search='results/04_kmcpGTDB/{samples}.GTDB.kmcp.search',
    log:
        'logs/{samples}.kmcp.search.GTDB.log'
    conda:
        'kmcp'
    threads:12
    resources: 
        mem_gb= lambda wildcards, attempts: 104 + ((attempts - 1) * 24),
        partition="inv-bigmem,inv-bigmem-fast,inv-iranui-fast,inv-iranui"
    shell:
        'kmcp search '
        '-w '
        '--threads {threads} '
        '--db-dir {input.kmcpGTDB} '
        '{input.KDRs} '
        '-o {output.search} '
        '--log {log}'     



rule kmcpGTDBProfile:
    input:
        kmcpSearch=rules.kmcpGTDBSearch.output.search,
        kmcpTaxdump='/bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/kcmp/gtdb-taxdump/R207',
        taxid='/bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/kcmp/taxid.map',
    output:
        profile='results/04_kmcpGTDB/{samples}.GTDB.kmcp.report',
    log:
        'logs/{samples}.kmcp.profile.log'
    conda:
        'kmcp'
    threads: 8 
    resources: 
        mem_gb=6,
    shell:
        'kmcp profile '
        '--mode 1 '
        '--threads {threads} '
        '-X {input.kmcpTaxdump} '
        '-T {input.taxid} '
        '-o {output.profile} '
        '--log {log} '
        '{input.kmcpSearch} '



rule centrifugeGTDB:
    input:
        CFGTDB='/bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/centrifuge/GTDB' ,
        KDRs=rules.kneaddata.output.KDRs,
    output:
        report='results/04_centrifuge/{samples}.GTDB.centrifuge.report',
        out='results/04_centrifuge/{samples}.GTDB.centrifuge',
    log:
        'logs/centrifuge/{samples}.centrifuge.log'
    conda:
        'centrifuge'
    threads: 8
    resources:
        mem_gb= lambda wildacards, attempts: 132 + ((attempts -1) + 20),
    shell:
        'centrifuge ' 
        '-x {input.CFGTDB} '
        '-U {input.KDRs} '
        '-S {output.out} ' 
        '--report-file {output.report} '
        '-t '
        '--threads {threads} '
        '&> {log} '



# centrifuge-kreport -x /bifo/scratch/2022-BJP-GTDB/2022-BJP-GTDB/centrifuge/GTDB rumen.mg.test.centrifuge.out > rumen.mg.test.centrifuge.kreport




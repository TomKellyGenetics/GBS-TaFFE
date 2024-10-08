#!/bin/bash
### Wrapper script for launching snakemake workflows ###
echo "Launching snakemake workflow..."
sleep 3
echo "Beginning executing on: $(date)"

#echo "Demultiplexing SQ libraries"
#snakemake --profile config/slurm --snakefile workflow/demux.smk
#echo "Demultiplexing completed"

echo "Preparing fastq for profiling."

echo "Collecting SQ runs: $(ls -r results | grep SQ)"

for i in $(ls -r results | grep SQ); 
do
	echo $i;
	
	snakemake --profile config/slurm_profiles/eRI --config LIBRARY=$i --snakefile workflow/GBS-TaFFE.smk results/$i/00_QC/seqkit.report.KDR.txt &&
	
	snakemake --profile config/slurm_profiles/eRI --config LIBRARY=$i --snakefile workflow/Ref-Free.smk &&
	
	ln -s /scratch/2023-mbie-rumen-gbs/GBS-TaFFE/results/$i /projects/2024-gbs_microbiomes_processing/Pipeline/ 

done


echo "snakemake run completed: $(date)"

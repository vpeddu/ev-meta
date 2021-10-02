//TODO: rebuild database but with taxids or full names appended 

process Trimming_FastP { 
//conda "${baseDir}/env/env.yml"
publishDir "${params.OUTPUT}/fastp_PE/${base}", mode: 'symlink', overwrite: true
container "bromberglab/fastp"
beforeScript 'chmod o+rw .'
cpus 6
input: 
    tuple val(base), file(r1), file(r2)
output: 
    tuple val(base), file("${base}.trimmed.R1.fastq.gz"), file("${base}.trimmed.R2.fastq.gz")
    tuple val(base), file("${base}.trimmed.R1.fastq.gz")
    file "*"


script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 
echo "running fastp on ${base}"
fastp -w ${task.cpus} \
    -i ${r1} \
    -I ${r2} \
    -o ${base}.trimmed.R1.fastq.gz \
    -O ${base}.trimmed.R2.fastq.gz
"""
}
process Low_complexity_filtering { 
//conda "${baseDir}/env/env.yml"
publishDir "${params.OUTPUT}/fastp_PE/${base}", mode: 'symlink', overwrite: true
container "quay.io/biocontainers/bbmap:38.76--h516909a_0"
beforeScript 'chmod o+rw .'
cpus 6
input: 
    tuple val(base), file(r1), file(r2)
output: 
    tuple val(base), file("${base}.lcf_filtered.R1.fastq.gz"), file("${base}.lcf_filtered.R2.fastq.gz")

script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

bbduk.sh \
    in1=${r1} in2=${r2} \
    out1=${base}.lcf_filtered.R1.fastq.gz out2=${base}.lcf_filtered.R2.fastq.gz \
    entropy=0.7 \
    entropywindow=50 \
    entropyk=4 
"""
}

//TODO: delete intermediate bam for space savings
process Host_depletion { 
publishDir "${params.OUTPUT}/Star_PE/${base}", mode: 'symlink', overwrite: true
container "quay.io/biocontainers/star:2.7.9a--h9ee0642_0"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), file(r1), file(r2)
    file starindex
output: 
    file "${base}.star*"
    file "${base}.starAligned.out.bam"
    tuple val("${base}"), file("${base}.starUnmapped.out.mate1.fastq.gz"), file("${base}.starUnmapped.out.mate2.fastq.gz")
script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 
STAR   \
    --runThreadN ${task.cpus}  \
    --genomeDir ${starindex}   \
    --readFilesIn ${r1} ${r2} \
    --readFilesCommand zcat      \
    --outSAMtype BAM Unsorted \
    --outReadsUnmapped Fastx \
    --outFileNamePrefix ${base}.star  

mv ${base}.starUnmapped.out.mate1 ${base}.starUnmapped.out.mate1.fastq
mv ${base}.starUnmapped.out.mate2 ${base}.starUnmapped.out.mate2.fastq

gzip ${base}.starUnmapped.out.mate1.fastq
gzip ${base}.starUnmapped.out.mate2.fastq
"""
}

process Kraken_prefilter { 
publishDir "${params.OUTPUT}/Interleave_FASTQ/${base}", mode: 'symlink', overwrite: true
container "staphb/kraken2"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), file(r1), file(r2)
    file kraken2_db
output: 
    stdout krakenoutCh
    //tuple val("${base}"), file("${base}.kraken2.report")
script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

kraken2 --db ${kraken2_db} \
    --threads ${task.cpus} \
    --classified-out ${base}.kraken2.classified \
    --output ${base}.kraken2.output \
    --report ${base}.kraken2.report \
    --gzip-compressed \
    --unclassified-out ${base}.kraken2.unclassified \
    ${r1} ${r2}


cat  ${base}.kraken2.report | awk '/\\tG\\t/{print "base "\$5}'

"""
}

process Extract_db { 
//publishDir "${params.OUTPUT}//${base}", mode: 'symlink', overwrite: true
//container "quay.io/biocontainers/star:2.7.9a--h9ee0642_0"
container 'quay.io/vpeddu/evmeta'
beforeScript 'chmod o+rw .'
cpus 1
input: 
    tuple val(base), file(report)
    file fastadb
    file extract_script
output: 
    tuple val("${base}"), file("${base}.species.fasta.gz")


script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

# python3 ${extract_script} ${report} ${fastadb}

#grep -P "\tG\t" ${report} | cut -f5 | parallel {}.genus.fasta.gz /scratch/vpeddu/genus_level_download/test_index/

for i in `grep -P "\tG\t" ${report} | cut -f5`
do
echo adding \$i
cat ${fastadb}/\$i.genus.fasta.gz >> species.fasta.gz
done


mv species.fasta.gz ${base}.species.fasta.gz

"""
}

//TODO: create containre with Minimap2 and samtools so we can get rid of intermediate sam for space savings
process Minimap2 { 
//conda "${baseDir}/env/env.yml"
publishDir "${params.OUTPUT}/Minimap2/${base}", mode: 'symlink'
container "staphb/minimap2"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), val(genus), file(r1), file(r2)
    file fastadb

output: 
    tuple val("${base}"), file("${base}.${genus}.minimap2.sam")

script:
"""
#!/bin/bash

#logging
echo "ls of directory" 
ls -lah 

echo "using db ${fastadb}/${genus}.fasta.gz"
echo "read files are ${r1} and ${r2}"

echo "running Minimap2 on ${base}"
#TODO: FILL IN MINIMAP2 COMMAND 
minimap2 \
    -ax sr \
    -t ${task.cpus} \
    -K 16G \
    --split-prefix \
    -2 \
    ${fastadb}/${genus}.fasta.gz \
    ${r1} ${r2} > \
    ${base}.${genus}.minimap2.sam
"""
}

//TODO: bring back the unclassified bam output
process Sam_conversion { 
publishDir "${params.OUTPUT}/sam_conversion/${base}", mode: 'symlink', overwrite: true
container "staphb/samtools"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), file(sam)
output: 
    tuple val("${base}"), file("${base}.final.sorted.bam"), file("${base}.final.sorted.bam.bai")
    //file "${base}.unclassfied.bam"

script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

for i in *.sam
do
    if [ -s \$i ]
    then
        samtools view -Sb -@  ${task.cpus} -F 4 \$i > \$i.temp.bam
        samtools sort -@ ${task.cpus} \$i.temp.bam > \$i.sorted.temp.bam
    else
        echo "\$i does not exist"
    fi
done

samtools merge -@ ${task.cpus} -o ${base}.final.sorted.bam *.sorted.temp.bam

samtools index ${base}.final.sorted.bam

#samtools view -Sb -@  ${task.cpus} -f 4 ${sam} > ${base}.unclassfied.bam


"""
}

process Classify { 
publishDir "${params.OUTPUT}/Classification/${base}", mode: 'symlink', overwrite: true
container 'quay.io/vpeddu/evmeta'
beforeScript 'chmod o+rw .'
errorStrategy 'ignore'
cpus 8
input: 
    tuple val(base), file(bam), file(bamindex)
    file taxdump
    file classify_script
    file accessiontotaxid
output: 
    tuple val("${base}"), file("${base}.prekraken.tsv")
    file "${base}.accession_DNE.txt"

script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 
#mv taxonomy/taxdump.tar.gz .
#tar -xvzf taxdump.tar.gz
cp viral/*.dmp .
python3 ${classify_script} ${bam} ${base} ${accessiontotaxid}
"""
}

process Write_report { 
publishDir "${params.OUTPUT}/", mode: 'symlink', overwrite: true
container "evolbioinfo/krakenuniq:v0.5.8"
beforeScript 'chmod o+rw .'
errorStrategy 'ignore'
cpus 8
input: 
    tuple val(base), file(prekraken)
    file krakenuniqdb
output: 
    file "${base}.final.report.tsv"

script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

krakenuniq-report --db ${krakenuniqdb} \
 --taxon-counts \
  ${prekraken} > ${base}.final.report.tsv
"""
}
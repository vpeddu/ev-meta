process NanoFilt { 
//conda "${baseDir}/env/env.yml"
publishDir "${params.OUTPUT}/Nanofilt/${base}", mode: 'symlink', overwrite: true
container " quay.io/biocontainers/nanofilt:2.8.0--py_0"
beforeScript 'chmod o+rw .'
cpus 6
input: 
    tuple val(base), file(r1)
output: 
    tuple val(base), file("${base}.filtered.fastq.gz")
    file "*"


script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 
echo "running Nanofilt on ${base}"

gunzip -c ${r1} | NanoFilt -q 9 \
        --maxlength 5000 \
        --length 200 | gzip > ${base}.filtered.fastq.gz

"""
}

process NanoPlot { 
//conda "${baseDir}/env/env.yml"
publishDir "${params.OUTPUT}/NanoPlot/${base}", mode: 'symlink', overwrite: true
container "quay.io/biocontainers/nanoplot:1.38.1--pyhdfd78af_0"
beforeScript 'chmod o+rw .'
cpus 2
input: 
    tuple val(base), file(r1) 
output: 
    file "*"

script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

NanoPlot -t ${task.cpus} \
    -p ${base} \
    --fastq ${r1} \
    --title ${base} 
"""
}

process Host_depletion_nanopore { 
publishDir "${params.OUTPUT}/Host_filtered/${base}", mode: 'symlink', overwrite: true
container "staphb/minimap2"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), file(r1)
    file minimap2_host_index
output: 
    tuple val("${base}"), file("${base}.host_filtered.sam")
script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

minimap2 \
    -ax map-ont \
    -t ${task.cpus} \
    -2 \
    ${minimap2_host_index} \
    ${r1} > \
    ${base}.host_filtered.sam
"""
}

process Host_depletion_extraction_nanopore { 
publishDir "${params.OUTPUT}/Host_filtered/${base}", mode: 'symlink', overwrite: true
container "staphb/samtools"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), file(sam)
output: 
    tuple val("${base}"), file("${base}.host_filtered.fastq.gz")
script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

samtools fastq -n -f 4 ${sam} | gzip > ${base}.host_filtered.fastq.gz
"""
}

process MetaFlye { 
publishDir "${params.OUTPUT}/MetaFlye/${base}", mode: 'symlink', overwrite: true
container "quay.io/biocontainers/flye:2.9--py27h6a42192_0"
beforeScript 'chmod o+rw .'
errorStrategy 'ignore'
cpus 16
input: 
    tuple val(base), file(r1)
output: 
    tuple val("${base}"), file("${base}.flye.fasta")
script:
"""
#!/bin/bash
#logging
echo "ls of directory" 
ls -lah 

flye --nano-corr ${r1} --out-dir ${base}.flye \
    -t ${task.cpus} \
    --meta \

mv ${base}.flye/assembly.fasta ${base}.flye.fasta

"""
}


process Kraken_prefilter_nanopore { 
publishDir "${params.OUTPUT}/Kraken_prefilter/${base}", mode: 'symlink', overwrite: true
container "staphb/kraken2"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), file(flye_assembly)
    file kraken2_db
output: 
    stdout 
    val "${base}"
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
    ${flye_assembly} 

cat  ${base}.kraken2.report | awk '/\\tG\\t/{print "base "\$5}'

"""
}


process Minimap2_nanopore { 
//conda "${baseDir}/env/env.yml"
publishDir "${params.OUTPUT}/Minimap2/${base}", mode: 'symlink'
container "staphb/minimap2"
beforeScript 'chmod o+rw .'
cpus 8
input: 
    tuple val(base), val(genus), file(r1)
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
echo "read file is ${r1}"

echo "running Minimap2 on ${base}"
#TODO: FILL IN MINIMAP2 COMMAND 
minimap2 \
    -ax map-ont \
    -t ${task.cpus} \
    -2 \
    --split-prefix \
    -K16G \
    ${fastadb}/${genus}.fasta.gz \
    ${r1} > \
    ${base}.${genus}.minimap2.sam
"""
}

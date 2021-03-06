# aPOMP: a Pore Metagenomic Pipeline

## Introduction
aPOMP is a portable metagenomics pipeline designed for use with Oxford Nanopore long read sequencing data. 

## Workflow 
aPOMP options 

# *required flags
flag| description
-----|-----
*--NANOPORE/--ILLUMINA|sequencing platform used
*--INPUT\_FOLDER|folder containing input FASTQs (illumina must be paired)  
*--INDEX|path to aPOMP index folder
*--OUTPUT|output folder
--IDENTIFY\_RESISTANCE\_PLASMIDS|assemble and identify resistant plasmids 
--CLEAN\_RIBOSOME\_TRNA|filter out ribosomal and tRNA sequences before classification 
--EGGNOG|identify orthologous groups in unclassified reads using  the Eggnog-mapper
--MINIMAPSPLICE|run Minimap2 with preset -ax splice (default -ax map-ont)
--KRAKEN2\_THRESHOLD [int]|discard Kraken2 results containing less than this many reads at or below the genus level (default 10)
--LOW_COMPLEXITY_FILTER_NANOPORE|run low complexity filtering on nanopore samples
--METAFLYE|run metaflye before all classifications. Not for use on small memory machines
--NANOFILT\_QUALITY [int]|minimum quality threshold for nanofilt (default 10) 
--NANOFILT_MINLENGTH [int]| Have Nanofilt filter out any reads smaller than this number 
--NANOFILT_MAXLENGTH [int]| Have Nanofilt filter out any reads larger than this number 

--help|display help message
## Database download 
The full aPOMP database is ~250GB and can be downloaded at <insert tarball link>. Smaller indexes are avaiable at <build smaller indexes>
* HG38 human host depletion (Minimap2, STAR)
* Full BLAST NT (downloaded 09/2021)
* Kraken PFP (downloaded 10/2021) 
* NCBI taxonomy (downloaded 09/20021)
* Eggnog DB (downloaded 12/2021)

## Nanopore workflow
quick run command:  
```
  nextflow run vpeddu/ev-meta \		
		 --NANOPORE \
		 --IDENTIFY_RESISTANCE_PLASMIDS \
   -profile standard \
		 --EGGNOG \
		 --INPUT_FOLDER <input_fastq_folder> \
		 --OUTPUT Zymo-GridION-EVEN-BB-SN_out \
		 --INDEX <index_path> \
		 --CLEAN_RIBOSOME_TRNA \
		 -with-docker 'ubuntu:18.04' \
		 -with-tower \
		 -with-report \
		 -latest \
		 -resume
```

### Read filtering 
1. Low complexity filtering (bbDuk.sh) if `--LOW_COMPLEXITY_FILTER_NANOPORE` specified
2. Read quality filtering (NanoFilt). 
  * Quality threshold adjustable with `--NANOFILT_QUALITY [int]` (default: 10) 
  * Min readlength adjustable with `--NANOFILT_MINLENGTH [int]` (default: 200)
  * Max readlength adjustable with `--NANOFILT_MAXLENGTH [int]` (default: 5000)
3. tRNA filtering (Minimap2) if `--CLEAN_RIBOSOME_TRNA` specified 
  * Reference tRNA database downloaded from http://gtrnadb.ucsc.edu/cgi-bin/GtRNAdb2-search.cgi
4. Host filtering (Minimap2, HG38 default). To specify a different host, replace the fasta in the index folder (/path_to_index/minimap2_host/new_host.fa) 
5. Plasmid extraction (Minimap2) done with alignment against plsDB v.2021_06_23_v2
  * if `--IDENTIFY_RESISTANCE_PLASMIDS` specified, plasmid reads are first assembled (`Flye --plasmid`), and then run against NCBI AMRfinder 

![alt text](https://github.com/vpeddu/ev-meta/blob/main/img/read_filtering.png)

### Alignment to NT 
1. Genus level estimation (Kraken2). 
  * Default database is plusPFP-16 from https://benlangmead.github.io/aws-indexes/k2
  * To use a different database replace the Kraken2 files in the index folder (/path_to_index/kraken2_db/<all_kraken_files>) 
2. Genus extraction (Grep/awk). By default all genera with 10 reads assigned to the genus or below are kept. Adjustable with `--KRAKEN2\_THRESHOLD [int]` (default 10)
3. NT database extraction. The index file contains all of NT organized into fasta files named by genus. This step extracts those for subsequent alignment against the filtered sample file. 
4. Genus level alignment. Each sample is aligned against each genus in a separate process (Minimap2).
* if `--MINIMAPSPLICE` is specified Minimap2 is run with -ax splice (default -ax map-ont) 
5. Aligned file collection. Aligned output for each sample is collected and merged (samtools merge) into one bam file 
6. Unaligned file collection. Unaligned output for each sample is collected. A unique list of Read IDs is used to extract the original reads from the host-filtered FASTQ 
	
![alt text](https://github.com/vpeddu/ev-meta/blob/main/img/alignment.png)
	
### Classification 
1. Merged aligned files are classified using a custom LCA algorithm (custom Python script) 
* For each read the top 10 longest alignments are used for classification. Shorter alignments are weighted lower than longer alignments. 
* `find_majority_vote` from `Taxopy` is used to determine the LCA, taking into account the weights from the mapped read lengths. 
	
![alt text](https://github.com/vpeddu/ev-meta/blob/main/img/lca.png)

2. Unassigned read counts from the alignment step (NCBI TAXID: 0) and plasmid read counts from the filtering step (NCBI TAXID: 36549) are added to clasisfication file. 
3. Output from the LCA script is fed into `Krakenuniq-report` to create a pavian readable TSV file. 
	
![alt text](https://github.com/vpeddu/ev-meta/blob/main/img/classification.png)

### Novel sequence annotation
#### only done if `--EGGNOG` specified
1. Unassigned reads are clustered (mmSeqs cluster)
2. Clustered reads are assembled (Metaflye) 
3. Assembled reads are run against eggNOG database (eggnog-mapper) 
4. Eggnog output is parsed into a pavian formatted file 
  * A custom python script parses the taxIDs from the eggnog output file and the LCA algorithm as mentioned above is run without read length weighting. 
	
![alt text](https://github.com/vpeddu/ev-meta/blob/main/img/unassigned_classification.png)


	

	
## Illumina workflow (need to update)
quick run command:  
```
  nextflow run vpeddu/ev-meta \
    --ILLUMINA \
	--INPUT_FOLDER <Input folder> \
	--OUTPUT <Output folder> \
	--INDEX <Index location>  \
	--NUCL_TYPE <RNA or DNA> \
	-with-docker ubuntu:18.04 
    -latest \
    -with-report 
```


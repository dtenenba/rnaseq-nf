/*
 * Copyright (c) 2013-2019, Centre for Genomic Regulation (CRG).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 *
 */


/*
 * Proof of concept of a RNAseq pipeline implemented with Nextflow
 *
 * Authors:
 * - Paolo Di Tommaso <paolo.ditommaso@gmail.com>
 * - Emilio Palumbo <emiliopalumbo@gmail.com>
 * - Evan Floden <evanfloden@gmail.com>
 */


/*
 * Default pipeline parameters. They can be overriden on the command line eg.
 * given `params.foo` specify on the run command line `--foo some_value`.
 */

params.reads = "s3://dtenenba-temp-encrypted-bucket/data/ggal/ggal_gut_{1,2}.fq"
params.transcriptome = "s3://dtenenba-temp-encrypted-bucket/data/ggal/ggal_1_48850000_49020000.Ggal71.500bpflank.fa"
params.outdir = "s3://dtenenba-temp-encrypted-bucket/results"
params.multiqc = "s3://dtenenba-temp-encrypted-bucket/multiqc"

log.info """\
 R N A S E Q - N F   P I P E L I N E
 ===================================
 transcriptome: ${params.transcriptome}
 reads        : ${params.reads}
 outdir       : ${params.outdir}
 """


Channel
    .fromFilePairs( params.reads, checkExists:true )
    .into { read_pairs_ch; read_pairs2_ch }


process index {
    tag "$transcriptome.simpleName"

    input:
    path transcriptome from params.transcriptome

    output:
    path 'index' into index_ch

    script:
    """
    salmon index --threads $task.cpus -t $transcriptome -i index
    """
}


process quant {
    tag "$pair_id"

    input:
    path index from index_ch
    tuple val(pair_id), path(reads) from read_pairs_ch

    output:
    path(pair_id) into quant_ch

    script:
    """
    salmon quant --threads $task.cpus --libType=U -i $index -1 ${reads[0]} -2 ${reads[1]} -o $pair_id
    """
}

process fastqc {
    tag "FASTQC on $sample_id"
    publishDir params.outdir

    input:
    tuple val(sample_id), path(reads) from read_pairs2_ch

    output:
    path "fastqc_${sample_id}_logs" into fastqc_ch

    script:
    """
    mkdir fastqc_${sample_id}_logs
    fastqc -o fastqc_${sample_id}_logs -f fastq -q ${reads}
    """
}


process multiqc {
    publishDir params.outdir, mode:'copy'
    
    input:
    path 'data*/*' from quant_ch.mix(fastqc_ch).collect()
    path config from params.multiqc

    output:
    path 'multiqc_report.html'

    script:
    """
    cp $config/* .
    echo "custom_logo: \$PWD/logo.png" >> multiqc_config.yaml
    multiqc -v .
    """
}

workflow.onComplete {
	log.info ( workflow.success ? "\nDone! Open the following report in your browser --> $params.outdir/multiqc_report.html\n" : "Oops .. something went wrong" )
}

#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/clipseq
========================================================================================
 nf-core/clipseq Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/clipseq
----------------------------------------------------------------------------------------
*/

def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/clipseq --reads '*_R{1,2}.fastq.gz' -profile docker

    Mandatory arguments:
      --input [file]                  Comma-separated file with details of samples and reads
      -profile [str]                  Configuration profile to use. Can use multiple (comma separated)
                                      Available: conda, docker, singularity, test, awsbatch, <institute> and more

    Options:
      --genome [str]                  Name of iGenomes reference

    References:                       If not specified in the configuration file or you wish to overwrite any of the references
      --fasta [file]                  Path to genome fasta reference
      --gtf [file]                    Path to genome annotation gtf reference
      --star_index [folder]           Path to genome STAR index
      --smrna_fasta [file]            Path to small RNA fasta reference

    Adapter trimming:
      --adapter [str]              Adapter to trim from reads (default: AGATCGGAAGAGC)

    Deduplication:
      --umi_separator [st]        UMI separator character in read header/name (default: :)

    Peak calling:
      --peakcaller [str]           Peak caller (options: icount, paraclu)
      --segment [file]                Path to iCount segment file
      --half_window [int]             iCount half-window size (default: 3)
      --merge_window [int]            iCount merge-window size (default: 3)
      --min_value [int]               Paraclu minimum cluster count/value (default: 10)
      --min_density_increase [int]    Paraclu minimum density increase (default: 2)
      --max_cluster_length [int]      Paraclu maximum cluster length (default: 2)

    Other options:
      --outdir [file]                 The output directory where the results will be saved
      --email [email]                 Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --email_on_fail [email]         Same as --email, except only send mail if the workflow is not successful
      --max_multiqc_email_size [str]  Theshold size for MultiQC report to be attached in notification email. If file generated by pipeline exceeds the threshold, it will not be attached (Default: 25MB)
      -name [str]                     Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic

    AWSBatch options:
      --awsqueue [str]                The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion [str]               The AWS Region for your AWS Batch job to run on
      --awscli [str]                  Path to the AWS CLI tool
    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

/*
================================================================================
SET UP CONFIGURATION VARIABLES
================================================================================
*/

// Check if genome exists in the config file
if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
    exit 1, "The provided genome '${params.genome}' is not available in the iGenomes file. Currently the available genomes are ${params.genomes.keySet().join(", ")}"
// Link to smRNA if available
} else if ( params.genomes && params.genome && params.smrna.containsKey(params.genome) && !params.smrna_fasta) {
    //params.smrna_genome = params.genome
    params.smrna_fasta = params.genome ? params.smrna[ params.genome ].smrna_fasta ?: false : false
// Show warning of no pre-mapping if smRNA fasta is unavailable and not specified. 
} else if ( params.genomes && params.genome && !params.smrna.containsKey(params.genome) && !params.smrna_fasta) {
    log.warn "There is no available smRNA fasta file associated with the provided genome '${params.genome}'; pre-mapping will be skipped. A smRNA fasta file can be specified on the command line with --smrna_fasta"
//     
}

// TODO nf-core: Add any reference files that are needed
// Configurable reference genome variables
params.fasta = params.genome ? params.genomes[ params.genome ].fasta ?: false : false
params.gtf = params.genome ? params.genomes[ params.genome ].gtf ?: false : false
params.star_index = params.genome ? params.genomes[ params.genome ].star ?: false : false




//
// NOTE - THIS IS NOT USED IN THIS PIPELINE, EXAMPLE ONLY
// If you want to use the channel below in a process, define the following:
//   input:
//   file fasta from ch_fasta
//
// params.fasta = params.genome ? params.genomes[ params.genome ].fasta ?: false : false
// if (params.fasta) { ch_fasta = file(params.fasta, checkIfExists: true) }

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
    custom_runName = workflow.runName
}

/*
================================================================================
AWS
================================================================================
*/

if (workflow.profile.contains('awsbatch')) {
    // AWSBatch sanity checking
    if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
    // Check outdir paths to be S3 buckets if running on AWSBatch
    // related: https://github.com/nextflow-io/nextflow/issues/813
    if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
    // Prevent trace files to be stored on S3 since S3 does not support rolling files.
    if (params.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_multiqc_config = file("$baseDir/assets/multiqc_config.yaml", checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
ch_output_docs = file("$baseDir/docs/output.md", checkIfExists: true)

/*
================================================================================
SET-UP INPUTS
================================================================================
*/

params.adapter = "AGATCGGAAGAGC"
params.umi_separator = ":"

//params.smrna_fasta = "/Users/chakraa2/Github/nf-core-clipseq/assets/test_data/indices/small_rna.fa.gz"

// params.fasta = "/Users/chakraa2/projects/nfclip/chr20.fa.gz"
// params.star_index = "/Users/chakraa2/projects/nfclip/star_chr20"

//params.fai = "/Users/chakraa2/Github/nf-core-clipseq/assets/test_data/indices/chr20.fa.fai"

ch_smrna_fasta = Channel.value(params.smrna_fasta)
if (params.star_index) ch_star_index = Channel.value(params.star_index)
ch_fai_crosslinks = Channel.value(params.fai)
ch_fai_icount = Channel.value(params.fai)

if (params.peakcaller && params.peakcaller != 'icount' && params.peakcaller != "paraclu") {
    exit 1, "Invalid peak caller option: ${params.peakcaller}. Valid options: 'icount', 'paraclu'"
}

if (params.input) {
    Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header:true)
        .map{ row -> [ row.sample_id, file(row.data1, checkIfExists: true) ] } // Can change this later to [0], [1]
        .into{ ch_fastq; ch_fastq_fastqc_pretrim }
} else { 
    exit 1, "Samples comma-separated input file not specified" 
}


/*
================================================================================
HEADER LOG
================================================================================
*/

// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
// TODO nf-core: Report custom parameters here
summary['Input']            = params.input
if (params.fasta) summary['Fasta ref']        = params.fasta
if (params.gtf) summary['GTF ref']            = params.gtf
if (params.star_index) summary['STAR index'] = params.star_index
if (params.peakcaller) summary['Peak caller']            = params.peakcaller
if (params.segment) summary['iCount segment']            = params.segment
if (params.peakcaller == "icount") summary['Half window']            = params.half_window
if (params.peakcaller == "icount") summary['Merge window']            = params.merge_window
if (params.peakcaller == "paraclu") summary['Min value']            = params.min_value
if (params.peakcaller == "paraclu") summary['Max density increase']            = params.min_density_increase
if (params.peakcaller == "paraclu") summary['Max cluster length']            = params.max_cluster_length
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if (workflow.profile.contains('awsbatch')) {
    summary['AWS Region']   = params.awsregion
    summary['AWS Queue']    = params.awsqueue
    summary['AWS CLI']      = params.awscli
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Description'] = params.config_profile_description
if (params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if (params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if (params.email || params.email_on_fail) {
    summary['E-mail Address']    = params.email
    summary['E-mail on failure'] = params.email_on_fail
    summary['MultiQC maxsize']   = params.max_multiqc_email_size
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "-\033[2m--------------------------------------------------\033[0m-"

// // Check the hostnames against configured profiles
// checkHostname()

// Channel.from(summary.collect{ [it.key, it.value] })
//     .map { k,v -> "<dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }
//     .reduce { a, b -> return [a, b].join("\n            ") }
//     .map { x -> """
//     id: 'nf-core-clipseq-summary'
//     description: " - this information is collected when the pipeline is started."
//     section_name: 'nf-core/clipseq Workflow Summary'
//     section_href: 'https://github.com/nf-core/clipseq'
//     plot_type: 'html'
//     data: |
//         <dl class=\"dl-horizontal\">
//             $x
//         </dl>
//     """.stripIndent() }
//     .set { ch_workflow_summary }

// /*
//  * Parse software version numbers
//  */
// process get_software_versions {
//     publishDir "${params.outdir}/pipeline_info", mode: 'copy',
//         saveAs: { filename ->
//                       if (filename.indexOf(".csv") > 0) filename
//                       else null
//                 }

//     output:
//     file 'software_versions_mqc.yaml' into ch_software_versions_yaml
//     file "software_versions.csv"

//     script:
//     // TODO nf-core: Get all tools to print their version number here
//     """
//     echo $workflow.manifest.version > v_pipeline.txt
//     echo $workflow.nextflow.version > v_nextflow.txt
//     fastqc --version > v_fastqc.txt
//     multiqc --version > v_multiqc.txt
//     scrape_software_versions.py &> software_versions_mqc.yaml
//     """
// }

/*
================================================================================
PREPROCESSING
================================================================================
*/

/*
 * Generating premapping index
 */

if (params.smrna_fasta) {
    process generate_premap_index {

        tag "$smrna_fasta"    

        input:
        path(smrna_fasta) from ch_smrna_fasta

        output:
        path("${smrna_fasta.simpleName}.*.bt2") into ch_bt2_index

        script:

        """
        bowtie2-build --threads $task.cpus $smrna_fasta ${smrna_fasta.simpleName}
        """
    }
}


/*
 * Generating STAR index
 */

// Need logic to recognise if fasta and/or gtf are compressed and decompress if so for STAR index generation

if (!params.star_index || !params.fai) { // will probably need to modify the logic once iGenomes incorporated

    if (params.fasta) {
        if (hasExtension(params.fasta, 'gz')) {
            ch_fasta_gz = Channel
                .fromPath(params.fasta, checkIfExists: true)
                .ifEmpty { exit 1, "Genome reference fasta not found: ${params.fasta}" }
        } else {
            ch_fasta = Channel
                .fromPath(params.fasta, checkIfExists: true)
                .ifEmpty { exit 1, "Genome reference fasta not found: ${params.fasta}" }
        }
    }
}

if (params.fasta) {
    if (hasExtension(params.fasta, 'gz')) {

        process decompress_fasta {

            tag "$fasta_gz"

            input:
            path(fasta_gz) from ch_fasta_gz

            output:
            path("*.fa") into (ch_fasta, ch_fasta_fai)

            script:

            """
            pigz -d -c $fasta_gz > ${fasta_gz.baseName}
            """
        }
    }
}

if (!params.star_index) {

    if (params.gtf) {
        if (hasExtension(params.gtf, 'gz')) {
            ch_gtf_gz_star = Channel
                .fromPath(params.gtf, checkIfExists: true)
                .ifEmpty { exit 1, "Genome reference gtf not found: ${params.gtf}" }
        } else {
            ch_gtf_star = Channel
                .fromPath(params.gtf, checkIfExists: true)
                .ifEmpty { exit 1, "Genome reference gtf not found: ${params.gtf}" }
        }
    }

    if (params.gtf) {
        if (hasExtension(params.gtf, 'gz')) {

            process decompress_gtf {

                tag "$gtf_gz"

                input:
                path(gtf_gz) from ch_gtf_gz_star

                output:
                path("*.gtf") into ch_gtf_star

                script:

                """
                pigz -d -c $gtf_gz > ${gtf_gz.baseName}
                """

            }
        }
    }

    process generate_star_index {

        tag "$fasta"    

        input:
        path(fasta) from ch_fasta
        path(gtf) from ch_gtf_star

        output:
        path("STAR_${fasta.baseName}") into ch_star_index

        script:

        """
        mkdir STAR_${fasta.baseName}
        STAR --runMode genomeGenerate --runThreadN ${task.cpus} \
        --genomeDir STAR_${fasta.baseName} \
        --genomeFastaFiles $fasta \
        --genomeSAindexNbases 11 \
        --sjdbGTFfile $gtf
        """
    }

}

/*
 * Generating fai index
 */

//ch_fasta_fai.view()

if (!params.fai) {
    process generate_fai {
            tag "$fasta"

            input:
            path(fasta) from ch_fasta_fai

            output:
            //path("${fasta.baseName}.fa.fai") into (ch_fai_crosslinks, ch_fai_icount)
            path("*.fai") into (ch_fai_crosslinks, ch_fai_icount)

            script:
            
            command = "samtools faidx $fasta"

            """
            ${command}
            """
    }
}


/*
 * Generating iCount segment file
 */

// iCount GTF input autodetects gz

if (params.peakcaller && params.peakcaller == 'icount') {

    if(!params.segment) {

        ch_gtf_icount = Channel
            .fromPath(params.gtf, checkIfExists: true)
            .ifEmpty { exit 1, "Genome reference gtf not found: ${params.gtf}" }

        process icount_segment {

            tag "$gtf"

            publishDir "${params.outdir}/icount", mode: 'copy'

            input:
            path(gtf) from ch_gtf_icount
            path(fai) from ch_fai_icount

            output:
            path("icount_${gtf}") into ch_segment

            script:

            """
            iCount segment $gtf icount_${gtf} $fai
            """

        }

    } else {

        ch_segment = Channel.value(params.segment)

    }

}

/*
================================================================================
CLIP PIPELINE
================================================================================
*/

/*
 * STEP 1 - Pre-trimming FastQC
 */

process fastqc {

    tag "$name"
    // label 'process_medium'
    publishDir "${params.outdir}/fastqc", mode: 'copy',
        saveAs: { filename ->
                      filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"
                }

    input:
    tuple val(name), path(reads) from ch_fastq_fastqc_pretrim

    output:
    path "*fastqc.{zip,html}" into ch_fastqc_pretrim_mqc

    script:

    """
    fastqc --quiet --threads $task.cpus $reads
    mv ${reads.simpleName}*.html ${name}_prefastqc.html
    mv ${reads.simpleName}*.zip ${name}_prefastqc.zip
    """

}

/*
 * STEP 2 - Read trimming
 */

process cutadapt {

    tag "$name"
    // label 'process_high'
    publishDir "${params.outdir}/cutadapt", mode: 'copy'

    input:
    tuple val(name), path(reads) from ch_fastq

    output:
    tuple val(name), path("*.fastq.gz") into ch_trimmed
    path "*.log" into ch_cutadapt_mqc

    script:

    """
    cutadapt -j $task.cpus -a ${params.adapter} -m 12 -o ${name}.fastq.gz $reads > ${name}_cutadapt.log
    """

}

/*
 * STEP 3 - Post-trimming FastQC
 */

/*
 * STEP 4 - Premapping
 */

if (params.smrna_fasta) {
    process premap {

        tag "$name"
        // label 'process_high'
        publishDir "${params.outdir}/premap", mode: 'copy'

        input:
        tuple val(name), path(reads) from ch_trimmed
        path(index) from ch_bt2_index.collect()

        output:
        tuple val(name), path("*.fastq.gz") into ch_unmapped
        tuple val(name), path("*.bam"), path("*.bai")
        path "*.log" into ch_premap_mqc

        script:

        """
        bowtie2 -p $task.cpus -x ${index[0].simpleName} --un-gz ${name}.unmapped.fastq.gz -U $reads 2> ${name}.premap.log | \
        samtools sort -@ $task.cpus /dev/stdin > ${name}.premapped.bam && \
        samtools index -@ $task.cpus ${name}.premapped.bam
        """

    }
}

/*
 * STEP 5 - Aligning
 */

process align {

    tag "$name"
    // label 'process_high'
    publishDir "${params.outdir}/premap", mode: 'copy'

    input:
    tuple val(name), path(reads) from ch_unmapped
    path(index) from ch_star_index.collect()

    output:
    tuple val(name), path("*.bam"), path("*.bai") into ch_aligned
    path "*.Log.final.out" into ch_align_mqc

    script:

    clip_args = "--outFilterMultimapNmax 1 \
                --outFilterMultimapScoreRange 1 \
                --outSAMattributes All \
                --alignSJoverhangMin 8 \
                --alignSJDBoverhangMin 1 \
                --outFilterType BySJout \
                --alignIntronMin 20 \
                --alignIntronMax 1000000 \
                --outFilterScoreMin 10  \
                --alignEndsType Extend5pOfRead1 \
                --twopassMode Basic \
                --outSAMtype BAM SortedByCoordinate"

    """
    STAR --runThreadN $task.cpus --runMode alignReads --genomeDir $index \
    --readFilesIn $reads --readFilesCommand gunzip -c \
    --outFileNamePrefix ${name}. $clip_args && \
    samtools index -@ task.cpus ${name}.Aligned.sortedByCoord.out.bam
    """

}

/*
 * STEP 6 - Deduplicate
 */

process dedup {

    tag "$name"
    // label 'process_high'
    publishDir "${params.outdir}/dedup", mode: 'copy'

    input:
    tuple val(name), path(bam), path(bai) from ch_aligned

    output:
    tuple val(name), path(bam), path(bai) into ch_dedup
    path "*.log" into ch_dedup_mqc

    script:

    """
    umi_tools dedup --umi-separator="$params.umi_separator" -I $bam -S ${name}.dedup.bam --output-stats=${name} --log=${name}.log
    """

}

/*
 * STEP 6 - Identify crosslinks
 */

process get_crosslinks {

    tag "$name"
    // label 'process_medium'
    publishDir "${params.outdir}/xlinks", mode: 'copy'

    input:
    tuple val(name), path(bam), path(bai) from ch_dedup
    path(fai) from ch_fai_crosslinks

    output:
    tuple val(name), path("${name}.xl.bed.gz") into ch_xlinks_icount, ch_xlinks_paraclu

    script:

    """
    bedtools bamtobed -i $bam > dedup.bed
    bedtools shift -m 1 -p -1 -i dedup.bed -g $fai > shifted.bed
    bedtools genomecov -dz -strand + -5 -i shifted.bed -g $fai | awk '{OFS="\t"}{print \$1, \$2, \$2+1, ".", \$3, "+"}' > pos.bed
    bedtools genomecov -dz -strand - -5 -i shifted.bed -g $fai | awk '{OFS="\t"}{print \$1, \$2, \$2+1, ".", \$3, "-"}' > neg.bed
    cat pos.bed neg.bed | sort -k1,1 -k2,2n | pigz > ${name}.xl.bed.gz
    """

}

/*
 * STEP 7a - Peak-call (iCount)
 */

if (params.peakcaller && params.peakcaller == 'icount') {

    process icount_peak_call {

        tag "$name"
        publishDir "${params.outdir}/icount", mode: 'copy'

        input:
        tuple val(name), path(xlinks) from ch_xlinks_icount
        path(segment) from ch_segment.collect()

        output:
        tuple val(name), path("${name}.${half_window}nt.sigxl.bed.gz") into ch_sigxlinks
        tuple val(name), path("${name}.${half_window}nt_${merge_window}nt.peaks.bed.gz") into ch_peaks_icount

        script:

        half_window = params.half_window
        merge_window = params.merge_window

        """
        iCount peaks $segment $xlinks ${name}.${half_window}nt.sigxl.bed.gz --half_window ${half_window} --fdr 0.05

        pigz -d -c ${name}.${half_window}nt.sigxl.bed.gz | \
        bedtools sort | \
        bedtools merge -s -d ${merge_window} -c 4,5,6 -o distinct,sum,distinct | \
        pigz > ${name}.${half_window}nt_${merge_window}nt.peaks.bed.gz
        """

    }

    // process icount_merge_sigxls {

    //     tag "$name"
    //     publishDir "${params.outdir}/icount", mode: 'copy'

    //     input:
    //     tuple val(name), path(sigxlinks) from ch_sigxlinks

    //     output:
    //     tuple val(name), path("${name}.${half_window}nt.${merge_window}nt.peaks.bed.gz") into ch_peaks_icount

    //     script:

    //     half_window = 3


    //     """
    //     pigz -d -c $sigxlinks | \
    //     bedtools sort | \
    //     bedtools merge -s -d ${merge_window} -c 4,5,6 -o distinct,sum,distinct | \
    //     pigz > ${name}.${half_window}nt.${merge_window}nt.peaks.bed.gz
    //     """

    // }

}

/*
 * STEP 7b - Peak-call (paraclu)
 */

if (params.peakcaller && params.peakcaller == 'paraclu') {

    process paraclu_peak_call {

        tag "$name"
        publishDir "${params.outdir}/paraclu", mode: 'copy'

        input:
        tuple val(name), path(xlinks) from ch_xlinks_paraclu

        output:
        tuple val(name), path("${name}.${min_value}_${max_cluster_length}nt_${min_density_increase}.peaks.bed.gz") into ch_peaks_paraclu

        script:

        min_value = params.min_value
        min_density_increase = params.density_increase
        max_cluster_length = params.max_cluster_length

        """
        pigz -d -c $xlinks | \
        awk '{OFS = "\t"}{print \$1, \$6, \$2, \$5}' | \
        sort -k1,1 -k2,2 -k3,3n > paraclu_input.tsv

        paraclu ${min_value} paraclu_input.tsv | \
        paraclu-cut.sh -d ${min_density_increase} -l ${max_cluster_length} | \
        awk '{OFS = "\t"}{print \$1, \$3-1, \$4, ".", \$6, \$2}' |
        bedtools sort |
        pigz > ${name}.${min_value}_${max_cluster_length}nt_${min_density_increase}.peaks.bed.gz
        """

    }

    // process icount_merge_sigxls {

    //     tag "$name"
    //     publishDir "${params.outdir}/icount", mode: 'copy'

    //     input:
    //     tuple val(name), path(sigxlinks) from ch_sigxlinks

    //     output:
    //     tuple val(name), path("${name}.${half_window}nt.${merge_window}nt.peaks.bed.gz") into ch_peaks

    //     script:

    //     half_window = 3


    //     """
    //     pigz -d -c $sigxlinks | \
    //     bedtools sort | \
    //     bedtools merge -s -d ${merge_window} -c 4,5,6 -o distinct,sum,distinct | \
    //     pigz > ${name}.${half_window}nt.${merge_window}nt.peaks.bed.gz
    //     """

    // }

}

// /*
//  * STEP 2 - MultiQC
//  */
// process multiqc {
//     publishDir "${params.outdir}/MultiQC", mode: 'copy'

//     input:
//     file (multiqc_config) from ch_multiqc_config
//     file (mqc_custom_config) from ch_multiqc_custom_config.collect().ifEmpty([])
//     // TODO nf-core: Add in log files from your new processes for MultiQC to find!
//     file ('fastqc/*') from ch_fastqc_results.collect().ifEmpty([])
//     file ('software_versions/*') from ch_software_versions_yaml.collect()
//     file workflow_summary from ch_workflow_summary.collectFile(name: "workflow_summary_mqc.yaml")

//     output:
//     file "*multiqc_report.html" into ch_multiqc_report
//     file "*_data"
//     file "multiqc_plots"

//     script:
//     rtitle = custom_runName ? "--title \"$custom_runName\"" : ''
//     rfilename = custom_runName ? "--filename " + custom_runName.replaceAll('\\W','_').replaceAll('_+','_') + "_multiqc_report" : ''
//     custom_config_file = params.multiqc_config ? "--config $mqc_custom_config" : ''
//     // TODO nf-core: Specify which MultiQC modules to use with -m for a faster run time
//     """
//     multiqc -f $rtitle $rfilename $custom_config_file .
//     """
// }

// /*
//  * STEP 3 - Output Description HTML
//  */
// process output_documentation {
//     publishDir "${params.outdir}/pipeline_info", mode: 'copy'

//     input:
//     file output_docs from ch_output_docs

//     output:
//     file "results_description.html"

//     script:
//     """
//     markdown_to_html.py $output_docs -o results_description.html
//     """
// }

/*
================================================================================
NF-CORE ON COMPLETE
================================================================================
*/

/*
 * Completion e-mail notification
 */
// workflow.onComplete {

//     // Set up the e-mail variables
//     def subject = "[nf-core/clipseq] Successful: $workflow.runName"
//     if (!workflow.success) {
//         subject = "[nf-core/clipseq] FAILED: $workflow.runName"
//     }
//     def email_fields = [:]
//     email_fields['version'] = workflow.manifest.version
//     email_fields['runName'] = custom_runName ?: workflow.runName
//     email_fields['success'] = workflow.success
//     email_fields['dateComplete'] = workflow.complete
//     email_fields['duration'] = workflow.duration
//     email_fields['exitStatus'] = workflow.exitStatus
//     email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
//     email_fields['errorReport'] = (workflow.errorReport ?: 'None')
//     email_fields['commandLine'] = workflow.commandLine
//     email_fields['projectDir'] = workflow.projectDir
//     email_fields['summary'] = summary
//     email_fields['summary']['Date Started'] = workflow.start
//     email_fields['summary']['Date Completed'] = workflow.complete
//     email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
//     email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
//     if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
//     if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
//     if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
//     email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
//     email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
//     email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

//     // TODO nf-core: If not using MultiQC, strip out this code (including params.max_multiqc_email_size)
//     // On success try attach the multiqc report
//     def mqc_report = null
//     try {
//         if (workflow.success) {
//             mqc_report = ch_multiqc_report.getVal()
//             if (mqc_report.getClass() == ArrayList) {
//                 log.warn "[nf-core/clipseq] Found multiple reports from process 'multiqc', will use only one"
//                 mqc_report = mqc_report[0]
//             }
//         }
//     } catch (all) {
//         log.warn "[nf-core/clipseq] Could not attach MultiQC report to summary email"
//     }

//     // Check if we are only sending emails on failure
//     email_address = params.email
//     if (!params.email && params.email_on_fail && !workflow.success) {
//         email_address = params.email_on_fail
//     }

//     // Render the TXT template
//     def engine = new groovy.text.GStringTemplateEngine()
//     def tf = new File("$baseDir/assets/email_template.txt")
//     def txt_template = engine.createTemplate(tf).make(email_fields)
//     def email_txt = txt_template.toString()

//     // Render the HTML template
//     def hf = new File("$baseDir/assets/email_template.html")
//     def html_template = engine.createTemplate(hf).make(email_fields)
//     def email_html = html_template.toString()

//     // Render the sendmail template
//     def smail_fields = [ email: email_address, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: mqc_report, mqcMaxSize: params.max_multiqc_email_size.toBytes() ]
//     def sf = new File("$baseDir/assets/sendmail_template.txt")
//     def sendmail_template = engine.createTemplate(sf).make(smail_fields)
//     def sendmail_html = sendmail_template.toString()

//     // Send the HTML e-mail
//     if (email_address) {
//         try {
//             if (params.plaintext_email) { throw GroovyException('Send plaintext e-mail, not HTML') }
//             // Try to send HTML e-mail using sendmail
//             [ 'sendmail', '-t' ].execute() << sendmail_html
//             log.info "[nf-core/clipseq] Sent summary e-mail to $email_address (sendmail)"
//         } catch (all) {
//             // Catch failures and try with plaintext
//             [ 'mail', '-s', subject, email_address ].execute() << email_txt
//             log.info "[nf-core/clipseq] Sent summary e-mail to $email_address (mail)"
//         }
//     }

//     // Write summary e-mail HTML to a file
//     def output_d = new File("${params.outdir}/pipeline_info/")
//     if (!output_d.exists()) {
//         output_d.mkdirs()
//     }
//     def output_hf = new File(output_d, "pipeline_report.html")
//     output_hf.withWriter { w -> w << email_html }
//     def output_tf = new File(output_d, "pipeline_report.txt")
//     output_tf.withWriter { w -> w << email_txt }

//     c_green = params.monochrome_logs ? '' : "\033[0;32m";
//     c_purple = params.monochrome_logs ? '' : "\033[0;35m";
//     c_red = params.monochrome_logs ? '' : "\033[0;31m";
//     c_reset = params.monochrome_logs ? '' : "\033[0m";

//     if (workflow.stats.ignoredCount > 0 && workflow.success) {
//         log.info "-${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}-"
//         log.info "-${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}-"
//         log.info "-${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}-"
//     }

//     if (workflow.success) {
//         log.info "-${c_purple}[nf-core/clipseq]${c_green} Pipeline completed successfully${c_reset}-"
//     } else {
//         checkHostname()
//         log.info "-${c_purple}[nf-core/clipseq]${c_red} Pipeline completed with errors${c_reset}-"
//     }

// }

// Check file extension - from nf-core/rnaseq
def hasExtension(it, extension) {
    it.toString().toLowerCase().endsWith(extension.toLowerCase())
}


def nfcoreHeader() {
    // Log colors ANSI codes
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";

    return """    -${c_dim}--------------------------------------------------${c_reset}-
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  nf-core/clipseq v${workflow.manifest.version}${c_reset}
    -${c_dim}--------------------------------------------------${c_reset}-
    """.stripIndent()
}

def checkHostname() {
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}

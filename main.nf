#!/usr/bin/env nextflow



println """\

=================================
 K I N C - N F   P I P E L I N E
=================================


Workflow Information:
---------------------

  Project Directory:  ${workflow.projectDir}
  Launch Directory:   ${workflow.launchDir}
  Work Directory:     ${workflow.workDir}
  Config Files:       ${workflow.configFiles}
  Container Engine:   ${workflow.containerEngine}
  Profiles:           ${workflow.profile}


Execution Parameters:
---------------------

import-emx
  enabled:      ${params.import_emx.enabled}

similarity
  enabled:      ${params.similarity.enabled}
  chunkrun:     ${params.similarity.chunkrun}
  chunks:       ${params.similarity.chunks}
  gpu:          ${params.similarity.gpu}
  threads:      ${params.similarity.threads}
  clus_method:  ${params.similarity.clus_method}
  corr_method:  ${params.similarity.corr_method}

export-cmx
  enabled:      ${params.export_cmx.enabled}

threshold_constant:
  enabled:      ${params.threshold_constant.enabled}
  threshold:    ${params.threshold_constant.threshold}

threshold_rmt:
  enabled:      ${params.threshold_rmt.enabled}
  reduction:    ${params.threshold_rmt.reduction}
  threads:      ${params.threshold_rmt.threads}
  spline:       ${params.threshold_rmt.spline}

extract:
  enabled:      ${params.extract.enabled}
"""



/**
 * Make sure that no more than one threshold method has been selected.
 */
n_threshold_methods = 0

if ( params.threshold_constant.enabled == true ) {
  n_threshold_methods++
}
if ( params.threshold_rmt.enabled == true ) {
  n_threshold_methods++
}

if ( n_threshold_methods > 1 ) {
  error "error: no more than one threshold method may be selected"
}



/**
 * Create channels for input emx files.
 */
EMX_TXT_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.emx_txt_files}", size: 1, flat: true)
EMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.emx_files}", size: 1, flat: true)



/**
 * Create channels for input cmx files.
 */
CCM_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.ccm_files}", size: 1, flat: true)
CMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.cmx_files}", size: 1, flat: true)



/**
 * The import_emx process converts a plain-text expression matrix into
 * an emx file.
 */
process import_emx {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(emx_txt_file) from EMX_TXT_FILES_FROM_INPUT

    output:
        set val(dataset), file("${dataset}.emx") into EMX_FILES_FROM_IMPORT

    when:
        params.import_emx.enabled == true

    script:
        """
        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        kinc run import-emx \
            --input ${emx_txt_file} \
            --output ${dataset}.emx
        """
}



/**
 * Gather emx files and send them to each process that uses them.
 */
Channel.empty()
    .mix (
        EMX_FILES_FROM_INPUT,
        EMX_FILES_FROM_IMPORT
    )
    .into {
        EMX_FILES_FOR_SIMILARITY_CHUNK;
        EMX_FILES_FOR_SIMILARITY_MERGE;
        EMX_FILES_FOR_SIMILARITY_MPI;
        EMX_FILES_FOR_EXPORT_CMX;
        EMX_FILES_FOR_EXTRACT
    }



/**
 * Make sure that similarity_chunk is using more than one chunk if enabled.
 */
if ( params.similarity.chunkrun == true && params.similarity.chunks == 1 ) {
    error "error: chunkrun cannot be run with only one chunk"
}



/**
 * Change similarity threads to 1 if GPU acceleration is disabled.
 */
if ( params.similarity.gpu_model == "cpu" ) {
    params.similarity.threads = 1
}



/**
 * The similarity_chunk process performs a single chunk of KINC similarity.
 */
process similarity_chunk {
    tag "${dataset}/${index}"
    label "gpu"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY_CHUNK
        each(index) from Channel.from( 0 .. params.similarity.chunks-1 )

    output:
        set val(dataset), file("*.abd") into SIMILARITY_CHUNKS

    when:
        params.similarity.enabled == true && params.similarity.chunkrun == true

    script:
        """
        kinc settings set cuda ${params.similarity.gpu_model == "cpu" ? "none" : "0"}
        kinc settings set opencl none
        kinc settings set threads ${params.similarity.threads}
        kinc settings set logging off

        kinc chunkrun ${index} ${params.similarity.chunks} similarity \
            --input ${emx_file} \
            --clusmethod ${params.similarity.clus_method} \
            --corrmethod ${params.similarity.corr_method} \
            --minexpr ${params.similarity.min_expr} \
            --minclus ${params.similarity.min_clus} \
            --maxclus ${params.similarity.max_clus} \
            --crit ${params.similarity.criterion} \
            --preout ${params.similarity.preout} \
            --postout ${params.similarity.postout} \
            --mincorr ${params.similarity.min_corr} \
            --maxcorr ${params.similarity.max_corr} \
            --bsize ${params.similarity.bsize} \
            --gsize ${params.similarity.gsize} \
            --lsize ${params.similarity.lsize}
        """
}



/**
 * Merge output chunks from similarity into a list.
 */
SIMILARITY_CHUNKS_GROUPED = SIMILARITY_CHUNKS.groupTuple()



/**
 * The similarity_merge process takes the output chunks from similarity
 * and merges them into the final ccm and cmx files.
 */
process similarity_merge {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY_MERGE
        set val(dataset), file(chunks) from SIMILARITY_CHUNKS_GROUPED

    output:
        set val(dataset), file("${dataset}.ccm") into CCM_FILES_FROM_SIMILARITY_MERGE
        set val(dataset), file("${dataset}.cmx") into CMX_FILES_FROM_SIMILARITY_MERGE

    script:
        """
        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        kinc merge ${params.similarity.chunks} similarity \
            --input ${emx_file} \
            --ccm ${dataset}.ccm \
            --cmx ${dataset}.cmx \
            --clusmethod ${params.similarity.clus_method} \
            --corrmethod ${params.similarity.corr_method} \
            --minexpr ${params.similarity.min_expr} \
            --minclus ${params.similarity.min_clus} \
            --maxclus ${params.similarity.max_clus} \
            --crit ${params.similarity.criterion} \
            --preout ${params.similarity.preout} \
            --postout ${params.similarity.postout} \
            --mincorr ${params.similarity.min_corr} \
            --maxcorr ${params.similarity.max_corr} \
            --bsize ${params.similarity.bsize} \
            --gsize ${params.similarity.gsize} \
            --lsize ${params.similarity.lsize}
        """
}



/**
 * The similarity_mpi process computes an entire similarity matrix using MPI.
 */
process similarity_mpi {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"
    label "gpu"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY_MPI

    output:
        set val(dataset), file("${dataset}.ccm") into CCM_FILES_FROM_SIMILARITY_MPI
        set val(dataset), file("${dataset}.cmx") into CMX_FILES_FROM_SIMILARITY_MPI

    when:
        params.similarity.enabled == true && params.similarity.chunkrun == false

    script:
        """
        kinc settings set cuda ${params.similarity.gpu_model == "cpu" ? "none" : "0"}
        kinc settings set opencl none
        kinc settings set threads ${params.similarity.threads}
        kinc settings set logging off

        mpirun -np ${params.similarity.chunks} \
        kinc run similarity \
            --input ${emx_file} \
            --ccm ${dataset}.ccm \
            --cmx ${dataset}.cmx \
            --clusmethod ${params.similarity.clus_method} \
            --corrmethod ${params.similarity.corr_method} \
            --minexpr ${params.similarity.min_expr} \
            --minclus ${params.similarity.min_clus} \
            --maxclus ${params.similarity.max_clus} \
            --crit ${params.similarity.criterion} \
            --preout ${params.similarity.preout} \
            --postout ${params.similarity.postout} \
            --mincorr ${params.similarity.min_corr} \
            --maxcorr ${params.similarity.max_corr} \
            --bsize ${params.similarity.bsize} \
            --gsize ${params.similarity.gsize} \
            --lsize ${params.similarity.lsize}
        """
}



/**
 * Gather ccm files and send them to all processes that use them.
 */
Channel.empty()
    .mix (
        CCM_FILES_FROM_INPUT,
        CCM_FILES_FROM_SIMILARITY_MERGE,
        CCM_FILES_FROM_SIMILARITY_MPI
    )
    .into {
        CCM_FILES_FOR_EXPORT;
        CCM_FILES_FOR_EXTRACT
    }



/**
 * Gather cmx files and send them to all processes that use them.
 */
Channel.empty()
    .mix (
        CMX_FILES_FROM_INPUT,
        CMX_FILES_FROM_SIMILARITY_MERGE,
        CMX_FILES_FROM_SIMILARITY_MPI
    )
    .into {
        CMX_FILES_FOR_EXPORT;
        CMX_FILES_FOR_THRESHOLD_CONSTANT;
        CMX_FILES_FOR_THRESHOLD_RMT;
        CMX_FILES_FOR_EXTRACT
    }



/**
 * The export_cmx process exports the ccm and cmx files from similarity
 * into a plain-text format.
 */
process export_cmx {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_EXPORT_CMX
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_EXPORT
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_EXPORT

    output:
        set val(dataset), file("${dataset}.cmx.txt")

    when:
        params.export_cmx.enabled == true

    script:
        """
        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        kinc run export-cmx \
           --emx ${emx_file} \
           --ccm ${ccm_file} \
           --cmx ${cmx_file} \
           --output ${dataset}.cmx.txt
        """
}



/**
 * The threshold_constant process simply writes the provided threshold to a file
 * for the extract process.
 */
process threshold_constant {
    tag "${dataset}"

    input:
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_THRESHOLD_CONSTANT

    output:
        set val(dataset), file("threshold.txt") into THRESHOLD_FILES_FROM_CONSTANT

    when:
        params.threshold_constant.enabled == true

    script:
        """
        echo ${params.threshold_constant.threshold} > threshold.txt
        """
}



/**
 * The threshold_rmt process takes the correlation matrix from similarity
 * and attempts to find a suitable correlation threshold via the RMT method.
 */
process threshold_rmt {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_THRESHOLD_RMT

    output:
        set val(dataset), file("${dataset}.rmt.txt") into THRESHOLD_FILES_FROM_RMT

    when:
        params.threshold_rmt.enabled == true

    script:
        """
        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        kinc run rmt \
            --input ${cmx_file} \
            --log ${dataset}.rmt.txt \
            --reduction ${params.threshold_rmt.reduction} \
            --threads ${params.threshold_rmt.threads} \
            --spline ${params.threshold_rmt.spline}
        """
}



/**
 * Select which threshold method to pipe into extract.
 */
if ( params.threshold_constant.enabled == true ) {
  THRESHOLD_FILES = THRESHOLD_FILES_FROM_CONSTANT
}
else if ( params.threshold_rmt.enabled == true ) {
  THRESHOLD_FILES = THRESHOLD_FILES_FROM_RMT
}



/**
 * The extract process takes the correlation matrix from similarity and
 * extracts a network with a given threshold.
 */
process extract {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_EXTRACT
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_EXTRACT
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_EXTRACT
        set val(dataset), file(threshold_file) from THRESHOLD_FILES

    output:
        set val(dataset), file("${dataset}.coexpnet.txt") into NET_FILES_FROM_EXTRACT

    when:
        params.extract.enabled == true

    script:
        """
        THRESHOLD=\$(tail -n 1 ${threshold_file})

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        kinc run extract \
           --emx ${emx_file} \
           --ccm ${ccm_file} \
           --cmx ${cmx_file} \
           --output ${dataset}.coexpnet.txt \
           --mincorr \${THRESHOLD}
        """
}

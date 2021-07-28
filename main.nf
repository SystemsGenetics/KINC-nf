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
  enabled:        ${params.import_emx.enabled}

similarity
  enabled:        ${params.similarity.enabled}
  chunkrun:       ${params.similarity.chunkrun}
  chunks:         ${params.similarity.chunks}
  hardware_type:  ${params.similarity.hardware_type}
  threads:        ${params.similarity.threads}
  clus_method:    ${params.similarity.clus_method}
  corr_method:    ${params.similarity.corr_method}

export-cmx
  enabled:        ${params.export_cmx.enabled}

corrpower
  enabled:        ${params.corrpower.enabled}
  chunks:         ${params.corrpower.chunks}
  alpha:          ${params.corrpower.alpha}
  power:          ${params.corrpower.power}

cond-test
  enabled:        ${params.cond_test.enabled}
  chunks:         ${params.cond_test.chunks}
  feat_tests:     ${params.cond_test.feat_tests}
  feat_types:     ${params.cond_test.feat_types}
  alpha:          ${params.cond_test.alpha}
  power:          ${params.cond_test.power}

extract:
  enabled:        ${params.extract.enabled}
  filter-pvalue:  ${params.extract.filter_pvalue}
  filter-rsquare: ${params.extract.filter_rsquare}
"""



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
 * Create channels for input amx files.
 */
AMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.amx_files}", size: 1, flat: true)



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
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE n_rows=`tail -n +1 ${emx_txt_file} | wc -l`"
        echo "#TRACE n_cols=`head -n +1 ${emx_txt_file} | wc -w`"

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
        EMX_FILES_FOR_COND_TEST;
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
if ( params.similarity.hardware_type == "cpu" ) {
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
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE hardware_type=${params.similarity.hardware_type}"
        echo "#TRACE chunks=${params.similarity.chunks}"
        echo "#TRACE threads=${params.similarity.threads}"

        kinc settings set cuda ${params.similarity.hardware_type == "cpu" ? "none" : "0"}
        kinc settings set opencl none
        kinc settings set threads ${params.similarity.threads}
        kinc settings set logging off

        kinc chunkrun ${index} ${params.similarity.chunks} similarity \
            --input ${emx_file} \
            --clusmethod ${params.similarity.clus_method} \
            --corrmethod ${params.similarity.corr_method} \
            --minexpr ${params.similarity.min_expr} \
            --minsamp ${params.similarity.min_samp} \
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
 * Match each emx file with its corresponding ccm/cmx chunks.
 */
INPUTS_FOR_SIMILARITY_MERGE = EMX_FILES_FOR_SIMILARITY_MERGE.join(SIMILARITY_CHUNKS_GROUPED)



/**
 * The similarity_merge process takes the output chunks from similarity
 * and merges them into the final ccm and cmx files.
 */
process similarity_merge {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(emx_file), file(chunks) from INPUTS_FOR_SIMILARITY_MERGE

    output:
        set val(dataset), file("${dataset}.ccm") into CCM_FILES_FROM_SIMILARITY_MERGE
        set val(dataset), file("${dataset}.cmx") into CMX_FILES_FROM_SIMILARITY_MERGE

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE chunks=${params.similarity.chunks}"
        echo "#TRACE abd_bytes=`stat -Lc '%s' *.abd | awk '{sum += \$1} END {print sum}'`"

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
            --minsamp ${params.similarity.min_samp} \
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
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE hardware_type=${params.similarity.hardware_type}"
        echo "#TRACE np=${params.similarity.chunks}"
        echo "#TRACE threads=${params.similarity.threads}"

        kinc settings set cuda ${params.similarity.hardware_type == "cpu" ? "none" : "0"}
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
            --minsamp ${params.similarity.min_samp} \
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
        CCM_FILES_FOR_CORRPOWER
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
        CMX_FILES_FOR_CORRPOWER
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
 * The corrpower process applies power filtering to a correlation matrix.
 */
process corrpower {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_CORRPOWER
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_CORRPOWER

    output:
        set val(dataset), file("${dataset}.paf.ccm") into CCM_FILES_FROM_CORRPOWER
        set val(dataset), file("${dataset}.paf.cmx") into CMX_FILES_FROM_CORRPOWER

    when:
        params.corrpower.enabled == true

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE np=${params.corrpower.chunks}"
        echo "#TRACE ccm_bytes=`stat -Lc '%s' ${ccm_file}`"
        echo "#TRACE cmx_bytes=`stat -Lc '%s' ${cmx_file}`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        mpirun -np ${params.corrpower.chunks} \
            kinc run corrpower \
            --ccm-in ${dataset}.ccm \
            --cmx-in ${dataset}.cmx \
            --ccm-out ${dataset}.paf.ccm \
            --cmx-out ${dataset}.paf.cmx \
            --alpha ${params.corrpower.alpha} \
            --power ${params.corrpower.power}
        """
}



/**
 * Gather filtered cmx files and send them to all processes that use them.
 */
Channel.empty()
    .mix (
        CMX_FILES_FROM_CORRPOWER
    )
    .into {
        CMX_FILES_FOR_COND_TEST;
        CMX_FILES_FOR_EXTRACT
    }



/**
 * Gather filtered ccm files and send them to all processes that use them.
 */
Channel.empty()
    .mix (
        CCM_FILES_FROM_CORRPOWER
    )
    .into {
        CCM_FILES_FOR_COND_TEST;
        CCM_FILES_FOR_EXTRACT
    }



/**
 * The cond_test process performs condition-specific analysis on a
 * correlation matrix.
 */
process cond_test {
    tag "${dataset}"
    publishDir "${params.output.dir}/${dataset}"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_COND_TEST
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_COND_TEST
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_COND_TEST
        set val(dataset), file(amx_file) from AMX_FILES_FROM_INPUT

    output:
        set val(dataset), file("${dataset}.paf.csm") into CSM_FILES_FROM_COND_TEST

    when:
        params.cond_test.enabled == true

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE np=${params.cond_test.chunks}"
        echo "#TRACE ccm_bytes=`stat -Lc '%s' ${ccm_file}`"
        echo "#TRACE cmx_bytes=`stat -Lc '%s' ${cmx_file}`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        mpirun -np ${params.cond_test.chunks} \
            kinc run cond-test \
            --emx ${dataset}.emx \
            --ccm ${dataset}.paf.ccm \
            --cmx ${dataset}.paf.cmx \
            --amx ${amx_file} \
            --output ${dataset}.paf.csm \
            --feat-tests ${params.cond_test.feat_tests} \
            --feat-types ${params.cond_test.feat_types} \
            --alpha ${params.cond_test.alpha} \
            --power ${params.cond_test.power}
        """
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
        set val(dataset), file(csm_file) from CSM_FILES_FROM_COND_TEST

    output:
        set val(dataset), file("${dataset}.paf-*.txt") into NET_FILES_FROM_EXTRACT

    when:
        params.extract.enabled == true

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE emx_bytes=`stat -Lc '%s' ${dataset}.emx`"
        echo "#TRACE ccm_bytes=`stat -Lc '%s' ${dataset}.ccm`"
        echo "#TRACE cmx_bytes=`stat -Lc '%s' ${dataset}.cmx`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        kinc run extract \
           --emx ${emx_file} \
           --ccm ${ccm_file} \
           --cmx ${cmx_file} \
           --csm ${csm_file} \
           --format ${params.extract.format} \
           --output ${dataset}.paf-th${params.extract.min_corr}-p${params.extract.filter_pvalue}-rsqr${params.extract.filter_rsquare}.txt \
           --mincorr ${params.extract.min_corr} \
           --maxcorr ${params.extract.max_corr} \
           --filter-pvalue ${params.extract.filter_pvalue} \
           --filter-rsquare ${params.extract.filter_rsquare}
        """
}

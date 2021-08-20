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
  enabled:        ${params.import_emx_enabled}

similarity
  enabled:        ${params.similarity_enabled}
  chunkrun:       ${params.similarity_chunkrun}
  chunks:         ${params.similarity_chunks}
  hardware_type:  ${params.similarity_hardware_type}
  threads:        ${params.similarity_threads}
  clusmethod:     ${params.similarity_clusmethod}
  corrmethod:     ${params.similarity_corrmethod}

export-cmx
  enabled:        ${params.export_cmx_enabled}

corrpower
  enabled:        ${params.corrpower_enabled}
  chunks:         ${params.corrpower_chunks}
  alpha:          ${params.corrpower_alpha}
  power:          ${params.corrpower_power}

cond-test
  enabled:        ${params.condtest_enabled}
  chunks:         ${params.condtest_chunks}
  feat_tests:     ${params.condtest_feat_tests}
  feat_types:     ${params.condtest_feat_types}
  alpha:          ${params.condtest_alpha}
  power:          ${params.condtest_power}

extract:
  enabled:        ${params.extract_enabled}
  filter-pvalue:  ${params.extract_filter_pvalue}
  filter-rsquare: ${params.extract_filter_rsquare}
"""



/**
 * Create channels for input emx files.
 */
EMX_TXT_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input_dir}/${params.emx_txt_files}", size: 1, flat: true)
EMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input_dir}/${params.emx_files}", size: 1, flat: true)



/**
 * Create channels for input cmx files.
 */
CCM_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input_dir}/${params.ccm_files}", size: 1, flat: true)
CMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input_dir}/${params.cmx_files}", size: 1, flat: true)



/**
 * Create channels for input amx files.
 */
AMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input_dir}/${params.amx_files}", size: 1, flat: true)



/**
 * The import_emx process converts a plain-text expression matrix into
 * an emx file.
 */
process import_emx {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"

    input:
        set val(dataset), file(emx_txt_file) from EMX_TXT_FILES_FROM_INPUT

    output:
        set val(dataset), file("${dataset}.emx") into EMX_FILES_FROM_IMPORT

    when:
        params.import_emx_enabled == true

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
if ( params.similarity_chunkrun == true && params.similarity_chunks == 1 ) {
    error "error: chunkrun cannot be run with only one chunk"
}



/**
 * Change similarity threads to 1 if GPU acceleration is disabled.
 */
if ( params.similarity_hardware_type == "cpu" ) {
    params.similarity_threads = 1
}



/**
 * The similarity_chunk process performs a single chunk of KINC similarity.
 */
process similarity_chunk {
    tag "${dataset}/${index}"
    label "gpu"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY_CHUNK
        each(index) from Channel.from( 0 .. params.similarity_chunks-1 )

    output:
        set val(dataset), file("*.abd") into SIMILARITY_CHUNKS

    when:
        params.similarity_enabled == true && params.similarity_chunkrun == true

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE hardware_type=${params.similarity_hardware_type}"
        echo "#TRACE chunks=${params.similarity_chunks}"
        echo "#TRACE threads=${params.similarity_threads}"

        kinc settings set cuda ${params.similarity_hardware_type == "cpu" ? "none" : "0"}
        kinc settings set opencl none
        kinc settings set threads ${params.similarity_threads}
        kinc settings set logging off

        kinc chunkrun ${index} ${params.similarity_chunks} similarity \
            --input ${emx_file} \
            --clusmethod ${params.similarity_clusmethod} \
            --corrmethod ${params.similarity_corrmethod} \
            --minexpr ${params.similarity_minexpr} \
            --minsamp ${params.similarity_minsamp} \
            --minclus ${params.similarity_minclus} \
            --maxclus ${params.similarity_maxclus} \
            --crit ${params.similarity_criterion} \
            --preout ${params.similarity_preout} \
            --postout ${params.similarity_postout} \
            --mincorr ${params.similarity_mincorr} \
            --maxcorr ${params.similarity_maxcorr} \
            --bsize ${params.similarity_bsize} \
            --gsize ${params.similarity_gsize} \
            --lsize ${params.similarity_lsize}
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
    publishDir "${params.output_dir}/${dataset}"

    input:
        set val(dataset), file(emx_file), file(chunks) from INPUTS_FOR_SIMILARITY_MERGE

    output:
        set val(dataset), file("${dataset}.ccm") into CCM_FILES_FROM_SIMILARITY_MERGE
        set val(dataset), file("${dataset}.cmx") into CMX_FILES_FROM_SIMILARITY_MERGE

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE chunks=${params.similarity_chunks}"
        echo "#TRACE abd_bytes=`stat -Lc '%s' *.abd | awk '{sum += \$1} END {print sum}'`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        kinc merge ${params.similarity_chunks} similarity \
            --input ${emx_file} \
            --ccm ${dataset}.ccm \
            --cmx ${dataset}.cmx \
            --clusmethod ${params.similarity_clusmethod} \
            --corrmethod ${params.similarity_corrmethod} \
            --minexpr ${params.similarity_minexpr} \
            --minsamp ${params.similarity_minsamp} \
            --minclus ${params.similarity_minclus} \
            --maxclus ${params.similarity_maxclus} \
            --crit ${params.similarity_criterion} \
            --preout ${params.similarity_preout} \
            --postout ${params.similarity_postout} \
            --mincorr ${params.similarity_mincorr} \
            --maxcorr ${params.similarity_maxcorr} \
            --bsize ${params.similarity_bsize} \
            --gsize ${params.similarity_gsize} \
            --lsize ${params.similarity_lsize}
        """
}



/**
 * The similarity_mpi process computes an entire similarity matrix using MPI.
 */
process similarity_mpi {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"
    label "gpu"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY_MPI

    output:
        set val(dataset), file("${dataset}.ccm") into CCM_FILES_FROM_SIMILARITY_MPI
        set val(dataset), file("${dataset}.cmx") into CMX_FILES_FROM_SIMILARITY_MPI

    when:
        params.similarity_enabled == true && params.similarity_chunkrun == false

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE hardware_type=${params.similarity_hardware_type}"
        echo "#TRACE np=${params.similarity_chunks}"
        echo "#TRACE threads=${params.similarity_threads}"

        kinc settings set cuda ${params.similarity_hardware_type == "cpu" ? "none" : "0"}
        kinc settings set opencl none
        kinc settings set threads ${params.similarity_threads}
        kinc settings set logging off

        mpirun -np ${params.similarity_chunks} \
        kinc run similarity \
            --input ${emx_file} \
            --ccm ${dataset}.ccm \
            --cmx ${dataset}.cmx \
            --clusmethod ${params.similarity_clusmethod} \
            --corrmethod ${params.similarity_corrmethod} \
            --minexpr ${params.similarity_minexpr} \
            --minsamp ${params.similarity_minsamp} \
            --minclus ${params.similarity_minclus} \
            --maxclus ${params.similarity_maxclus} \
            --crit ${params.similarity_criterion} \
            --preout ${params.similarity_preout} \
            --postout ${params.similarity_postout} \
            --mincorr ${params.similarity_mincorr} \
            --maxcorr ${params.similarity_maxcorr} \
            --bsize ${params.similarity_bsize} \
            --gsize ${params.similarity_gsize} \
            --lsize ${params.similarity_lsize}
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
    publishDir "${params.output_dir}/${dataset}"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_EXPORT_CMX
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_EXPORT
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_EXPORT

    output:
        set val(dataset), file("${dataset}.cmx.txt")

    when:
        params.export_cmx_enabled == true

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
    publishDir "${params.output_dir}/${dataset}"

    input:
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_CORRPOWER
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_CORRPOWER

    output:
        set val(dataset), file("${dataset}.paf.ccm") into CCM_FILES_FROM_CORRPOWER
        set val(dataset), file("${dataset}.paf.cmx") into CMX_FILES_FROM_CORRPOWER

    when:
        params.corrpower_enabled == true

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE np=${params.corrpower_chunks}"
        echo "#TRACE ccm_bytes=`stat -Lc '%s' ${ccm_file}`"
        echo "#TRACE cmx_bytes=`stat -Lc '%s' ${cmx_file}`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        mpirun -np ${params.corrpower_chunks} \
            kinc run corrpower \
            --ccm-in ${dataset}.ccm \
            --cmx-in ${dataset}.cmx \
            --ccm-out ${dataset}.paf.ccm \
            --cmx-out ${dataset}.paf.cmx \
            --alpha ${params.corrpower_alpha} \
            --power ${params.corrpower_power}
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
 * The condtest process performs condition-specific analysis on a
 * correlation matrix.
 */
process condtest {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_COND_TEST
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_COND_TEST
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_COND_TEST
        set val(dataset), file(amx_file) from AMX_FILES_FROM_INPUT

    output:
        set val(dataset), file("${dataset}.paf.csm") into CSM_FILES_FROM_COND_TEST

    when:
        params.condtest_enabled == true

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE np=${params.condtest_chunks}"
        echo "#TRACE ccm_bytes=`stat -Lc '%s' ${ccm_file}`"
        echo "#TRACE cmx_bytes=`stat -Lc '%s' ${cmx_file}`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        mpirun -np ${params.condtest_chunks} \
            kinc run cond-test \
            --emx ${dataset}.emx \
            --ccm ${dataset}.paf.ccm \
            --cmx ${dataset}.paf.cmx \
            --amx ${amx_file} \
            --output ${dataset}.paf.csm \
            --feat-tests ${params.condtest_feat_tests} \
            --feat-types ${params.condtest_feat_types} \
            --alpha ${params.condtest_alpha} \
            --power ${params.condtest_power}
        """
}



/**
 * The extract process takes the correlation matrix from similarity and
 * extracts a network with a given threshold.
 */
process extract {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"

    input:
        set val(dataset), file(emx_file) from EMX_FILES_FOR_EXTRACT
        set val(dataset), file(ccm_file) from CCM_FILES_FOR_EXTRACT
        set val(dataset), file(cmx_file) from CMX_FILES_FOR_EXTRACT
        set val(dataset), file(csm_file) from CSM_FILES_FROM_COND_TEST

    output:
        set val(dataset), file("${dataset}.paf-*.txt") into NET_FILES_FROM_EXTRACT

    when:
        params.extract_enabled == true

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
           --format ${params.extract_format} \
           --output ${dataset}.paf-th${params.extract_mincorr}-p${params.extract_filter_pvalue}-rsqr${params.extract_filter_rsquare}.txt \
           --mincorr ${params.extract_mincorr} \
           --maxcorr ${params.extract_maxcorr} \
           --filter-pvalue ${params.extract_filter_pvalue} \
           --filter-rsquare ${params.extract_filter_rsquare}
        """
}

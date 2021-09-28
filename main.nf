#!/usr/bin/env nextflow

nextflow.enable.dsl=2



println \
"""
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
  enabled:        ${params.import_emx}

similarity
  enabled:        ${params.similarity}
  chunkrun:       ${params.similarity_chunkrun}
  chunks:         ${params.similarity_chunks}
  hardware_type:  ${params.similarity_hardware_type}
  threads:        ${params.similarity_threads}
  clusmethod:     ${params.similarity_clusmethod}
  corrmethod:     ${params.similarity_corrmethod}

export-cmx
  enabled:        ${params.export_cmx}

corrpower
  enabled:        ${params.corrpower}
  chunks:         ${params.corrpower_chunks}
  alpha:          ${params.corrpower_alpha}
  power:          ${params.corrpower_power}

cond-test
  enabled:        ${params.condtest}
  chunks:         ${params.condtest_chunks}
  feat_tests:     ${params.condtest_feat_tests}
  feat_types:     ${params.condtest_feat_types}
  alpha:          ${params.condtest_alpha}
  power:          ${params.condtest_power}

extract
  enabled:        ${params.extract}
  filter-pvalue:  ${params.extract_filter_pvalue}
  filter-rsquare: ${params.extract_filter_rsquare}
"""



workflow {
    // load input files
    emx_txt_files = Channel.fromFilePairs("${params.input_dir}/${params.emx_txt_files}", size: 1, flat: true)
    emx_files = Channel.fromFilePairs("${params.input_dir}/${params.emx_files}", size: 1, flat: true)
    ccm_files = Channel.fromFilePairs("${params.input_dir}/${params.ccm_files}", size: 1, flat: true)
    cmx_files = Channel.fromFilePairs("${params.input_dir}/${params.cmx_files}", size: 1, flat: true)
    amx_files = Channel.fromFilePairs("${params.input_dir}/${params.amx_files}", size: 1, flat: true)

    // import emx files if specified
    if ( params.import_emx == true ) {
        import_emx(emx_txt_files)

        emx_files = emx_files.mix(import_emx.out.emx_files)
    }

    // make sure that similarity_chunk is using more than one chunk if enabled
    if ( params.similarity_chunkrun == true && params.similarity_chunks == 1 ) {
        error "error: chunkrun cannot be run with only one chunk"
    }

    // change similarity threads to 1 if GPU acceleration is not enabled
    if ( params.similarity_hardware_type == "cpu" ) {
        params.similarity_threads = 1
    }

    // perform similarity_chunk if specified
    if ( params.similarity == true && params.similarity_chunkrun == true ) {
        // process similarity chunks
        indices = Channel.from( 0 .. params.similarity_chunks-1 )
        similarity_chunk(emx_files, indices)

        // merge similarity chunks into a list
        chunks = similarity_chunk.out.chunks.groupTuple(size: params.similarity_chunks)

        // match each emx file with corresponding ccm/cmx chunks
        merge_inputs = emx_files.join(chunks)

        // merge chunks into ccm/cmx files
        similarity_merge(merge_inputs)

        ccm_files = ccm_files.mix(similarity_merge.out.ccm_files)
        cmx_files = cmx_files.mix(similarity_merge.out.cmx_files)
    }

    // perform similarity_mpi if specified
    if ( params.similarity == true && params.similarity_chunkrun == false ) {
        similarity_mpi(emx_files)

        ccm_files = ccm_files.mix(similarity_mpi.out.ccm_files)
        cmx_files = cmx_files.mix(similarity_mpi.out.cmx_files)
    }

    // export cmx files if specified
    if ( params.export_cmx == true ) {
        export_cmx(emx_files, ccm_files, cmx_files)
    }

    // perform correlation power analysis if specified
    if ( params.corrpower == true ) {
        corrpower(ccm_files, cmx_files)

        paf_ccm_files = corrpower.out.ccm_files
        paf_cmx_files = corrpower.out.cmx_files
    }
    else {
        paf_ccm_files = Channel.empty()
        paf_cmx_files = Channel.empty()
    }

    // perform condition testing if specified
    if ( params.condtest == true ) {
        condtest(emx_files, paf_ccm_files, paf_cmx_files, amx_files)

        csm_files = condtest.out.csm_files
    }

    // extract network files if specified
    if ( params.extract == true ) {
        extract(emx_files, paf_ccm_files, paf_cmx_files, csm_files)
    }
}



/**
 * The import_emx process converts a plain-text expression matrix into
 * an emx file.
 */
process import_emx {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"

    input:
        tuple val(dataset), path(emx_txt_file)

    output:
        tuple val(dataset), path("${dataset}.emx"), emit: emx_files

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
 * The similarity_chunk process performs a single chunk of KINC similarity.
 */
process similarity_chunk {
    tag "${dataset}/${index}"
    label "gpu"

    input:
        tuple val(dataset), path(emx_file)
        each index

    output:
        tuple val(dataset), path("*.abd"), emit: chunks

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
 * The similarity_merge process takes the output chunks from similarity
 * and merges them into the final ccm and cmx files.
 */
process similarity_merge {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"

    input:
        tuple val(dataset), path(emx_file), path(chunks)

    output:
        tuple val(dataset), path("${dataset}.ccm"), emit: ccm_files
        tuple val(dataset), path("${dataset}.cmx"), emit: cmx_files

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
        tuple val(dataset), path(emx_file)

    output:
        tuple val(dataset), path("${dataset}.ccm"), emit: ccm_files
        tuple val(dataset), path("${dataset}.cmx"), emit: cmx_files

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

        mpirun --allow-run-as-root -np ${params.similarity_chunks} \
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
 * The export_cmx process exports the ccm and cmx files from similarity
 * into a plain-text format.
 */
process export_cmx {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"

    input:
        tuple val(dataset), path(emx_file)
        tuple val(dataset), path(ccm_file)
        tuple val(dataset), path(cmx_file)

    output:
        tuple val(dataset), path("${dataset}.cmx.txt"), emit: cmx_txt_files

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
        tuple val(dataset), path(ccm_file)
        tuple val(dataset), path(cmx_file)

    output:
        tuple val(dataset), path("${dataset}.paf.ccm"), emit: ccm_files
        tuple val(dataset), path("${dataset}.paf.cmx"), emit: cmx_files

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE np=${params.corrpower_chunks}"
        echo "#TRACE ccm_bytes=`stat -Lc '%s' ${ccm_file}`"
        echo "#TRACE cmx_bytes=`stat -Lc '%s' ${cmx_file}`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        mpirun --allow-run-as-root -np ${params.corrpower_chunks} \
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
 * The condtest process performs condition-specific analysis on a
 * correlation matrix.
 */
process condtest {
    tag "${dataset}"
    publishDir "${params.output_dir}/${dataset}"

    input:
        tuple val(dataset), path(emx_file)
        tuple val(dataset), path(ccm_file)
        tuple val(dataset), path(cmx_file)
        tuple val(dataset), path(amx_file)

    output:
        tuple val(dataset), path("${dataset}.paf.csm"), emit: csm_files

    script:
        """
        echo "#TRACE dataset=${dataset}"
        echo "#TRACE np=${params.condtest_chunks}"
        echo "#TRACE ccm_bytes=`stat -Lc '%s' ${ccm_file}`"
        echo "#TRACE cmx_bytes=`stat -Lc '%s' ${cmx_file}`"

        kinc settings set cuda none
        kinc settings set opencl none
        kinc settings set logging off

        mpirun --allow-run-as-root -np ${params.condtest_chunks} \
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
        tuple val(dataset), path(emx_file)
        tuple val(dataset), path(ccm_file)
        tuple val(dataset), path(cmx_file)
        tuple val(dataset), path(csm_file)

    output:
        tuple val(dataset), path("${dataset}.paf-*.txt"), emit: net_files

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

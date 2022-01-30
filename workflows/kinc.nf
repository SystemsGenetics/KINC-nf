/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowKinc.initialise(params, log)

// Check input path parameters to see if they exist
def checkPathParamList = [ params.data, params.smeta ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters

/*
========================================================================================
    CONFIG FILES
========================================================================================
*/

/*
========================================================================================
    IMPORT LOCAL MODULES/SUBWORKFLOWS
========================================================================================
*/
include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/modules/custom/dumpsoftwareversions/main'

include { KINC_IMPORTEMX } from '../modules/local/modules/kinc/importemx/main.nf'
include { KINC_SIMILARITY_CHUNK } from '../modules/local/modules/kinc/similarity_chunk/main.nf'
include { KINC_SIMILARITY_MERGE } from '../modules/local/modules/kinc/similarity_merge/main.nf'
include { KINC_CORRPOWER } from '../modules/local/modules/kinc/corrpower/main.nf'
include { KINC_CONDTEST } from '../modules/local/modules/kinc/condtest/main.nf'
include { KINC_EXTRACT } from '../modules/local/modules/kinc/extract/main.nf'
include { KINC_REMOVEBIAS } from '../modules/local/modules/kinc/removebias/main.nf'
/*
========================================================================================
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
========================================================================================
*/

//
// MODULE: Installed directly from nf-core/modules
//

/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/

workflow KINC {

    ch_versions = Channel.empty()

    data_file = Channel.fromPath( params.data ).map { [[id: it.getFileName()], it] }
    smeta_file = Channel.fromPath( params.smeta )

    // Step 1: Import data matrix
    KINC_IMPORTEMX(data_file)
    emx_file = KINC_IMPORTEMX.out.emx

    // Step 2: Perform the chunked similarity (correlation) step
    indices = Channel.from( 0 .. params.chunks - 1 )
    KINC_SIMILARITY_CHUNK(emx_file, params.chunks, params.hardware, indices)
    chunk_files = KINC_SIMILARITY_CHUNK.out.results.groupTuple(size: params.chunks)
    KINC_SIMILARITY_MERGE(emx_file.join(chunk_files), params.chunks)
    ccm_file = KINC_SIMILARITY_MERGE.out.ccm
    cmx_file = KINC_SIMILARITY_MERGE.out.cmx

    // Step 3: Perform a power analysis to remove low powered correlations.
    KINC_CORRPOWER(ccm_file, cmx_file, params.chunks)
    pccm_file = KINC_CORRPOWER.out.ccm
    pcmx_file = KINC_CORRPOWER.out.cmx

    // Step 4: Perform conditional testing
    KINC_CONDTEST(emx_file, pccm_file, pcmx_file, smeta_file, params.chunks)
    pcsm_file = KINC_CONDTEST.out.csm

    // Step 5: Extract the network
    KINC_EXTRACT(emx_file, pccm_file, pcmx_file, pcsm_file)
    net_file = KINC_EXTRACT.out.net

    // Step 6: Remove biased edges from the network file
    KINC_REMOVEBIAS(data_file, net_file, smeta_file)

    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

}

/*
========================================================================================
    COMPLETION EMAIL AND SUMMARY
========================================================================================
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
}

/*
========================================================================================
    THE END
========================================================================================
*/

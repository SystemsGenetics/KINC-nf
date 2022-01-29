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

    KINC_IMPORTEMX(data_file)

    indices = Channel.from( 0 .. params.chunks - 1 )
    KINC_SIMILARITY_CHUNK(KINC_IMPORTEMX.out.emx, params.chunks, params.hardware, indices)

    chunk_files = KINC_SIMILARITY_CHUNK.out.results.groupTuple(size: params.chunks)

    KINC_SIMILARITY_MERGE(data_file.join(chunk_files), params.chunks)


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

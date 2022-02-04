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

// Set the graph ID if one doesn't exist.
def graph_id = params.graph_id
if (!graph_id) {
    graph_id = params.graph_name
    graph_id = graph_id.replaceAll(/[^\w\.\-]/, '_')
}
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
include { KINC_FILTERBIAS } from '../modules/local/modules/kinc/filterbias/main.nf'
include { KINC_MAKEPLOTS } from '../modules/local/modules/kinc/makeplots/main.nf'
include { KINC_FILTERRANK as KINC_FILTERRANK_CONDITION } from '../modules/local/modules/kinc/filterrank/main.nf'
include { KINC_FILTERRANK as KINC_FILTERRANK_UNIQUE_CLASS } from '../modules/local/modules/kinc/filterrank/main.nf'
include { KINC_FILTERRANK as KINC_FILTERRANK_UNIQUE_LABEL } from '../modules/local/modules/kinc/filterrank/main.nf'
include { KINC_NET2GRAPHML } from '../modules/local/modules/kinc/net2graphml/main.nf'
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

    data_file = Channel.fromPath( params.data ).map { [[id: graph_id], it] }
    smeta_file = Channel.fromPath( params.smeta )

    // Step 1: Import data matrix
    KINC_IMPORTEMX(data_file)
    emx_file = KINC_IMPORTEMX.out.emx

    // Step 2: Perform the chunked similarity (correlation) step
    indices = Channel.from( 0 .. params.similarity_chunks - 1 )
    KINC_SIMILARITY_CHUNK(emx_file, params.similarity_chunks, params.max_gpus, indices)
    chunk_files = KINC_SIMILARITY_CHUNK.out.results.groupTuple(size: params.similarity_chunks)
    KINC_SIMILARITY_MERGE(emx_file.join(chunk_files), params.similarity_chunks)
    ccm_file = KINC_SIMILARITY_MERGE.out.ccm
    cmx_file = KINC_SIMILARITY_MERGE.out.cmx

    // Step 3: Perform a power analysis to remove low powered correlations.
    KINC_CORRPOWER(ccm_file, cmx_file)
    pccm_file = KINC_CORRPOWER.out.ccm
    pcmx_file = KINC_CORRPOWER.out.cmx

    // Step 4: Perform conditional testing
    KINC_CONDTEST(emx_file, pccm_file, pcmx_file, smeta_file)
    pcsm_file = KINC_CONDTEST.out.csm

    // Step 5: Extract the network
    KINC_EXTRACT(emx_file, pccm_file, pcmx_file, pcsm_file)

    // Step 6: Remove biased edges from the network file
    KINC_FILTERBIAS(data_file, KINC_EXTRACT.out.net, smeta_file)

    // Step 7: Generate the summary plots
    KINC_MAKEPLOTS(KINC_FILTERBIAS.out.net)

    // Step 8: Rank the edges and filter by rank.
    KINC_FILTERRANK_CONDITION(KINC_FILTERBIAS.out.net)
    KINC_FILTERRANK_UNIQUE_CLASS(KINC_FILTERBIAS.out.net)
    KINC_FILTERRANK_UNIQUE_LABEL(KINC_FILTERBIAS.out.net)

    // Step 9: Output all network files as a graphml file
    csnets = KINC_FILTERRANK_CONDITION.out.net
    uclass_csnets = KINC_FILTERRANK_UNIQUE_CLASS.out.net
    ulabel_csnets = KINC_FILTERRANK_UNIQUE_LABEL.out.net

    csnets
        .concat(uclass_csnets, ulabel_csnets)
        .transpose()
        .set { CSNs }
    KINC_NET2GRAPHML(CSNs)

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

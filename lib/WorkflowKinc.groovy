//
// This file holds several functions specific to the workflow/kinc.nf in the systemsgenetics/kinc-nf pipeline
//

class WorkflowKinc {

    //
    // Check and validate parameters
    //
    public static void initialise(params, log) {

        if (!params.data) {
            log.error "Please provide a tab-delimeted abudance matrix to the pipeline e.g. '--data GEM.tsv'"
            System.exit(1)
        }
        if (!params.smeta) {
            log.error "Please provide a tab-delimeted sample metadata matrix to the pipeline e.g. '--smeta sample_metadata.tsv'"
            System.exit(1)
        }
        if (!params.outprefix) {
            log.error "Please provide the prefix for all output files e.g. '--outprefix kinc_test'"
            System.exit(1)
        }
        if (params.chunks < 2 ) {
            log.error "The number of chunks must be greater than 1."
            System.exit(1)
        }
    }

    //
    // Get workflow summary for MultiQC
    //
    public static String paramsSummaryMultiqc(workflow, summary) {
        String summary_section = ''
        for (group in summary.keySet()) {
            def group_params = summary.get(group)  // This gets the parameters of that particular group
            if (group_params) {
                summary_section += "    <p style=\"font-size:110%\"><b>$group</b></p>\n"
                summary_section += "    <dl class=\"dl-horizontal\">\n"
                for (param in group_params.keySet()) {
                    summary_section += "        <dt>$param</dt><dd><samp>${group_params.get(param) ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>\n"
                }
                summary_section += "    </dl>\n"
            }
        }

        String yaml_file_text  = "id: '${workflow.manifest.name.replace('/','-')}-summary'\n"
        yaml_file_text        += "description: ' - this information is collected when the pipeline is started.'\n"
        yaml_file_text        += "section_name: '${workflow.manifest.name} Workflow Summary'\n"
        yaml_file_text        += "section_href: 'https://github.com/${workflow.manifest.name}'\n"
        yaml_file_text        += "plot_type: 'html'\n"
        yaml_file_text        += "data: |\n"
        yaml_file_text        += "${summary_section}"
        return yaml_file_text
    }
}

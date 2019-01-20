#!/usr/bin/env nextflow



/**
 * Create channel for input files.
 */
GEM_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input_dir}/*.txt", size: 1, flat: true)



/**
 * Send input files to each process that uses them.
 */
GEM_FILES_FROM_INPUT.into { GEM_FILES_FOR_IMPORT_EMX; GEM_FILES_FOR_VISUALIZE }



/**
 * The import_emx process converts a plain-text expression matrix into
 * a KINC data object.
 */
process import_emx {
	tag "${dataset}"
	publishDir "${params.output_dir}/${dataset}"

	input:
		set val(dataset), file(input_file) from GEM_FILES_FOR_IMPORT_EMX

	output:
		set val(dataset), file("${dataset}.emx") into EMX_FILES

	when:
		params.import_emx.enabled == true

	script:
		"""
		kinc settings set logging off || echo

		kinc run import-emx \
			--input ${input_file} \
			--output ${dataset}.emx
		"""
}



/**
 * Send emx files to each process that uses them.
 */
EMX_FILES.into { EMX_FILES_FOR_SIMILARITY; EMX_FILES_FOR_MERGE; EMX_FILES_FOR_EXPORT; EMX_FILES_FOR_EXTRACT }



/**
 * The similarity process performs a single chunk of KINC similarity.
 */
process similarity {
	tag "${dataset}/${index}"
	label "gpu"

	input:
		set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY
		each(index) from Channel.from( 0 .. params.similarity.chunks-1 )

	output:
		set val(dataset), file("*.abd") into SIMILARITY_CHUNKS

	when:
		params.similarity.enabled == true

	script:
		"""
		kinc settings set opencl 0:0                           || echo
		kinc settings set threads ${params.similarity.threads} || echo
		kinc settings set logging off                          || echo

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
			--maxcorr ${params.similarity.max_corr}
		"""
}



/**
 * Merge output chunks from similarity into a list.
 */
SIMILARITY_CHUNKS_GROUPED = SIMILARITY_CHUNKS.groupTuple()



/**
 * The merge process takes the output chunks from similarity
 * and merges them into the final output files.
 */
process merge {
	tag "${dataset}"
	publishDir "${params.output_dir}/${dataset}"

	input:
		set val(dataset), file(emx_file) from EMX_FILES_FOR_MERGE
		set val(dataset), file(chunks) from SIMILARITY_CHUNKS_GROUPED

	output:
		set val(dataset), file("${dataset}.ccm") into CCM_FILES
		set val(dataset), file("${dataset}.cmx") into CMX_FILES

	script:
		"""
		kinc settings set logging off || echo

		kinc merge ${params.similarity.chunks} similarity \
			--input ${emx_file} \
			--ccm ${dataset}.ccm \
			--cmx ${dataset}.cmx
		"""
}



/**
 * Send ccm, cmx files to all processes that use them.
 */
CCM_FILES.into { CCM_FILES_FOR_EXPORT; CCM_FILES_FOR_EXTRACT }
CMX_FILES.into { CMX_FILES_FOR_EXPORT; CMX_FILES_FOR_THRESHOLD; CMX_FILES_FOR_EXTRACT }



/**
 * The export_cmx process exports the ccm and cmx files from similarity
 * into a plain-text format.
 */
process export_cmx {
	tag "${dataset}"
	publishDir "${params.output_dir}/${dataset}"

	input:
		set val(dataset), file(emx_file) from EMX_FILES_FOR_EXPORT
		set val(dataset), file(ccm_file) from CCM_FILES_FOR_EXPORT
		set val(dataset), file(cmx_file) from CMX_FILES_FOR_EXPORT

	output:
		set val(dataset), file("${dataset}-cmx.txt")

	when:
		params.export_cmx.enabled == true

	script:
		"""
		kinc settings set logging off || echo

		kinc run export-cmx \
		   --emx ${emx_file} \
		   --ccm ${ccm_file} \
		   --cmx ${cmx_file} \
		   --output ${dataset}-cmx.txt
		"""
}



/**
 * The threshold process takes the correlation matrix from similarity
 * and attempts to find a suitable correlation threshold.
 */
process threshold {
	tag "${dataset}"
	publishDir "${params.output_dir}/${dataset}"

	input:
		set val(dataset), file(cmx_file) from CMX_FILES_FOR_THRESHOLD

	output:
		set val(dataset), file("${dataset}-threshold.log") into THRESHOLD_LOGS

	when:
		params.threshold.enabled == true

	script:
		"""
		kinc settings set logging off || echo

		kinc run rmt \
			--input ${cmx_file} \
			--log ${dataset}-threshold.log \
			--reduction ${params.threshold.reduction} \
			--spline ${params.threshold.spline}
		"""
}



/**
 * The extract process takes the correlation matrix from similarity
 * and attempts to find a suitable correlation threshold.
 */
process extract {
	tag "${dataset}"
	publishDir "${params.output_dir}/${dataset}"

	input:
		set val(dataset), file(emx_file) from EMX_FILES_FOR_EXTRACT
		set val(dataset), file(ccm_file) from CCM_FILES_FOR_EXTRACT
		set val(dataset), file(cmx_file) from CMX_FILES_FOR_EXTRACT
		set val(dataset), file(log_file) from THRESHOLD_LOGS

	output:
		set val(dataset), file("${dataset}-net.txt") into NET_FILES

	when:
		params.extract.enabled == true

	script:
		"""
		THRESHOLD=\$(tail -n 1 ${log_file})

		kinc settings set logging off || echo

		kinc run extract \
		   --emx ${emx_file} \
		   --ccm ${ccm_file} \
		   --cmx ${cmx_file} \
		   --output ${dataset}-net.txt \
		   --mincorr \$THRESHOLD
		"""
}



/**
 * The visualize process takes extracted network files and saves the
 * pairwise scatter plots as a directory of images.
 */
process visualize {
	tag "${dataset}"
	label "python"
	publishDir "${params.output_dir}/${dataset}/plots"

	input:
		set val(dataset), file(emx_file) from GEM_FILES_FOR_VISUALIZE
		set val(dataset), file(net_file) from NET_FILES

	output:
		set val(dataset), file("*.png") into PAIRWISE_SCATTER_PLOTS

	when:
		params.visualize.enabled == true

	script:
		"""
		python3 /opt/KINC/scripts/visualize.py \
			--emx ${emx_file} \
			--netlist ${net_file} \
			--output . \
			--scale
		"""
}

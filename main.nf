#!/usr/bin/env nextflow



/**
 * Create channels for input files.
 */
EMX_TXT_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.emx_txt_files}", size: 1, flat: true)
EMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.emx_files}", size: 1, flat: true)

CMX_TXT_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.cmx_txt_files}", size: 1, flat: true)
CCM_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.ccm_files}", size: 1, flat: true)
CMX_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.cmx_files}", size: 1, flat: true)

RMT_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.rmt_files}", size: 1, flat: true)

NET_FILES_FROM_INPUT = Channel.fromFilePairs("${params.input.dir}/${params.input.net_files}", size: 1, flat: true)



/**
 * Send input files to each process that uses them.
 */
EMX_TXT_FILES_FROM_INPUT
	.into {
		EMX_TXT_FILES_FOR_IMPORT_EMX;
		EMX_TXT_FILES_FOR_IMPORT_CMX;
		EMX_TXT_FILES_FOR_VISUALIZE
	}



/**
 * The import_emx process converts a plain-text expression matrix into
 * an emx file.
 */
process import_emx {
	tag "${dataset}"
	publishDir "${params.output.dir}/${dataset}"

	input:
		set val(dataset), file(input_file) from EMX_TXT_FILES_FOR_IMPORT_EMX

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
			--input ${input_file} \
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
		EMX_FILES_FOR_EXPORT_EMX;
		EMX_FILES_FOR_SIMILARITY_CHUNK;
		EMX_FILES_FOR_SIMILARITY_MERGE;
		EMX_FILES_FOR_SIMILARITY_MPI;
		EMX_FILES_FOR_EXPORT_CMX;
		EMX_FILES_FOR_EXTRACT
	}



/**
 * The export_emx process exports an emx file into the plain-text format.
 */
process export_emx {
	tag "${dataset}"
	publishDir "${params.output.dir}/${dataset}"

	input:
		set val(dataset), file(emx_file) from EMX_FILES_FOR_EXPORT_EMX

	output:
		set val(dataset), file("${dataset}.emx.txt")

	when:
		params.export_emx.enabled == true

	script:
		"""
		kinc settings set cuda none
		kinc settings set opencl none
		kinc settings set logging off

		kinc run export-emx \
		   --input ${emx_file} \
		   --output ${dataset}.emx.txt
		"""
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
if ( params.similarity.gpu == false ) {
	params.similarity.threads = 1
}



/**
 * The similarity_chunk process performs a single chunk of KINC similarity.
 */
process similarity_chunk {
	tag "${dataset}/${index}"

	input:
		set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY_CHUNK
		each(index) from Channel.from( 0 .. params.similarity.chunks-1 )

	output:
		set val(dataset), file("*.abd") into SIMILARITY_CHUNKS

	when:
		params.similarity.enabled == true && params.similarity.chunkrun == true

	script:
		"""
		kinc settings set cuda ${params.similarity.gpu ? "0" : "none"}
		kinc settings set opencl none
		kinc settings set threads ${params.similarity.threads}
		kinc settings set logging off

		taskset -c 0-${params.similarity.threads-1} kinc chunkrun ${index} ${params.similarity.chunks} similarity \
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
			--cmx ${dataset}.cmx
		"""
}



/**
 * The similarity_mpi process computes an entire similarity matrix using MPI.
 */
process similarity_mpi {
	tag "${dataset}"
	publishDir "${params.output.dir}/${dataset}"

	input:
		set val(dataset), file(emx_file) from EMX_FILES_FOR_SIMILARITY_MPI

	output:
		set val(dataset), file("${dataset}.ccm") into CCM_FILES_FROM_SIMILARITY_MPI
		set val(dataset), file("${dataset}.cmx") into CMX_FILES_FROM_SIMILARITY_MPI

	when:
		params.similarity.enabled == true && params.similarity.chunkrun == false

	script:
		"""
		kinc settings set cuda ${params.similarity.gpu ? "0" : "none"}
		kinc settings set opencl none
		kinc settings set threads ${params.similarity.threads}
		kinc settings set logging off

		mpirun -np ${params.similarity.chunks} taskset -c 0-${params.similarity.threads-1} kinc run similarity \
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
 * The import_cmx process converts a plain-text correlation/cluster matrix into
 * ccm and cmx files.
 */
process import_cmx {
	tag "${dataset}"
	publishDir "${params.output.dir}/${dataset}"

	input:
		set val(dataset), file(emx_file) from EMX_TXT_FILES_FOR_IMPORT_CMX
		set val(dataset), file(input_file) from CMX_TXT_FILES_FROM_INPUT

	output:
		set val(dataset), file("${dataset}.ccm") into CCM_FILES_FROM_IMPORT
		set val(dataset), file("${dataset}.cmx") into CMX_FILES_FROM_IMPORT

	when:
		params.import_cmx.enabled == true

	script:
		"""
		NUM_GENES=\$(head -n -1 ${emx_file} | wc -l)
		NUM_SAMPLES=\$(head -n 1 ${emx_file} | wc -w)

		kinc settings set cuda none
		kinc settings set opencl none
		kinc settings set logging off

		kinc run import-cmx \
			--input ${input_file} \
			--ccm ${dataset}.ccm \
			--cmx ${dataset}.cmx \
			--genes \$NUM_GENES \
			--maxclusters ${params.import_cmx.max_clusters} \
			--samples \$NUM_SAMPLES \
			--corrname ${params.import_cmx.corr_name}
		"""
}



/**
 * Gather ccm files and send them to all processes that use them.
 */
Channel.empty()
	.mix (
		CCM_FILES_FROM_INPUT,
		CCM_FILES_FROM_SIMILARITY_MERGE,
		CCM_FILES_FROM_SIMILARITY_MPI,
		CCM_FILES_FROM_IMPORT
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
		CMX_FILES_FROM_SIMILARITY_MPI,
		CMX_FILES_FROM_IMPORT
	)
	.into {
		CMX_FILES_FOR_EXPORT;
		CMX_FILES_FOR_THRESHOLD;
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
 * The threshold process takes the correlation matrix from similarity
 * and attempts to find a suitable correlation threshold.
 */
process threshold {
	tag "${dataset}"
	publishDir "${params.output.dir}/${dataset}"

	input:
		set val(dataset), file(cmx_file) from CMX_FILES_FOR_THRESHOLD

	output:
		set val(dataset), file("${dataset}.rmt.txt") into RMT_FILES_FROM_THRESHOLD

	when:
		params.threshold.enabled == true

	script:
		"""
		kinc settings set cuda none
		kinc settings set opencl none
		kinc settings set logging off

		kinc run rmt \
			--input ${cmx_file} \
			--log ${dataset}.rmt.txt \
			--reduction ${params.threshold.reduction} \
			--threads ${params.threshold.threads} \
			--spline ${params.threshold.spline}
		"""
}



/**
 * Gather threshold logs.
 */
RMT_FILES = RMT_FILES_FROM_INPUT.mix(RMT_FILES_FROM_THRESHOLD)



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
		set val(dataset), file(rmt_file) from RMT_FILES

	output:
		set val(dataset), file("${dataset}.coexpnet.txt") into NET_FILES_FROM_EXTRACT

	when:
		params.extract.enabled == true

	script:
		"""
		THRESHOLD=\$(tail -n 1 ${rmt_file})

		kinc settings set cuda none
		kinc settings set opencl none
		kinc settings set logging off

		kinc run extract \
		   --emx ${emx_file} \
		   --ccm ${ccm_file} \
		   --cmx ${cmx_file} \
		   --output ${dataset}.coexpnet.txt \
		   --mincorr \$THRESHOLD
		"""
}



/**
 * Gather network files.
 */
NET_FILES = NET_FILES_FROM_INPUT.mix(NET_FILES_FROM_EXTRACT)



/**
 * The visualize process takes extracted network files and saves the
 * pairwise scatter plots as a directory of images.
 */
process visualize {
	tag "${dataset}"
	label "python"
	publishDir "${params.output.dir}/${dataset}/plots"

	input:
		set val(dataset), file(emx_file) from EMX_TXT_FILES_FOR_VISUALIZE
		set val(dataset), file(net_file) from NET_FILES

	output:
		set val(dataset), file("*.png")

	when:
		params.visualize.enabled == true

	script:
		"""
		python3 /opt/KINC/scripts/visualize.py \
			--emx ${emx_file} \
			--netlist ${net_file} \
			--output-dir . \
			${params.visualize.clusdist ? "--clusdist" : ""} \
			${params.visualize.corrdist ? "--corrdist" : ""} \
			${params.visualize.coverage ? "--coverage" : ""} \
			${params.visualize.pairwise ? "--pairwise" : ""} \
			${params.visualize.pw_scale ? "--pw-scale" : ""}
		"""
}

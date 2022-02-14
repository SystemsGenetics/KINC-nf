def VERSION = '3.4.2'

process KINC_SIMILARITY_MERGE {
    tag "${meta.id}"

    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(emx), path(chunk_files)
    val(num_chunks)

    output:
    tuple val(meta), path("*.ccm"), emit: ccm
    tuple val(meta), path("*.cmx"), emit: cmx
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"

    """
    kinc settings set cuda none
    kinc settings set opencl none
    kinc settings set threads 1
    kinc settings set logging off

    kinc merge ${num_chunks} similarity \
          --input ${emx} \
          --ccm ${prefix}.ccm \
          --cmx ${prefix}.cmx \
          ${args}

    echo $VERSION >KINC.version.txt
    """
}
def VERSION = '3.4.2'

process KINC_SIMILARITY_CHUNK {
    tag "${meta.id}/${index}"

    container { hardware == "gpu" ? "systemsgenetics/kinc:$VERSION-gpu" : "systemsgenetics/kinc:$VERSION-cpu" }

    input:
    tuple val(meta), path(emx)
    val(num_chunks)
    val(hardware)
    each index

    output:
    tuple val(meta), path("*.abd"), emit: results
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"

    """
    kinc settings set cuda ${hardware == "cpu" ? "none" : "0"}
    kinc settings set opencl none
    kinc settings set threads 1
    kinc settings set logging off

    kinc chunkrun ${index} ${num_chunks} similarity \
          --input ${emx} \
          --ccm ${prefix}.ccm \
          --cmx ${prefix}.cmx \
          ${args}

    echo $VERSION >KINC.version.txt
    """
}

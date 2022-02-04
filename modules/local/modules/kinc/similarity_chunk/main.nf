def VERSION = '3.4.2'

process KINC_SIMILARITY_CHUNK {
    tag "${meta.id}/${index}"
    label "KINC_GPU"

    container { max_gpus > 0 ? "systemsgenetics/kinc:$VERSION-gpu" : "systemsgenetics/kinc:$VERSION-cpu" }

    input:
    tuple val(meta), path(emx)
    val(num_chunks)
    val(max_gpus)
    each index

    output:
    tuple val(meta), path("*.abd"), emit: results
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"

    """
    kinc settings set cuda ${max_gpus == 0 ? "none" : "0"}
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

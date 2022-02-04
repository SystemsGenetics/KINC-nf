def VERSION = 'develop'

process KINC_FILTERRANK {
    tag "${meta.id}"

    // KINC has no conda package, a Galaxy singularity package, or a Quay,io docker image.
    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(net)

    output:
    tuple val(meta), path("*.csGCN.txt"), emit: net
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"
    """
    kinc-filter-rank.R  \
          --net ${net} \
          --out_prefix "${prefix}" \
          ${args}

    echo $VERSION >KINC.version.txt
    """
}

def VERSION = 'develop'

process KINC_MAKEPLOTS {
    tag "${meta.id}"

    // KINC has no conda package, a Galaxy singularity package, or a Quay,io docker image.
    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(net)

    output:
    tuple val(meta), path("figures/*.png"), emit: plots
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"
    """
    kinc-make-plots.R  \
          --net ${net} \
          --out_prefix ${prefix} \
          ${args}

    echo $VERSION >KINC.version.txt
    """
}

def VERSION = 'develop'

process KINC_FILTERBIAS {
    tag "${meta.id}"
    label "KINC_MULTI_THREADED"

    // KINC has no conda package, a Galaxy singularity package, or a Quay,io docker image.
    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(data)
    tuple val(meta), path(net)
    path(amx)

    output:
    tuple val(meta), path("*.filtered.net.tsv"), emit: net
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"
    """
    kinc-filter-bias.R  \
          --net ${net} \
          --emx ${data} \
          --amx ${amx} \
          --out_prefix "${prefix}" \
          --suffix ".filtered.net.tsv" \
          --threads ${task.cpus} \
          ${args}

    echo $VERSION >KINC.version.txt
    """
}

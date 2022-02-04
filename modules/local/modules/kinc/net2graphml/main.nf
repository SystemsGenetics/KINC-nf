def VERSION = 'develop'

process KINC_NET2GRAPHML {
    tag "${meta.id}"

    // KINC has no conda package, a Galaxy singularity package, or a Quay,io docker image.
    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(net)

    output:
    tuple val(meta), path("*.graphml"), emit: graphml
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"
    def outfile = net.name.replaceFirst(~/\.[^\.]+$/, '')
    outfile
    """
    kinc-net2graphml.py  \
          --net ${net} \
          --outfile ${outfile}.graphml \
          ${args}

    echo $VERSION >KINC.version.txt
    """
}

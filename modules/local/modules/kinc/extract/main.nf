def VERSION = '3.4.2'

process KINC_EXTRACT {
    tag "${meta.id}"

    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(emx)
    tuple val(meta), path(ccm)
    tuple val(meta), path(cmx)
    tuple val(meta), path(csm)

    output:
    tuple val(meta), path("*.net.tsv"), emit: net
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"

    """
    kinc settings set cuda none
    kinc settings set opencl none
    kinc settings set threads 1
    kinc settings set logging off

    kinc run extract \
        --emx ${emx} \
        --cmx ${cmx} \
        --ccm ${ccm} \
        --csm ${csm} \
        --output ${prefix}.net.tsv \
        ${args}

    echo $VERSION >KINC.version.txt
    """
}

def VERSION = '3.4.2'

process KINC_CORRPOWER {
    tag "${meta.id}"
    label "KINC_MPI"

    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(ccm)
    tuple val(meta), path(cmx)

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

    mpirun --allow-run-as-root -np  ${task.cpus} \
      kinc run corrpower \
        --ccm-in ${ccm} \
        --cmx-in ${cmx} \
        --ccm-out ${prefix}.cp.ccm \
        --cmx-out ${prefix}.cp.cmx \
        ${args}

    echo $VERSION >KINC.version.txt
    """
}

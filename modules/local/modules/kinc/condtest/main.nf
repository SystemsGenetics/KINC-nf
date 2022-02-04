def VERSION = '3.4.2'

process KINC_CONDTEST {
    tag "${meta.id}"
    label "KINC_MPI"

    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(emx)
    tuple val(meta), path(ccm)
    tuple val(meta), path(cmx)
    path(smeta)

    output:
    tuple val(meta), path("*.csm"), emit: csm
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"

    """
    kinc settings set cuda none
    kinc settings set opencl none
    kinc settings set threads 1
    kinc settings set logging off

    mpirun --allow-run-as-root -np ${task.cpus} \
      kinc run cond-test \
        --emx ${emx} \
        --ccm ${ccm} \
        --cmx ${cmx} \
        --amx ${smeta} \
        --output ${prefix}.csm \
        ${args}

    echo $VERSION >KINC.version.txt
    """
}

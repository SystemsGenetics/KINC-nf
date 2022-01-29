def VERSION = '3.4.2'

process KINC_IMPORTEMX {
    tag "${meta.id}"
    label 'process_low'

    // KINC has no conda package, a Galaxy singularity package, or a Quay,io docker image.
    container "systemsgenetics/kinc:$VERSION-cpu"

    input:
    tuple val(meta), path(data)

    output:
    tuple val(meta), path("*.emx"), emit: emx
    path "*.version.txt", emit: version

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "kinc_out"

    """
    kinc run import-emx \\
          --input $data \\
          --output ${prefix}.emx \\
          $args

    echo $VERSION >KINC.version.txt
    """
}

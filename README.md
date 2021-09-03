# KINC-nf

The Nextflow pipeline for [KINC](https://github.com/SystemsGenetics/KINC).

## Dependencies

All you need is [nextflow](https://nextflow.io/), [Docker](https://docker.com/), and [nvidia-docker](https://github.com/NVIDIA/nvidia-docker). On HPC systems, you can use [Singularity](https://www.sylabs.io/singularity/) in lieu of Docker. If for some reason you can't use either container software, you will have to install KINC from source.

## Installation

You don't. But you may want to refer to the [config file](https://github.com/SystemsGenetics/KINC-nf/blob/master/nextflow.config) on GitHub file and familiarize yourself with the available settings.

## Usage

You can run the pipeline out-of-the-box with Nextflow. We also provide some example data to get you started. Here's how to run KINC on the example data:
```bash
nextflow run systemsgenetics/kinc-nf -profile example,<docker|singularity>
```

This example will download the pipeline repository, the example data, and the Docker/Singularity container for KINC, and run KINC on the example data. The results will be saved to `./output`.

KINC-nf detects input files by their file extension. For example, the default extension for GEM files is `*.emx.txt`, so make sure that your input GEMs have this extension before running the pipeline. You can also place intermediate files in the input directory, and KINC-nf will use them as inputs to the appropriate processes. For example, you can provide the `*.emx` file created by `import_emx` instead of the plain-text GEM and KINC-nf will skip the `import_emx` step.

You can specify any of the params in `nextflow.config` as command-line arguments, for example:
```bash
nextflow run systemsgenetics/kinc-nf \
    --similarity_chunks 1 \
    --similarity_hardware_type gpu
```

The params allow you to control which analytics to run, how many chunks to use where applicable, and various other command-line parameters for KINC. You can resume a failed run with the `-resume` flag. Consult the Nextflow documentation for more information on these and other options.

## Palmetto

To run KINC-nf on Palmetto, you have to use Singularity instead of Docker, and use the `palmetto` profile:
```bash
nextflow run systemsgenetics/kinc-nf -profile palmetto,singularity
```

## Kubernetes

You can run this pipeline, as well as any other nextflow pipeline, on a [Kubernetes](https://kubernetes.io/) cluster with minimal effort. Consult the [kube-runner](https://github.com/SystemsGenetics/kube-runner) repo for instructions.

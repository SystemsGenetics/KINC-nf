# KINC-nf

The Nextflow pipeline for [KINC](https://github.com/SystemsGenetics/KINC).

## Dependencies

All you need is [nextflow](https://nextflow.io/), [Docker](https://docker.com/), and [nvidia-docker](https://github.com/NVIDIA/nvidia-docker). On HPC systems, you can use [Singularity](https://www.sylabs.io/singularity/) in lieu of Docker. If for some reason you can't use either container software, you will have to install KINC from source.

## Installation

You don't. But you may want to copy the `nextflow.config` file from this repo so that you can customize it:
```
wget https://raw.githubusercontent.com/SystemsGenetics/KINC-nf/master/nextflow.config
```

## Usage

Use nextflow to run this pipeline. For example, here is a basic usage:
```
nextflow run systemsgenetics/KINC-nf
```

This example will download this pipeline to your machine and use the default `nextflow.config` in this repo. It will assume that you have KINC installed natively, and it will process all GEM files in the `data` directory, saving all output files to the `output` directory, as defined in `nextflow.config`.

You can also create your own `nextflow.config` file; nextflow will check for a config file in your current directory before defaulting to config file in this repo. You will most likely need to customize this config file as it provides options such as which analytics to run, how many chunks to use where applicable, and various other command-line parameters for KINC. The config file also allows you to define your own "profiles" for running this pipeline in different environments. Consult the Nextflow documentation for more information on what environments are supported.

To use Docker or Singularity, run nextflow with the `-with-docker` or `-with-singularity` flag. You can resume a failed run with the `-resume` flag. Consult the Nextflow documentation for more information on these and other options.

## Kubernetes

You can run this pipeline, as well as any other nextflow pipeline, on a [Kubernetes](https://kubernetes.io/) cluster with minimal effort. Consult the [kube-runner](https://github.com/SystemsGenetics/kube-runner) repo for instructions.

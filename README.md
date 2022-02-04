# ![systemsgenetics/kinc-nf](assets/systemsgenetics-kinc_logo_light.png)

[![GitHub Actions CI Status](https://github.com/systemsgenetics/kinc-nf/workflows/nf-core%20CI/badge.svg)](https://github.com/systemsgenetics/kinc-nf/actions?query=workflow%3A%22nf-core+CI%22)
[![GitHub Actions Linting Status](https://github.com/systemsgenetics/kinc-nf/workflows/nf-core%20linting/badge.svg)](https://github.com/systemsgenetics/kinc-nf/actions?query=workflow%3A%22nf-core+linting%22)
[![Cite with Zenodo](https://zenodo.org/badge/71836133.svg)](https://zenodo.org/badge/latestdoi/71836133)

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A521.10.3-23aa62.svg?labelColor=000000)](https://www.nextflow.io/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)


## Introduction

This is the Nextflow pipeline for the knowledge Independent Network Construction (KINC) Toolkit.  Please see the full [KINC documentation](https://kinc.readthedocs.io/en/latest/) to learn more about KINC.

The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It uses Docker/Singularity containers making installation trivial and results highly reproducible. The [Nextflow DSL2](https://www.nextflow.io/docs/latest/dsl2.html) implementation of this pipeline uses one container per process which makes it much easier to maintain and update software dependencies.


## Pipeline summary
This workflow performs both a traditional network analysis and a condition specific network analysis.
### Traditional Network Construction
The following steps are performed:
1. Imports abundance/expression data matrix: `kinc run importemx`
2. Performs pairwise correlation analysis: `kinc run similarity`
3. Uses Random Matrix Theory (RMT) to identify a threshold for removing edges: `kinc run rmt`


### Condition-Specific Network Construction
The following steps are performed:

1. Imports abundance/expression data matrix: `kinc run importemx`
2. Performs pairwise Gaussian Mixture Models (GMMs) followed by correlation analysis: `kinc run similarity`
3. Performs power analysis of all edges to remove those that are underpowered:  `kinc run corrpower`
4. Performs condition-specific testing to identify edges associated with traits or experimental conditions: `kinc run cond-test`
5. Performs bias testing to remove biased edges: `kinc-filter-bias.R`
6. Ranks the edges, filters the top _n_:  `kinc-filter-rank.R`
7. Generates summary plots: `kinc-make-plots.R`
8. Generates network files in GraphML format suitable for Cytoscape or other viewers:  `kinc-net2graphml.py`

## Quick Start

1. Install [`Nextflow`](https://www.nextflow.io/docs/latest/getstarted.html#installation) (`>=21.10.3`)

2. Install any of [`Docker`](https://docs.docker.com/engine/installation/), [`Singularity`](https://www.sylabs.io/guides/3.0/user-guide/). Note: This workflow has not yet been tested on the following and may or may not work: [`Podman`](https://podman.io/), [`Shifter`](https://nersc.gitlab.io/development/shifter/how-to-use/) or [`Charliecloud`](https://hpc.github.io/charliecloud/) for full pipeline reproducibility.  [`Conda`](https://conda.io/miniconda.html) is not supported.

3. Download the pipeline and test it on a minimal dataset with a single command:

    ```console
    nextflow run systemsgenetics/kinc-nf -profile test,YOURPROFILE
    ```

    Note that some form of configuration will be needed so that Nextflow knows how to fetch the required software. This is usually done in the form of a config profile (`YOURPROFILE` in the example command above). You can chain multiple config profiles in a comma-separated string.

    > * The pipeline comes with config profiles called `docker`, `singularity`, `podman`, `shifter`, `charliecloud` and `conda` which instruct the pipeline to use the named tool for software management. For example, `-profile test,docker`.
    > * Please check [nf-core/configs](https://github.com/nf-core/configs#documentation) to see if a custom config file to run nf-core pipelines already exists for your Institute. If so, you can simply use `-profile <institute>` in your command. This will enable either `docker` or `singularity` and set the appropriate execution settings for your local compute environment.
    > * If you are using `singularity` and are persistently observing issues downloading Singularity images directly due to timeout or network issues, then you can use the `--singularity_pull_docker_container` parameter to pull and convert the Docker image instead. Alternatively, you can use the [`nf-core download`](https://nf-co.re/tools/#downloading-pipelines-for-offline-use) command to download images first, before running the pipeline. Setting the [`NXF_SINGULARITY_CACHEDIR` or `singularity.cacheDir`](https://www.nextflow.io/docs/latest/singularity.html?#singularity-docker-hub) Nextflow options enables you to store and re-use the images from a central location for future pipeline runs.
    > * If you are using `conda`, it is highly recommended to use the [`NXF_CONDA_CACHEDIR` or `conda.cacheDir`](https://www.nextflow.io/docs/latest/conda.html) settings to store the environments in a central location for future pipeline runs.

4. Start running your own analysis!

    <!-- TODO nf-core: Update the example "typical command" below used to run the pipeline -->

    ```console
    nextflow run systemsgenetics/kinc-nf -profile <docker/singularity/podman/shifter/charliecloud/conda/institute> --data <abundance/expression data> \
	--smeta <annotation/metadata matrix> \
	--graph_name "<name of your graph>" \
	--data_missing_val "NA" \
	--data_num_samples 0 \
	--data_has_row_ids "False" \
	--similarity_chunks 10 \
	--condtest_tests "<conditional tests>" \
	--condtest_types "<test data types>" \
	--filterbias_wa_base "<bias filter base>" \
	--max_cpus <num of CPUs per task> \
	--max_gpus <num of GPUs per task>
    ```

## Documentation

More thorough documenation about the pipeline is coming. Until then, you can learn about the KINC toolkit and pipeline here:

[KINC documentation](https://kinc.readthedocs.io/en/latest/) to learn more about KINC.

## Credits
This pipeline was developed by Ben Shealy and Stephen Ficklin.


## Contributions and Support

If you would like to contribute to this pipeline, please see the [contributing guidelines](.github/CONTRIBUTING.md).


## Citations

If you use this pipeline please cite:

> Joshua J R Burns, Benjamin T Shealy, Mitchell S Greer, John A Hadish, Matthew T McGowan, Tyler Biggs, Melissa C Smith, F Alex Feltus, Stephen P Ficklin, Addressing noise in co-expression network construction, Briefings in Bioinformatics, Volume 23, Issue 1, January 2022, bbab495, https://doi.org/10.1093/bib/bbab495


You can cite the `nf-core` publication as follows:

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).

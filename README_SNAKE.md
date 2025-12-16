Snakemake workflow to run post-processing scripts

Files added:
- `Snakefile` : Snakemake workflow that runs `postprocess_hiseq_lane_centos7_test_gzip.pl` per lane
- `snakemake_config.yaml` : Configuration file with defaults

Quick start

1. Edit `snakemake_config.yaml` to match locations (sample sheet, fastqdir, library name).

2. Dry-run:
```
snakemake -n -s Snakefile
```

3. Run with 4 cores:
```
snakemake --cores 4 -s Snakefile
```

Notes
- The workflow changes current directory into `Tools/` before invoking the postprocess script so relative paths inside that script work as expected.
- The postprocess script supports `--dryrun`; set `dryrun: true` in `snakemake_config.yaml` to enable it.
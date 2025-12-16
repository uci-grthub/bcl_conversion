configfile: "snakemake_config.yaml"

SCRIPTDIR = config.get("script_dir", "Tools")
SCRIPT = config.get("script_path", "postprocess/postprocess_hiseq_lane_centos7_test_gzip.pl")
SAMPLE_SHEET = config.get("sample_sheet", "Tools/data/code/SampleSheet.csv")
NUM_READS = config.get("num_reads", 2)
LIBRARY = config.get("library_name", "VilaE_WGS_Pool1")
FASTQDIR = config.get("fastqdir", "output")
START_S = config.get("start_s", 1)
DRYRUN = config.get("dryrun", False)
LANES = config.get("lanes", [1,2,3,4,5,6,7,8])
FASTP_THREADS = config.get("fastp_threads", 4)
FASTP_OUTDIR = config.get("fastp_outdir", "results/fastp")
FASTP_PLOTS_OUTDIR = config.get("fastp_plots_outdir", "results/fastp_plots")

rule all:
    input:
        expand("results/postprocess_lane{lane}.done", lane=LANES),
        expand("results/fastp_plots_lane{lane}.done", lane=LANES),
        expand("results/fastp_lane{lane}.done", lane=LANES)

rule postprocess_lane:
    output:
        touch("results/postprocess_lane{lane}.done")
    params:
        scriptdir = SCRIPTDIR,
        script = SCRIPT,
        sample_sheet = SAMPLE_SHEET,
        num_reads = NUM_READS,
        library = LIBRARY,
        fastqdir = FASTQDIR,
        start_s = START_S,
        dryflag = "--dryrun" if DRYRUN else ""
    threads: 1
    shell:
        """
        mkdir -p results
        cd {params.scriptdir}
        perl {params.script} {params.sample_sheet} {params.num_reads} {wildcards.lane} "{params.library}" {params.fastqdir} {params.start_s} {params.dryflag}
        cd - >/dev/null
        touch {output}
        """

rule fastp_lane:
    output:
        touch("results/fastp_lane{lane}.done")
    params:
        fastqdir = FASTQDIR,
        outdir = FASTP_OUTDIR,
        threads = FASTP_THREADS,
        lane = "{lane}"
    threads: 1
    shell:
        """
        mkdir -p {params.outdir}/lane{wildcards.lane}
        # Find R1 files for this lane and run fastp on each pair
        for r1 in $(find {params.fastqdir} -type f -name "*_L00{wildcards.lane}_R1_001.fastq.gz" 2>/dev/null); do
            r2=${{r1/_R1_/_R2_}}
            sample=$(basename "$r1" | sed -E 's/_S[0-9]+_L00[0-9]+_R1_001.fastq.gz//')
            out_prefix={params.outdir}/lane{wildcards.lane}/${{sample}}
            echo "fastp: $r1 & $r2 -> ${out_prefix}_R1.fastq.gz"
            fastp -i "$r1" -I "$r2" -o "${{out_prefix}}_R1.fastq.gz" -O "${{out_prefix}}_R2.fastq.gz" \
                  --html "${{out_prefix}}.html" --json "${{out_prefix}}.json" -w {params.threads} || true
        done
        touch {output}
        """

rule fastp_plots_lane:
    output:
        touch("results/fastp_plots_lane{lane}.done")
    params:
        fastp_outdir = FASTP_OUTDIR,
        plots_outdir = FASTP_PLOTS_OUTDIR,
        scripts_dir = SCRIPTDIR + "/analyze",
        lane = "{lane}"
    threads: 1
    shell:
        """
        mkdir -p {params.plots_outdir}/lane{wildcards.lane}
        for json in $(find {params.fastp_outdir}/lane{wildcards.lane} -type f -name "*.json" 2>/dev/null); do
            sample=$(basename "$json" .json)
            out_mean={params.plots_outdir}/lane{wildcards.lane}/${{sample}}-mean_phred.png
            out_base={params.plots_outdir}/lane{wildcards.lane}/${{sample}}-base_comp.png
            echo "Plotting $json -> $out_mean, $out_base"
            python3 {params.scripts_dir}/mean_phred_plot_fastp.py "$json" --out "$out_mean" || true
            python3 {params.scripts_dir}/base_composition_plot_fastp.py "$json" --out "$out_base" || true
        done
        touch {output}
        """

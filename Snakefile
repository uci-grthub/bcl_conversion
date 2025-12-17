import os

configfile: "snakemake_config.yaml"

SCRIPTDIR = config.get("script_dir", "Tools")
SCRIPT = config.get("script_path", "Tools/postprocess/postprocess_hiseq_lane_centos7_test_gzip.pl")
SAMPLE_SHEET = config.get("sample_sheet", "src/SampleSheet.csv")
NUM_READS = config.get("num_reads", 2)
LIBRARY = config.get("library_name", "VilaE_WGS_Pool1")
FASTQDIR = config.get("fastqdir", "output")
START_S = config.get("start_s", 1)
DRYRUN = config.get("dryrun", False)

# Auto-detect lanes from data/Data/Intensities/BaseCalls
detected_lanes = []
basecalls_path = "data/Data/Intensities/BaseCalls"
if os.path.exists(basecalls_path):
    detected_lanes = sorted([
        int(d[1:]) for d in os.listdir(basecalls_path) 
        if d.startswith("L") and d[1:].isdigit() and os.path.isdir(os.path.join(basecalls_path, d))
    ])

print("detected_lanes:", detected_lanes)



LANES = (detected_lanes if detected_lanes else [1,2,3,4,5,6,7,8])
FASTP_THREADS = config.get("fastp_threads", 4)
FASTP_OUTDIR = config.get("fastp_outdir", "results/fastp")
FASTP_PLOTS_OUTDIR = config.get("fastp_plots_outdir", "results/fastp_plots")

# Retrieve project names from SampleSheet
def get_projects(sample_sheet_path):
    projects = set()
    if os.path.exists(sample_sheet_path):
        with open(sample_sheet_path, 'r') as f:
            lines = f.readlines()
        
        in_data = False
        header = None
        project_idx = -1
        
        for line in lines:
            line = line.strip()
            if not line: continue
            
            if line.startswith('[Data]'):
                in_data = True
                continue
            
            if in_data:
                parts = line.split(',')
                if header is None:
                    header = [h.strip() for h in parts]
                    if 'Sample_Project' in header:
                        project_idx = header.index('Sample_Project')
                elif project_idx != -1:
                    if len(parts) > project_idx:
                        p = parts[project_idx].strip()
                        if p:
                            projects.add(p)
    return sorted(list(projects))

PROJECTS = get_projects(SAMPLE_SHEET)

print("PROJECTS found in SampleSheet:", PROJECTS)

rule all:
    input:
        expand("results/postprocess_lane{lane}.done", lane=LANES),
        expand("results/fastp_plots_lane{lane}.done", lane=LANES),
        expand("Reports/{project}/index.html", project=PROJECTS)

rule report_project:
    input:
        postprocess = expand("results/postprocess_lane{lane}.done", lane=LANES),
        fastp_plots = expand("results/fastp_plots_lane{lane}.done", lane=LANES)
    output:
        "Reports/{project}/index.html"
    params:
        project = "{project}",
        output_base = "output",
        fastp_plots_base = FASTP_PLOTS_OUTDIR,
        report_dir = "Reports/{project}"
    shell:
        "python3 src/generate_report.py {params.project} {params.output_base} {params.fastp_plots_base} {params.report_dir}"

rule postprocess_lane:
    input:
        "output"
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
    conda: "perl_env"
    shell:
        """
        mkdir -p results
        perl {params.script} {params.sample_sheet} {params.num_reads} {wildcards.lane} "{params.library}" {params.fastqdir} {params.start_s} {params.dryflag}
        touch {output}
        """

rule fastp_lane:
    input:
        "output"
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
            
            # Preserve project subdirectory structure
            r1_dir=$(dirname "$r1")
            rel_dir=${{r1_dir#{params.fastqdir}}}
            rel_dir=${{rel_dir#/}}
            target_dir="{params.outdir}/lane{wildcards.lane}/$rel_dir"
            mkdir -p "$target_dir"
            
            out_prefix="$target_dir/${{sample}}"
            
            if [ -f "$r2" ]; then
                echo "fastp (paired): $r1 & $r2 -> ${{out_prefix}}_R1.fastq.gz"
                fastp -i "$r1" -I "$r2" --json "${{out_prefix}}.json" -w {params.threads} || true
            else
                echo "fastp (single): $r1 -> ${{out_prefix}}_R1.fastq.gz"
                fastp -i "$r1" --json "${{out_prefix}}.json" -w {params.threads} || true
            fi
        done
        touch {output}
        """

rule fastp_plots_lane:
    input:
        "results/fastp_lane{lane}.done"
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
        # Find all json files
        for json in $(find {params.fastp_outdir}/lane{wildcards.lane} -type f -name "*.json" 2>/dev/null); do
            # Extract relative path to preserve project structure
            # json path: .../laneX/Project/Sample.json
            # rel_path: Project/Sample.json
            rel_path=${{json#{params.fastp_outdir}/lane{wildcards.lane}/}}
            rel_dir=$(dirname "$rel_path")
            
            mkdir -p "{params.plots_outdir}/lane{wildcards.lane}/$rel_dir"
            
            sample=$(basename "$json" .json)
            out_mean="{params.plots_outdir}/lane{wildcards.lane}/$rel_dir/${{sample}}-mean_phred.png"
            out_base="{params.plots_outdir}/lane{wildcards.lane}/$rel_dir/${{sample}}-base_comp.png"
            
            echo "Plotting $json -> $out_mean, $out_base"
            python3 {params.scripts_dir}/mean_phred_plot_fastp.py "$json" --out "$out_mean" || true
            python3 {params.scripts_dir}/base_composition_plot_fastp.py "$json" --out "$out_base" || true
        done
        touch {output}
        """

rule bcl_convert:
    input:
        sample_sheet="src/SampleSheet.csv",
        data_dir=directory("data")
    output:
        directory("output")
    shell:
        """
        dragen --bcl-conversion-only true \
        --bcl-input-directory {input.data_dir} \
        --output-directory {output} \
        --force \
        --bcl-sampleproject-subdirectories true \
        --sample-sheet {input.sample_sheet} \
        --strict-mode false
        """


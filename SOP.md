# SOP: Run the Illumina BCL Conversion Snakemake Workflow

This SOP provides clear, human‑readable steps to execute the BCL conversion pipeline from
start to finish. It supports both **MiSeq i100** and **NovaSeqX** runs — the platform is
auto-detected from the metadata workbook (see step 5).

## 1) Verify prerequisites

- You have access to the run directory where BCL data is stored on dragen.
- The run has finished copying (there is a `CopyComplete.txt` file in the run directory).
- You have a SampleSheet (`.xlsx`) Excel file from the lab.
- **DRAGEN** is available on the system (`which dragen` → `/opt/dragen/<ver>/bin/dragen`).
  DRAGEN is licensed/FPGA-tied and is installed at the system level, not by pixi.
- **pixi** is installed, otherwise install it once:

    ```bash
    curl -fsSL https://pixi.sh/install.sh | bash
    ```

## 2) Copy the project template

- Navigate to the processing directory on dragen (choose the platform folder), e.g.:
  - MiSeq i100: `cd /staging/nextcloud/testing_illumina/MiSeqi100`
  - NovaSeqX:   `cd /staging/nextcloud/testing_illumina/NovaseqX`
- Clone the github repository into a run-named directory:
  `git clone https://github.com/whtns/igb_transition {RUN_NAME}`
- Enter the project directory:
  `cd {RUN_NAME}`

## 3) Provision the environment with pixi

The Python tools and bioinformatics CLIs are provisioned from `pixi.toml` (locked in
`pixi.lock`). This creates a per-project environment under `.pixi/` — no global env to
activate.

```bash
pixi install
```

This installs Python, Snakemake, and the bioconda CLIs (`fastqc`, `flexbar`, `seqtk`,
`fqtk`). Run every subsequent command with `pixi run ...` (no activation step needed).

> The legacy `bcl_convert` mamba/conda environment is retired in favor of pixi.
> DRAGEN remains a system-level tool (see step 1) and is not installed by pixi.

## 4) Copy the SampleSheet into the new project

- Upload the Excel SampleSheet into the `metadata` directory:
  `{RUN_NAME}/metadata/{SampleSheet.xlsx}`

## 5) Review and update configuration

Open and update the project overrides in `snakemake_config_project.yaml` (these are layered
over the base `snakemake_config.yaml`).

Key fields to update (example values):

- `library_name`: `iR011` (the name of the run)
- `metadata`: `metadata/SampleSheet.xlsx` (path to the Excel file)
- `data_dir`: the BCL run directory, e.g.
  - MiSeq i100: `/staging/nextcloud/Miseqi100/20260626_SH00564_0020_ASC2231455-SC3`
  - NovaSeqX:   `/staging/nextcloud/NovaseqX/20260129_LH00626_0090_B233NGJLT4`
- `email_sender`: `kstachel@uci.edu` (sender of email reports)
- `email_recipient`: `kstachel@uci.edu` (recipient of email reports)
- `external_drive_path`: mount point of the external USB drive for rsync

## 6) Validate metadata

The workflow auto-detects the platform from the workbook:

- **NovaSeqX** (has a `Summary` sheet):
  - **Summary sheet** (header at row 3): `Lane`, `Gr` (Group), `Project Name`, `Masking`, `Fastq Link`
  - **Per-project sheets**: `Lane`, `Group`, `Sample Name`, `i7 Barcode Sequence`, `i5 Barcode Sequence`
  - Ensure Masking strings match the run cycle structure in `RunInfo.xml`
- **MiSeq i100** (has a `Barcode Entries` sheet, no `Summary` sheet):
  - Simple per-sample barcodes; Order IDs inferred from the `Lab ID` column
  - All samples assigned to a single lane (`lane1`) and single group

## 7) Dry run (recommended)

Validate the workflow plan before any processing:

```bash
pixi run snakemake -n
```

The output prints the detected metadata format. Fix any missing-file or configuration
errors before proceeding.

## 8) Run the full workflow

Execute the entire pipeline (adjust `--cores` to system resources, max 32):

```bash
pixi run snakemake --cores 8
```

## 9) Run specific workflow stages (optional)

Configs are identified per lane as `lane{N}` (MiSeq uses only `lane1`; NovaSeqX may use
`lane1`…`lane8`). Run individual targets, e.g.:

- BCL conversion for a lane:
  `pixi run snakemake --cores 8 output/lane1`
- FastP analysis for a lane:
  `pixi run snakemake --cores 4 results/fastp_lane1.done`
- FastP plots for a lane:
  `pixi run snakemake --cores 4 results/lane1/fastp_plots_lane1.done`
- Project or Order report:
  `pixi run snakemake --cores 1 Reports/order_0626I-08/index.html`
- Read count CSV:
  `pixi run snakemake --cores 1 results/iR011-count.csv`

## 10) Validate outputs

Check that outputs are generated and complete:

- `output/lane{N}/` contains project FASTQ files.
- `results/fastp/` has JSON stats.
- `results/fastp_plots/` has PNG plots.
- `Reports/` contains order and project HTML reports plus md5sums and PDFs.
- `results/{library}-count.csv` exists and looks correct.

## 11) Re-run or update specific steps (if needed)

If you need to re-run a specific rule (e.g., read counts):

```bash
pixi run snakemake --cores 4 -R compile_read_counts
```

## 12) Troubleshooting quick checks

- Missing lanes: confirm `data_dir` and the detected lanes at workflow start.
- BCL conversion failures: verify DRAGEN availability (`which dragen`) and run paths.
- Empty reports: verify metadata sheet names and headers.
- md5 mismatch: regenerate the specific project report outputs.

## Email Configuration

The workflow uses `src/send_email.py` with support for:
- Plain text or HTML content
- File attachments
- Configurable SMTP settings (default: smtp.uci.edu:25)

For OAuth2 (Gmail):
- Set up Google Cloud OAuth2 credentials
- Store `client_secret.json` and `token.json` in workspace
- Modify `send_email.py` to use `google-auth` libraries
- Set environment variables for credential paths

## Advanced Features

**View rule graph:**
```bash
pixi run snakemake --rulegraph | dot -Tpdf > rulegraph.pdf
```

**View complete dependency graph:**
```bash
pixi run snakemake --dag | dot -Tpdf > dag.pdf
```

**Flexbar / inline demultiplexing** (for Flexbar-tagged projects):
- Requires barcode FASTA files (auto-generated from metadata)
- `flexbar_barcode_leader_n` / `flexbar_retry_min_reads` tune inline-barcode matching
- A bioconda `flexbar` is provided by pixi; point `flexbar_bin` at it to drop the custom build
- Processes undetermined reads

**Tile-specific processing:**
- Set `tiles: "1_1101"` in config for subset processing
- Useful for test runs or debugging

**Custom naming schemes:**
- Modify renaming map generation in Snakefile
- Update `src/run_rename.sh` script

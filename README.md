# Snakemake BCL Conversion Pipeline

Automated workflow for Illumina (MiSeq i100 / NovaSeqX) sequencing data processing, quality control, and report generation.

## Workflow Diagram

![Workflow Rule Graph](rulegraph.png)

## Overview

This Snakemake pipeline handles the complete sequencing data processing workflow:
1. **BCL Conversion** - DRAGEN BCL-to-FASTQ conversion with per-lane sample sheets
2. **File Renaming** - Systematic renaming based on lane, group, position, and barcode
3. **Quality Analysis** - FastP quality metrics for all samples
4. **Visualization** - Quality plots (mean Phred scores, base composition)
5. **Report Generation** - Comprehensive HTML reports grouped by Order ID with embedded plots and download instructions
6. **Read Count Compilation** - Lane-level read counts formatted as CSV, aggregated per library
7. **Email Notifications** - Automated email delivery of reports and read counts

## Environment

Python and the bioinformatics CLIs are provisioned with [pixi](https://pixi.sh) from
`pixi.toml` (locked in `pixi.lock`). Install pixi once, then let it build the environment:

```bash
curl -fsSL https://pixi.sh/install.sh | bash   # one-time install
pixi install                                    # solve/create env from pixi.lock
```

Run any command inside the environment with `pixi run`, or use the predefined tasks:

```bash
pixi run snakemake -n        # dry run
pixi run all                 # full workflow (snakemake --cores 8)
pixi run dry-run             # preview
pixi run convert output/lane1
```

pixi manages Python (pandas, openpyxl, numpy, matplotlib, pillow, pyyaml, reportlab),
Snakemake, and the bioconda CLIs (`fastqc`, `flexbar`, `seqtk`). Two dependencies remain
**system-level** and are not installed by pixi:

- **DRAGEN** (`/opt/dragen/<ver>/bin/dragen`) — licensed, FPGA-tied; must be on `PATH`.
- An **optional custom `flexbar` build** referenced by `flexbar_bin` in the config. A
  bioconda `flexbar` is provided by pixi; point `flexbar_bin` at it to drop the custom build.

> The legacy `bcl_convert` mamba/conda environment is being retired in favor of pixi.

## Key Files

- **`Snakefile`** - Main workflow definition; imports rules from `src/workflow_defs.smk`
- **`snakemake_config.yaml`** - Base configuration (paths, threads, email settings)
- **`snakemake_config_project.yaml`** - Project-specific configuration (overrides base settings)
- **`metadata/*.xlsx`** - Excel metadata with Summary sheet and per-project sheets
- **`src/RunInfo_nn.xml`** - Normalized run configuration (auto-generated)

## Platforms & Auto-Detection

This pipeline supports two Illumina platforms/configurations. The platform is
**auto-detected from the metadata workbook** at workflow start (no config flag needed):

| Aspect | MiSeq i100 | NovaSeqX |
|--------|-----------|----------|
| Detection | Has a `Barcode Entries` sheet, no `Summary` sheet | Has a `Summary` sheet |
| Lanes | Single lane (`lane1`) | Up to 8 lanes (`lane1`…`lane8`) |
| Groups | Single group per lane | Multiple groups per lane |
| Order IDs | Inferred from `Lab ID` column of the first sheet | Read from the `Summary` sheet |
| Example `data_dir` | `/staging/nextcloud/Miseqi100/<run>` | `/staging/nextcloud/NovaseqX/<run>` |

The workflow prints `Detected MiSeq metadata format` (or proceeds with the NovaSeqX
Summary-sheet path) so you can confirm which mode is active. This run (`iR011`) is a
**MiSeq i100** run.

## Configuration

Edit `snakemake_config_project.yaml` (project overrides layered over `snakemake_config.yaml`).

**MiSeq i100 example** (this run):

```yaml
library_name: "iR011"                    # Run identifier
metadata: "metadata/06262026_BXA66618-2426_iR011.xlsx"
data_dir: "/staging/nextcloud/Miseqi100/20260626_SH00564_0020_ASC2231455-SC3"
lanes: [1,2,3,4,5,6,7,8]                 # Superset; only lane1 is used for MiSeq
email_sender: "kstachel@uci.edu"
email_recipient: "kstachel@uci.edu"
```

**NovaSeqX example**:

```yaml
library_name: "xR077"                    # Run identifier
metadata: "metadata/251219_23G5F2LT3_10B_PE151_xR077.xlsx"
data_dir: "/staging/nextcloud/NovaseqX/20260115_LH00626_0088_A233NM2LT4"
lanes: [1,2,3,4,5,6,7,8]                 # Lanes to process (auto-detected from BaseCalls)
email_sender: "kstachel@uci.edu"
email_recipient: "kstachel@uci.edu"
```

## Metadata Format

### NovaSeqX (Summary-sheet format)
- **Summary sheet** (header at row 3):
  - `Lane`, `Gr` (Group), `Project Name`, `Masking`, `Fastq Link`
- **Per-project sheets** with sample details:
  - `Lane`, `Group`, `Sample Name`, `i7 Barcode Sequence`, `i5 Barcode Sequence`

**Masking format**: `R1:151, I1:8, I2:8, R2:151` → generates OverrideCycles

### MiSeq i100 (simple format)
- A **`Barcode Entries`** sheet with per-sample barcodes (no `Summary` sheet)
- The first sheet's **`Lab ID`** column supplies both project labels (e.g. `PaegB`)
  and Order IDs (e.g. `0626I-08`); order IDs match the pattern `\d+I-\d+`
- All samples are assigned to a single lane (`lane1`) and single group

## Workflow Steps

Configs are identified per lane as `lane{N}` (e.g. `lane1`). MiSeq i100 runs use only
`lane1`; NovaSeqX runs may use `lane1` through `lane8`. Generated sample sheets, renaming
maps, and per-lane artifacts live under `results/lane{N}/`.

### 1. Sample Sheet Generation (automatic)
- Parses metadata Excel file
- Generates per-lane sample sheets in `results/lane{N}/SampleSheet_lane{N}.csv`
- Creates renaming maps in `results/lane{N}/renaming_map_lane{N}.csv`
- Produces Flexbar barcode files for Flexbar-tagged projects

### 2. BCL Conversion
```bash
snakemake --cores 8 output/lane1
```
- Runs DRAGEN BCL Convert per lane configuration
- Applies OverrideCycles from metadata masking field
- Creates project subdirectories
- Renames FASTQ files using renaming map: `{Run}-L{Lane}-G{Group}-P{Position}-{Barcode}`

### 3. Quality Analysis (FastP)
```bash
snakemake --cores 4 results/fastp_lane1.done
```
- Runs FastP on all samples per config
- Outputs JSON stats to `results/fastp/lane{N}/{project}/{sample}.json`

### 4. Quality Plots
```bash
snakemake --cores 4 results/lane1/fastp_plots_lane1.done
```
- Generates mean Phred and base composition plots
- Outputs PNG files to `results/fastp_plots/lane{N}/{project}/{sample}-*.png`

### 5. Project/Order Reports
```bash
snakemake --cores 1 Reports/order_0626I-08/index.html
```
- Creates comprehensive HTML reports grouped by `Order ID`
- Includes summary of all projects associated with the order
- Embeds quality plots as base64 images
- Includes download instructions (browser, wget, HPC) and sorted md5 checksums
- Outputs:
  - `Reports/order_{id}/index.html`
  - `Reports/order_{id}/md5sums.txt`
  - `Reports/order_{id}/Download_Instructions.pdf`
  - `Reports/{project}/lane{lane}/index.html`

### 6. Read Count Compilation
```bash
snakemake --cores 1 results/iR011-count.csv
```
- Aggregates read counts across all lanes
- Formats as CSV with lane/group/sample/counts columns
- Sorted by read count (descending) per lane

### 7. Email Delivery
```bash
snakemake --cores 1 Reports/iR011_read_counts_email.done
```
- Sends read count CSV as attachment
- Uses SMTP (smtp.uci.edu:25)

## Common Commands

**Dry run (see what would execute):**
```bash
snakemake -n
```

**Run entire workflow:**
```bash
snakemake --cores 8
```

**Run specific project report:**
```bash
snakemake --cores 4 Reports/MyProject/index.html
```

**Analyze undetermined indices:**
```bash
snakemake --cores 1 results/undetermined_indices/lane1.csv
```

**Force re-run a specific rule:**
```bash
snakemake --cores 4 -R compile_read_counts
```

**View rule graph:**
```bash
snakemake --rulegraph | dot -Tpdf > rulegraph.pdf
```

**View complete dependency graph:**
```bash
snakemake --dag | dot -Tpdf > dag.pdf
```

## Output Structure

```
output/
  lane{N}/
    {project}/
      {Run}-L{Lane}-G{Group}-P{Position}-{Barcode}-R1.fastq.gz
      {Run}-L{Lane}-G{Group}-P{Position}-{Barcode}-R2.fastq.gz

results/
  lane{N}/
    SampleSheet_lane{N}.csv
    renaming_map_lane{N}.csv
  fastp/
    lane{N}/{project}/{sample}.json
  fastp_plots/
    lane{N}/{project}/{sample}-mean_phred.png
    lane{N}/{project}/{sample}-base_comp.png
  undetermined_indices/
    lane{N}.csv
  {library}-count.csv

Reports/
  order_{id}/
    index.html
    md5sums.txt
    Download_Instructions.pdf
    email_sent.done
  {project}/
    lane{lane}/
      index.html
      md5sums.txt
  {library}_read_counts_email.done
```

## Undetermined Reads

Two config options control how Undetermined (unassigned) reads are handled per lane:

- **`keep_undetermined_configs`** - lanes whose Undetermined FASTQs are retained
  instead of deleted after conversion. Example: `keep_undetermined_configs: ['lane1']`
- **`report_undetermined_configs`** - lanes where Undetermined reads are treated as a
  normal sample: renamed into the lane's first project directory and flowed through the
  full pipeline (fastp QC, read counts, md5sums, nextcloud links, and the per-order HTML
  report). Lanes listed here are automatically added to `keep_undetermined_configs`.
  Example: `report_undetermined_configs: ['lane1']`

Undetermined reads are also kept automatically when a
`flexbar_barcodes_{config_id}.txt` file exists for the lane.

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

## Troubleshooting

**Missing lanes in workflow:**
- Check `detected_lanes` output at workflow start
- Verify `data_dir` in config points to the correct run directory (with `Data/Intensities/BaseCalls`)

**BCL conversion fails:**
- Verify `data_dir` and `run_info_path` are correct
- Check DRAGEN is available: `which dragen`
- Review OverrideCycles match actual run cycles

**No samples in report:**
- Check metadata Excel file has correct sheet names and headers
- Verify projects are listed in Summary sheet
- Look for "PROJECTS found in SampleSheet" in workflow output

**md5 mismatches:**
- Re-run specific project: `snakemake -R report_project --cores 1 Reports/{project}/md5sums.txt`
- Verify FASTQ files weren't modified after generation

## Advanced Features

**Flexbar / inline demultiplexing** (for Flexbar-tagged projects):
- Requires barcode FASTA files (auto-generated from metadata)
- `flexbar_barcode_leader_n` sets leading bases (e.g. a UMI) before the inline barcode
  in R1 (0 = barcode at position 1; 5 for PAREseq-style U5I6 libraries)
- `flexbar_retry_min_reads` triggers a reverse-complement retry pass if no sample
  exceeds the threshold after the forward pass
- Processes undetermined reads

**Excluding orders:**
- Set `exclude_order_ids: ["0626I-08"]` to skip processing, reports, and emails for
  specific Order IDs

**Scratch space for conversion:**
- Set `scratch_dir` to fast local NVMe; DRAGEN writes FASTQs there first, then moves
  them to `output/` (avoids writing directly to slow JBOD/network storage)

**Tile-specific processing:**
- Set `tiles: "1_1101"` in config for subset processing
- Useful for test runs or debugging

## Notes

- Run commands via `pixi run` (environment provisioned from `pixi.toml` / `pixi.lock`)
- The workflow auto-detects lanes from the BaseCalls directory
- Sample sheets are generated once at workflow start from metadata
- md5 checksums are sorted by position number (P001, P002, ...)
- Reports include embedded images for email compatibility
- 2-week data retention policy is noted in all reports

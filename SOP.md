# SOP: Run the Illumina BCL Conversion Snakemake Workflow

This SOP provides clear, human‑readable steps to execute the BCL conversion pipeline from
start to finish. It supports both **MiSeq i100** and **NovaSeqX** runs — the platform is
auto-detected from the metadata workbook (see step 7).

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
  `git clone https://github.com/uci-grthub/bcl_conversion {RUN_NAME}`
- Enter the project directory:
  `cd {RUN_NAME}`
- Enable the repo's git hooks (git does not install them on clone):
  `git config core.hooksPath .githooks`
- Run the setup hook, which creates `snakemake_config_project.yaml` (gitignored, so it
  does not exist in a fresh clone) and pre-fills `metadata`, `library_name`, and `data_dir`:

    ```bash
    bash .githooks/post-checkout --sequencer novaseqx   # or: --sequencer miseqi100
    ```

  The sequencer is inferred from the working directory path if you omit the flag.
  Review its output — every value it guesses is confirmed in step 6.

## 3) Provision the environment with pixi

The Python tools and bioinformatics CLIs are provisioned from `pixi.toml` (locked in
`pixi.lock`). This creates a per-project environment under `.pixi/` — no global env to
activate.

```bash
pixi install
```

This installs Python, Snakemake, and the bioconda CLIs (`fastqc`, `fastp`, `flexbar`,
`seqtk`, `fqtk`, `seqkit`, `pigz`, `graphviz`). Run every subsequent command with
`pixi run ...` (no activation step needed).

> The legacy `bcl_convert` mamba/conda environment is retired in favor of pixi.
> DRAGEN remains a system-level tool (see step 1) and is not installed by pixi.

**Always pass `--profile profiles/default`** to snakemake (every command in this SOP
does). The profile is not optional tuning: `bcl_convert` declares
`resources: serial_operation=1`, but a resource with no global limit is unconstrained, so
without the profile DRAGEN jobs run concurrently and contend for the FPGA. It also pins
`rerun-triggers: mtime` — the snakemake default would re-run bcl-convert after an
unrelated Snakefile edit. Adjust `cores` in `profiles/default/config.yaml` to the host, or
override per-invocation with `--cores`.

## 4) Configure credentials (`.env`)

The workflow publishes FASTQ share links to Nextcloud and emails reports, so it needs
four secrets. The Snakefile refuses to start unless all four are set — including
`snakemake -n` — so do this before the dry run.

```bash
cp .env.example .env
$EDITOR .env
```

| Variable | What it is |
| --- | --- |
| `NEXTCLOUD_URL` | Nextcloud instance, e.g. `https://precision.biochem.uci.edu` |
| `NEXTCLOUD_USER` | Nextcloud account owning the share directory |
| `NEXTCLOUD_PASSWORD` | **App password** for that account, not the login password |
| `GMAIL_APP_PASSWORD` | App password for the `email_sender` account |

Generate the Nextcloud app password under **Settings > Personal > Security > Devices &
sessions > Create new app password**. `.env` is gitignored — never commit it, and use
your own credentials rather than inheriting another operator's.

Export the values into the shell before each snakemake invocation:

```bash
set -a; source .env; set +a
```

Verify Nextcloud access before running anything long:

```bash
pixi run python scripts/test_nextcloud_token.py
```

## 5) Copy the SampleSheet into the new project

- Upload the Excel SampleSheet into the `metadata` directory:
  `{RUN_NAME}/metadata/{SampleSheet.xlsx}`
- The step 2 hook already copies the newest `.xlsx` from `../SampleSheets` if one is
  there; confirm the right sheet landed in `metadata/`.

## 6) Review and update configuration

Open and update the project overrides in `snakemake_config_project.yaml` (these are layered
over the base `snakemake_config.yaml`).

The step 2 hook pre-fills the first three fields below — confirm rather than retype them.
Key fields (example values):

- `library_name`: `iR011` (the name of the run)
- `metadata`: `metadata/SampleSheet.xlsx` (path to the Excel file)
- `data_dir`: the BCL run directory, e.g.
  - MiSeq i100: `/staging/nextcloud/Miseqi100/20260626_SH00564_0020_ASC2231455-SC3`
  - NovaSeqX:   `/staging/nextcloud/NovaseqX/20260129_LH00626_0090_B233NGJLT4`
- `email_sender`: **your** address — the account whose `GMAIL_APP_PASSWORD` is in `.env`
- `email_recipient` / `email_cc`: who receives the reports. Change these from the
  committed defaults, or the run emails the previous operator.
- `external_drive_path`: mount point of the external USB drive for rsync. Site-specific;
  confirm it is mounted before the run.
- `flexbar_bin`: `flexbar` uses the pixi-provided build. Only change this to use a local
  speedup build.

## 7) Validate metadata

The workflow auto-detects the platform from the workbook:

- **NovaSeqX** (has a `Summary` sheet):
  - **Summary sheet** (header at row 3): `Lane`, `Gr` (Group), `Project Name`, `Masking`, `Fastq Link`
  - **Per-project sheets**: `Lane`, `Group`, `Sample Name`, `i7 Barcode Sequence`, `i5 Barcode Sequence`
  - Ensure Masking strings match the run cycle structure in `RunInfo.xml`
- **MiSeq i100** (has a `Barcode Entries` sheet, no `Summary` sheet):
  - Simple per-sample barcodes; Order IDs inferred from the `Lab ID` column
  - All samples assigned to a single lane (`lane1`) and single group

## 8) Dry run (recommended)

Validate the workflow plan before any processing:

```bash
set -a; source .env; set +a   # if not already exported in this shell
pixi run snakemake --profile profiles/default -n
```

The output prints the detected metadata format. Fix any missing-file or configuration
errors before proceeding. An immediate `required environment variable(s) not set` means
step 4 was skipped or the `.env` was not sourced into this shell.

## 9) Run the full workflow

Execute the entire pipeline (adjust `--cores` to system resources, max 32):

```bash
pixi run snakemake --profile profiles/default --cores 8
```

## 10) Run specific workflow stages (optional)

Configs are identified per lane as `lane{N}` (MiSeq uses only `lane1`; NovaSeqX may use
`lane1`…`lane8`). Run individual targets, e.g.:

- BCL conversion for a lane:
  `pixi run snakemake --profile profiles/default --cores 8 output/lane1`
- FastP analysis for a lane:
  `pixi run snakemake --profile profiles/default --cores 4 results/fastp_lane1.done`
- FastP plots for a lane:
  `pixi run snakemake --profile profiles/default --cores 4 results/lane1/fastp_plots_lane1.done`
- Project or Order report:
  `pixi run snakemake --profile profiles/default --cores 1 Reports/order_0626I-08/index.html`
- Read count CSV:
  `pixi run snakemake --profile profiles/default --cores 1 results/iR011-count.csv`

## 11) Validate outputs

Check that outputs are generated and complete:

- `output/lane{N}/` contains project FASTQ files.
- `results/fastp/` has JSON stats.
- `results/fastp_plots/` has PNG plots.
- `Reports/` contains order and project HTML reports plus md5sums and PDFs.
- `results/{library}-count.csv` exists and looks correct.

## 12) Re-run or update specific steps (if needed)

If you need to re-run a specific rule (e.g., read counts):

```bash
pixi run snakemake --profile profiles/default --cores 4 -R compile_read_counts
```

## 13) Troubleshooting quick checks

- `required environment variable(s) not set`: `.env` not sourced — see step 4.
- `snakemake_config_project.yaml` missing: the step 2 hook did not run; it is gitignored
  and never present in a fresh clone.
- Missing lanes: confirm `data_dir` and the detected lanes at workflow start.
- BCL conversion failures: verify DRAGEN availability (`which dragen`) and run paths.
- Empty reports: verify metadata sheet names and headers.
- md5 mismatch: regenerate the specific project report outputs.
- Nextcloud 401 / empty share links: re-run `pixi run python scripts/test_nextcloud_token.py`;
  app passwords are revoked independently of the account login.
- `command not found` for a tool: run it under `pixi run`. A bare shell may resolve a
  different build from your own `PATH`.

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
pixi run snakemake --profile profiles/default --rulegraph | dot -Tpdf > rulegraph.pdf
```

**View complete dependency graph:**
```bash
pixi run snakemake --profile profiles/default --dag | dot -Tpdf > dag.pdf
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

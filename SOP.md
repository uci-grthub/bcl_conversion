# SOP: Run the NovaSeqX Snakemake Workflow

This SOP provides clear, human‑readable steps to execute the NovaSeqX BCL conversion pipeline from start to finish.

## 1) Verify prerequisites

- You have access to the run directory where bcl data is stored on dragen.
- The run has finished copying (there is a CopyComplete.txt file in the run directory)
- You have a SampleSheet (.xslx) Excel file from the lab.
- Conda/mamba is installed, otherwise: 

    ```
    curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
    bash Miniforge3-$(uname)-$(uname -m).sh
    ```

## 1) Copy the project template.

- Navigate to the processing directory on dragen 
`cd /staging/nextcloud/testing_illumina/NovaseqX`
- Clone the github repository
`git clone https://github.com/whtns/igb_transition {RUN_NAME}`
- Enter the project directory
`/staging/nextcloud/testing_illumina/NovaSeqX/{RUN_NAME}` 

## 2) Activate the conda environment.

- Install the `bcl_convert` conda environment
  - The `bcl_convert` conda env needs to be installed only once per user
  - it needs to be activated every time the workflow is executed 
  `mamba activate bcl_convert`

## 3) Copy the SampleSheet into the new project

- Upload the excel SampleSheet {SampleSheet.xlsx} into the `metadata` directory 
`/staging/nextcloud/testing_illumina/NovaseqX/{RUN_NAME}/metadata`

## 4) Review and update configuration

Open and update the project settings:

- `snakemake_config.yaml`

Key fields to update: {example values}

- `library_name`: {xR083} (the name of the run)
- `metadata`: {`metadata/SampleSheet.xlsx`} (path to the Excel file)
- `data_dir`: {`/staging/nextcloud/NovaseqX/20260129_LH00626_0090_B233NGJLT4`} (BCL run directory)
- `email_sender`: {kstachel@uci.edu} (the sender of email reports)
- `email_recipient`: {kstachel@uci.edu} (the recipient of email reports)
- `external_drive_path`: {`/mnt/extusb3/nextcloud3/`} (the mount point of the external usb connected to dragen for rsync)

## 3) Validate metadata
The Excel metadata file must contain:

- **Summary sheet** (header at row 3):
  - `Lane`, `Gr` (Group), `Project Name`, `Masking`, `Fastq Link`
- **Per-project sheets** with sample details:
  - `Lane`, `Group`, `Sample Name`, `i7 Barcode Sequence`, `i5 Barcode Sequence`
- Ensure Masking strings match run cycle structure in RunInfo.xml

## 4) Dry run (recommended)

Run a dry run to validate the workflow plan before any processing:

- `snakemake -n`

If the dry run shows missing files or configuration errors, fix those before proceeding.

## 5) Run the full workflow

Execute the entire pipeline:

- `snakemake --cores 8`

Adjust `--cores` based on system resources (max 32).

## 6) Run specific workflow stages (optional)

If you only need certain outputs, you can run specific targets:

- BCL conversion for a lane/masking:
`snakemake --cores 8 output/lane1_R1-151_I1-8_I2-8_R2-151`

- FastP analysis for a lane/masking:
`snakemake --cores 4 results/fastp_lane1_R1-151_I1-8_I2-8_R2-151.done`

- FastP plots for a lane/masking:
`snakemake --cores 4 results/fastp_plots_lane1_R1-151_I1-8_I2-8_R2-151.done`

- Project or Order report:
`snakemake --cores 1 Reports/order_12345/index.html`

- Read count CSV:
     `snakemake --cores 1 results/xR083-count.csv`

## 7) Validate outputs

Check that outputs are generated and complete:

- `output/` contains lane and project FASTQ files.
- `results/fastp/` has JSON stats.
- `results/fastp_plots/` has PNG plots.
- `Reports/` contains order and project HTML reports plus md5sums and PDFs.
- `results/{library}-count.csv` exists and looks correct.

## 8) Re-run or update specific steps (if needed)

If you need to re-run a specific rule (e.g., read counts):

- `snakemake --cores 4 -R compile_read_counts`

## 9) Troubleshooting quick checks

- Missing lanes: confirm `basecalls_path` and detected lanes.
- BCL conversion failures: verify DRAGEN availability and run paths.
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
snakemake --rulegraph | dot -Tpdf > rulegraph.pdf
```

**View complete dependency graph:**
```bash
snakemake --dag | dot -Tpdf > dag.pdf
```

**Flexbar demultiplexing** (for Flexbar-tagged projects):
- Enable by uncommenting flexbar rule in Snakefile
- Requires barcode FASTA files (auto-generated from metadata)
- Processes undetermined reads

**Tile-specific processing:**
- Set `tiles: "1_1101"` in config for subset processing
- Useful for test runs or debugging

**Custom naming schemes:**
- Modify renaming map generation in Snakefile
- Update `src/run_rename.sh` script

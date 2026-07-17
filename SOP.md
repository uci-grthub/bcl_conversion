# SOP: Run the BCL Conversion Snakemake Workflow

Supports **MiSeq i100** and **NovaSeqX** — the platform is auto-detected from the metadata
workbook. `pixi run` auto-loads `.env` and the required Snakemake profile, so day-to-day
commands take no extra flags.

## Quickstart (a normal run)

```bash
# 1. Clone into a run-named directory and enter it
cd /staging/nextcloud/testing_illumina/NovaseqX          # or .../MiSeqi100
git clone https://github.com/uci-grthub/bcl_conversion {RUN_NAME}
cd {RUN_NAME}

# 2. Set up the run: builds the pixi env on first use, then creates
#    snakemake_config_project.yaml and copies/prefills the samplesheet
pixi run init                 # add --sequencer novaseqx|miseqi100 if the path is ambiguous

# 3. Confirm the prefilled config (secrets come from the shared ../.env — no copy needed)
$EDITOR snakemake_config_project.yaml         # confirm data_dir; set email_* to YOUR address

# 4. Validate metadata + preview the plan (no processing happens)
pixi run validate
pixi run dry-run

# 5. Run the full workflow (adjust cores to the host, max 32)
pixi run all                                  # == snakemake --cores 8
```

That's the whole loop. No `--profile`, no `source .env` — `pixi run` handles both (see
`[activation]` in `pixi.toml`).

### Prerequisites

- Run has finished copying (a `CopyComplete.txt` exists in the run directory).
- A SampleSheet `.xlsx` from the lab (dropped in `../SampleSheets`, or placed directly in
  `metadata/`).
- **DRAGEN** on the system (`which dragen` → `/opt/dragen/<ver>/bin/dragen`). Licensed /
  FPGA-tied; not installed by pixi.
- **pixi** installed once: `curl -fsSL https://pixi.sh/install.sh | bash`.

---

## Reference

### Credentials (`.env`)

The workflow publishes FASTQ links to Nextcloud and emails reports, so it needs four
secrets. The Snakefile refuses to start (including `dry-run`) unless all four are set.

| Variable | What it is |
| --- | --- |
| `NEXTCLOUD_URL` | Nextcloud instance, e.g. `https://precision.biochem.uci.edu` |
| `NEXTCLOUD_USER` | Nextcloud account owning the share directory |
| `NEXTCLOUD_PASSWORD` | **App password** for that account (not the login password) |
| `GMAIL_APP_PASSWORD` | App password for the `email_sender` account |

**These normally live in the shared per-platform file** — `../.env`
(`.../NovaSeqX/.env` or `.../MiSeqi100/.env`) — which sits one level above every run
directory. `pixi run` loads it automatically, so a fresh clone needs **no** local `.env`.
To use your own credentials for one run, drop a `./.env` in the run directory; it overrides
the shared file (and is gitignored). Generate a Nextcloud app password under **Settings >
Personal > Security > Devices & sessions > Create new app password**.

> The loader ignores any `SNAKEMAKE_PROFILE` set in a `.env`; the repo's
> `profiles/default` always wins (see `scripts/load_dotenv.sh`).

Verify access before a long run:

```bash
pixi run python scripts/test_nextcloud_token.py
```

### Configuration files

- `snakemake_config_project.yaml` — per-run overrides (gitignored). `pixi run init`
  prefills `library_name`, `metadata`, `data_dir`. You confirm those and set
  `email_sender` / `email_recipient` / `email_cc` (to **your** address — the base config
  ships these blank so a run never emails the previous operator), plus optional
  `external_drive_path`, `scratch_dir`, `tiles`, `flexbar_bin`.
- `snakemake_config.yaml` — base defaults, layered under the project file. Rarely edited.
- `profiles/default/config.yaml` — resource limits. **Not optional tuning**: it declares
  `serial_operation=1` (serializes DRAGEN so bcl-convert jobs don't contend for the FPGA)
  and pins `rerun-triggers: mtime` (so an unrelated Snakefile edit doesn't re-run hours of
  DRAGEN). Applied automatically via `SNAKEMAKE_PROFILE`. Adjust `cores` here, or override
  per run with `--cores`.

### Metadata format (auto-detected)

- **NovaSeqX** (has a `Summary` sheet):
  - Summary sheet (header row 3): `Lane`, `Gr` (Group), `Project Name`, `Masking`, `Fastq Link`
  - Per-project sheets: `Lane`, `Group`, `Sample Name`, `i7 Barcode Sequence`, `i5 Barcode Sequence`
  - Masking strings must match the run cycle structure in `RunInfo.xml`.
- **MiSeq i100** (has a `Barcode Entries` sheet, no `Summary` sheet):
  - Per-sample barcodes; Order IDs inferred from the `Lab ID` column; all samples in `lane1`.

### Run specific stages

Configs are per lane (`lane1`…`lane8`; MiSeq uses only `lane1`). Pass a target to
`pixi run snakemake`:

```bash
pixi run snakemake --cores 8 output/lane1                          # BCL conversion, one lane
pixi run snakemake --cores 4 results/fastp_lane1.done              # FastP for a lane
pixi run snakemake --cores 4 results/lane1/fastp_plots_lane1.done  # FastP plots
pixi run snakemake --cores 1 Reports/order_0626I-08/index.html     # one order report
pixi run snakemake --cores 1 results/{RUN}-count.csv               # read-count CSV
pixi run snakemake --cores 4 -R compile_read_counts                # force a rule to re-run
```

### Validate outputs

- `output/lane{N}/` — project FASTQ files
- `results/fastp/` — JSON stats; `results/fastp_plots/` — PNG plots
- `Reports/` — order/project HTML reports, md5sums, PDFs
- `results/{RUN}-count.csv` — read counts

### Automated launch (cron)

`monitor_and_run_snakemake.sh` waits for `CopyComplete.txt` in `data_dir` and launches
`pixi run all` in a tmux session named after the library. See `CRON_INSTRUCTIONS.txt`.

### Dependency graphs

```bash
pixi run rulegraph            # rulegraph.png
pixi run dag                  # dag.pdf
```

### Advanced options

- **Flexbar / inline demultiplexing**: barcode FASTAs auto-generated from metadata;
  `flexbar_barcode_leader_n` / `flexbar_retry_min_reads` tune inline matching. A bioconda
  `flexbar` is provided by pixi; point `flexbar_bin` at a local speedup build to override.
- **Tile subset** (test/debug): set `tiles: "1_1101"` in config.
- **Email**: `src/send_email.py` (SMTP default `smtp.uci.edu:25`). For Gmail OAuth2, store
  `client_secret.json` / `token.json` and switch `send_email.py` to `google-auth`.

### Troubleshooting

| Symptom | Fix |
| --- | --- |
| `required environment variable(s) not set` | `.env` missing/incomplete — see Credentials. |
| `required config value(s) are empty` | `library_name` / `metadata` / `data_dir` unset — re-run `pixi run init` or edit the project config. |
| `snakemake_config_project.yaml` missing | Run `pixi run init` (it's gitignored, absent in a fresh clone). |
| Missing lanes | Confirm `data_dir` and the detected lanes at workflow start. |
| BCL conversion fails | `which dragen`; verify run paths. |
| Empty reports | Check metadata sheet names/headers (`pixi run validate`). |
| Nextcloud 401 / empty links | `pixi run python scripts/test_nextcloud_token.py`; app passwords revoke independently. |
| `command not found` for a tool | Run under `pixi run`; a bare shell may resolve a different build. |

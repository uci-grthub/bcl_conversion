import os
import sys
import csv
from typing import List, Tuple

# Optional pandas import for robust CSV parsing; fallback to csv if unavailable
try:
    import pandas as pd  # type: ignore
except Exception:
    pd = None

# Reuse logic from rename_fastqs where possible
try:
    from rename_fastqs import is_parse_or_10x, rename_fastqs
except Exception:
    # Fallback: local definition if import fails
    def is_parse_or_10x(project_name: str) -> bool:
        """Check if project uses Illumina default naming.
        
        Returns True for: 10x (including VisiumHD, 5'V2, 3'V3, ATAC, etc.), Parse, BD.
        These platforms require Illumina default naming for downstream tools.
        """
        try:
            p = (project_name or "").lower()
        except Exception:
            p = ""
        return ("10x" in p) or ("parse" in p) or ("bd" in p)
    def rename_fastqs(config_id, output_dir, map_file):
        # Minimal wrapper; prefer calling the existing script via run_rename.sh
        pass


def ensure_dir(path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)


def rename_file_if_exists(src: str, dst: str, dry_run: bool = False):
    if os.path.abspath(src) == os.path.abspath(dst):
        return False
    if os.path.exists(src):
        if dry_run:
            print(f"Would rename: {src} -> {dst}")
            return True
        else:
            ensure_dir(dst)
            # Overwrite destination for idempotency
            try:
                if os.path.exists(dst):
                    os.remove(dst)
                os.rename(src, dst)
                return True
            except Exception as e:
                print(f"Error renaming {src} -> {dst}: {e}")
    return False


def load_map_rows(map_file: str) -> List[dict]:
    # Prefer pandas if available; otherwise use csv.DictReader
    if pd is not None:
        try:
            return pd.read_csv(map_file).to_dict(orient='records')
        except Exception as e:
            print(f"Error reading map file {map_file} with pandas: {e}")
    try:
        with open(map_file, 'r', newline='') as f:
            reader = csv.DictReader(f)
            return [row for row in reader]
    except Exception as e:
        print(f"Error reading map file {map_file} with csv: {e}")
        return []


def row_stem(row: dict, default_run: str = "") -> Tuple[str, int, str, str]:
    project = str(row.get('Sample_Project', '')).strip()
    sample_name = str(row.get('Sample_Name', row.get('Sample_ID', ''))).strip()
    try:
        lane = int(float(row.get('Lane', 0)))
    except Exception:
        lane = 0
    run = str(row.get('Run', default_run)).strip()
    try:
        group = str(int(float(row.get('Group', 0))))
    except Exception:
        group = str(row.get('Group', '')).strip()
    if group.lower() == 'nan' or not group:
        group = 'Undetermined'
    index1 = str(row.get('index', '')).strip()
    if index1.lower() == 'nan':
        index1 = ''
    index2 = str(row.get('index2', '')).strip()
    if index2.lower() == 'nan':
        index2 = ''
    barcode = f"{index1}-{index2}" if index2 else index1
    position = str(row.get('Position', '')).strip()
    if not position:
        # Fallback: use row order if needed (best-effort)
        position = 'P001'
    stem = f"{run}-L{lane}-G{group}-{position}-{barcode}"
    return stem, lane, project, sample_name


def rename_fastp_and_plots(config_id: str, map_rows: List[dict], results_base: str = "results", dry_run: bool = False):
    fastp_base = os.path.join(results_base, 'fastp', config_id)
    plots_base = os.path.join(results_base, 'fastp_plots', config_id)

    total_renamed = 0

    for idx, row in enumerate(map_rows):
        stem, lane, project, sample_name = row_stem(row)
        parse_10x = is_parse_or_10x(project)

        # Build desired path
        if project and project.lower() != 'nan':
            stem_path = f"{project}/{stem}"
            sample_path = f"{project}/{sample_name}"
        else:
            stem_path = stem
            sample_path = sample_name

        # Fastp files
        src_json_sample = os.path.join(fastp_base, f"{sample_path}.json")
        dst_json_stem = os.path.join(fastp_base, f"{stem_path}.json")
        src_html_sample = os.path.join(fastp_base, f"{sample_path}.html")
        dst_html_stem = os.path.join(fastp_base, f"{stem_path}.html")

        src_json_stem = os.path.join(fastp_base, f"{stem_path}.json")
        dst_json_sample = os.path.join(fastp_base, f"{sample_path}.json")
        src_html_stem = os.path.join(fastp_base, f"{stem_path}.html")
        dst_html_sample = os.path.join(fastp_base, f"{sample_path}.html")

        # Plots
        src_mean_sample = os.path.join(plots_base, f"{sample_path}-mean_phred.png")
        dst_mean_stem = os.path.join(plots_base, f"{stem_path}-mean_phred.png")
        src_base_sample = os.path.join(plots_base, f"{sample_path}-base_comp.png")
        dst_base_stem = os.path.join(plots_base, f"{stem_path}-base_comp.png")

        src_mean_stem = os.path.join(plots_base, f"{stem_path}-mean_phred.png")
        dst_mean_sample = os.path.join(plots_base, f"{sample_path}-mean_phred.png")
        src_base_stem = os.path.join(plots_base, f"{stem_path}-base_comp.png")
        dst_base_sample = os.path.join(plots_base, f"{sample_path}-base_comp.png")

        # For 10x/Parse keep sample-based; for others move to stem-based
        if parse_10x:
            total_renamed += int(rename_file_if_exists(src_json_stem, dst_json_sample, dry_run=dry_run))
            total_renamed += int(rename_file_if_exists(src_html_stem, dst_html_sample, dry_run=dry_run))
            total_renamed += int(rename_file_if_exists(src_mean_stem, dst_mean_sample, dry_run=dry_run))
            total_renamed += int(rename_file_if_exists(src_base_stem, dst_base_sample, dry_run=dry_run))
        else:
            total_renamed += int(rename_file_if_exists(src_json_sample, dst_json_stem, dry_run=dry_run))
            total_renamed += int(rename_file_if_exists(src_html_sample, dst_html_stem, dry_run=dry_run))
            total_renamed += int(rename_file_if_exists(src_mean_sample, dst_mean_stem, dry_run=dry_run))
            total_renamed += int(rename_file_if_exists(src_base_sample, dst_base_stem, dry_run=dry_run))

    print(f"Downstream results renamed: {total_renamed}")


def rename_fastqs_outputs(config_id: str, output_dir: str, map_file: str, dry_run: bool = False):
    """Rename FASTQ outputs from bcl_convert per FASTQ_RENAME.md.
    - 10x/Parse/BD: must be in Illumina default (<Sample_Name>_S<num>_L00<lane>_R<read>_001.fastq.gz)
      All 10x products (VisiumHD, 5'V2, 3'V3, ATAC, Multiome, etc.) use this format.
      If in custom stem format, reverse-rename back to Illumina format.
    - Default: rename from Illumina format or obsolete stem format to current stem format
      (<run>-L<lane>-G<group>-P<pos>-<barcode>-R<read>.fastq.gz)
    """
    rows = load_map_rows(map_file)
    for i, row in enumerate(rows):
        stem, lane, project, sample_name = row_stem(row)
        s_num = i + 1
        project_dir = output_dir if not project or project.lower() == 'nan' else os.path.join(output_dir, project)
        parse_10x = is_parse_or_10x(project)
        for read_type in ['R1', 'R2', 'I1', 'I2']:
            illumina_name = f"{sample_name}_S{s_num}_L{lane:03d}_{read_type}_001.fastq.gz"
            illumina_path = os.path.join(project_dir, illumina_name)
            new_name = f"{stem}-{read_type}.fastq.gz"
            new_path = os.path.join(project_dir, new_name)
            
            if parse_10x:
                # 10x/Parse/BD: ensure files are in Illumina default format
                # Check if already in Illumina format
                if os.path.exists(illumina_path):
                    if dry_run:
                        print(f"Illumina default naming: already correct: {illumina_path}")
                    continue
                
                # Check if currently in custom stem format and needs reverse-renaming
                if os.path.exists(new_path):
                    if dry_run:
                        print(f"Would reverse-rename to Illumina format: {new_path} -> {illumina_path}")
                    else:
                        rename_file_if_exists(new_path, illumina_path, dry_run=False)
                    continue
                
                # If neither exists, note it
                if dry_run and read_type == 'R1':
                    print(f"Illumina default naming: missing FASTQ: {illumina_path}")
                continue
            
            # Default projects: rename to stem format
            # Check if destination already exists (idempotency)
            if os.path.exists(new_path):
                if dry_run:
                    print(f"Already in target format: {new_path}")
                continue
            
            # Check if source is in Illumina format
            if os.path.exists(illumina_path):
                if dry_run:
                    print(f"Would rename FASTQ: {illumina_path} -> {new_path}")
                else:
                    rename_file_if_exists(illumina_path, new_path, dry_run=False)
                continue
            
            # Check for obsolete custom stem format (may have a different barcode or position from map)
            # Try to find any file matching pattern xR*-L<lane>-G*-P*-*-<read_type>.fastq.gz
            try:
                for fname in os.listdir(project_dir):
                    if not fname.endswith(f"-{read_type}.fastq.gz"):
                        continue
                    if fname == new_name:
                        continue  # Already correct
                    if "_S" in fname and f"_L{lane:03d}_" in fname:
                        continue  # Looks like Illumina format, skip (would catch above)
                    # Check if it matches old xR format pattern
                    if fname.startswith("xR") and f"-L{lane}-G" in fname and f"-{read_type}.fastq.gz" in fname:
                        obsolete_path = os.path.join(project_dir, fname)
                        if dry_run:
                            print(f"Would rename obsolete format: {obsolete_path} -> {new_path}")
                        else:
                            rename_file_if_exists(obsolete_path, new_path, dry_run=False)
                        break  # Found and handled, move to next read_type
            except OSError:
                pass  # Directory doesn't exist yet, skip
            
            # If nothing found, report missing (only for R1 to avoid noise)
            if dry_run and not os.path.exists(illumina_path) and not os.path.exists(new_path):
                if read_type == 'R1':
                    print(f"Missing FASTQ (R1): {illumina_path}")


def main():
    if len(sys.argv) < 4:
        print("Usage: python3 src/rename_pipeline_outputs.py <config_id> <output_dir> <map_file> [--results-base results] [--dry-run]")
        sys.exit(1)
    config_id = sys.argv[1]
    output_dir = sys.argv[2]
    map_file = sys.argv[3]
    results_base = 'results'
    dry_run = False
    for arg in sys.argv[4:]:
        if arg.startswith('--results-base='):
            results_base = arg.split('=', 1)[1]
        elif arg == '--dry-run':
            dry_run = True

    rows = load_map_rows(map_file)
    if not rows:
        print("No rows found in map; aborting.")
        sys.exit(1)

    if dry_run:
        print(f"Dry-run: planned renames for {config_id}")
        print(f"Output dir: {output_dir}")
        print(f"Results base: {results_base}")
        # Simulate FASTQ renames
        rename_fastqs_outputs(config_id, output_dir, map_file, dry_run=True)
        # Simulate downstream results renames
        rename_fastp_and_plots(config_id, rows, results_base=results_base, dry_run=True)
        print("Dry-run complete.")
        sys.exit(0)

    # FASTQ outputs from bcl_convert
    rename_fastqs_outputs(config_id, output_dir, map_file, dry_run=False)

    # Downstream results (fastp JSON/HTML and plots)
    rename_fastp_and_plots(config_id, rows, results_base=results_base, dry_run=False)

    print("Renaming complete.")


if __name__ == '__main__':
    main()

import os
import sys
import glob
import shutil
import json
import re
import base64
import subprocess

def extract_po_number(md5_line):
    """Extract position number from md5sum line for sorting."""
    # Format: "hash  filename" where filename contains -P001- pattern
    parts = md5_line.split()
    if len(parts) > 1:
        filename = parts[1]
        match = re.search(r'-P(\d+)-', filename)
        if match:
            return int(match.group(1))
    return float('inf')

def get_image_base64(path):
    if os.path.exists(path):
        with open(path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode('utf-8')
    return None

def get_file_size(path):
    if os.path.exists(path):
        size_bytes = os.path.getsize(path)
        # Convert to human readable
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.2f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.2f} PB"
    return "N/A"


def parse_lane_from_config(config_id):
    match = re.match(r'lane(\d+)_', config_id)
    if match:
        return int(match.group(1))
    return None

def is_parse_or_10x(project_name):
    """Check if project uses Illumina default naming.
    
    Returns True for: 10x (including VisiumHD, 5'V2, 3'V3, ATAC, etc.), Parse, BD.
    """
    try:
        p = (project_name or "").lower()
    except Exception:
        p = ""
    return ("10x" in p) or ("parse" in p) or ("bd" in p)

def generate_report(project, output_base_dir, fastp_plots_base_dir, fastp_base_dir, report_dir, fastq_links_str, lane_filter=None):
    os.makedirs(report_dir, exist_ok=True)
    lane_label = f" (Lane {lane_filter})" if lane_filter is not None else ""
    
    # Parse fastq_links (semicolon-separated)
    fastq_links = [link.strip() for link in fastq_links_str.split(';') if link.strip()]
    
    # Build download links section
    download_links_html = ""
    if fastq_links:
        download_links_html = "<p style='margin: 0 0 10px 0; line-height: 1.6;'><strong>Files for downloading:</strong></p>"
        download_links_html += "<ul style='margin: 5px 0 10px 20px; padding: 0;'>"
        for link in fastq_links:
            download_links_html += f"<li style='margin-bottom: 5px;'><a href='{link}' style='color: #0066cc;'>{link}</a></li>"
        download_links_html += "</ul>"
    
    # Gmail-compatible HTML with inline styles and table-based layout
    html_content = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Report for {project}{lane_label}</title>
</head>
<body style="font-family: 'Public Sans', 'Work Sans', Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f7fb; color: #1c2b36;">
<table width="100%" cellpadding="0" cellspacing="0" style="max-width: 900px; margin: 0 auto;">
<tr>
<td>

<!-- Hero Section -->
<div style="background: linear-gradient(135deg, rgba(0, 50, 98, 0.92), rgba(0, 50, 98, 0.7)); color: #fefefe; padding: 28px; border-radius: 14px; margin-bottom: 24px;">
<h1 style="margin: 0 0 10px 0; font-size: 28px; letter-spacing: -0.2px;">Sequencing Report: {project}{lane_label}</h1>
<p style="margin: 0 0 16px 0; max-width: 760px; color: #e9eef5;">Your sequencing data has been processed and is ready for download.</p>
</div>

<!-- Introduction Section -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 24px;">
<tr>
<td style="padding: 18px; background-color: #ffffff; border-radius: 14px; box-shadow: 0 14px 30px rgba(0, 34, 68, 0.12); border: 1px solid rgba(0, 50, 98, 0.06);">
<p style="margin: 0 0 10px 0; line-height: 1.6;"><strong>Dear GRTHub User,</strong></p>
<p style="margin: 0 0 10px 0; line-height: 1.6;">The sequencing data for the samples you submitted to the GRTHub has been processed and is now available for downloading in FastQ file format.</p>
<p style="margin: 0 0 10px 0; line-height: 1.6;">Your fastq files will remain available for downloading during a period of <strong>2 weeks only</strong>. Please download your files immediately and verify their integrity using the provided MD5sum values as soon as possible, and before the end of this period. After 2 weeks, the fastq files will be deleted from our servers.</p>
<p style="margin: 0; line-height: 1.6;"><strong>A file containing the MD5sum for your FastQ files is included in this report.</strong></p>
</td>
</tr>
</table>

<!-- Download Links Section -->
<div style="margin-bottom: 24px;">
<h2 style="margin: 0 0 12px 0; font-size: 20px; letter-spacing: -0.2px; color: #333333;">Your Download Links</h2>
<div style="background: #fff9ec; border: 1px solid rgba(245, 183, 0, 0.5); color: #7a5800; padding: 14px 16px; border-radius: 14px; margin-bottom: 16px; box-shadow: 0 8px 18px rgba(245, 183, 0, 0.12);">
<strong style="display: block; margin-bottom: 8px;">📋 Direct Links:</strong>
{download_links_html}
<div style="margin-top: 10px; padding-top: 10px; border-top: 1px solid rgba(0, 0, 0, 0.1); font-size: 13px;">
<strong>To download entire folder as zip:</strong> Append <code style="background: rgba(0,0,0,0.1); padding: 2px 4px; border-radius: 3px;">/download</code> to the link above.
</div>
</div>
</div>

<!-- Download Methods Section -->
<div style="margin-bottom: 24px;">
<h2 style="margin: 0 0 12px 0; font-size: 20px; letter-spacing: -0.2px; color: #333333;">How to Download</h2>
<p style="margin: 0 0 14px 0; color: #66788a;">Choose the method that works best for your setup:</p>

<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 12px;">
<tr>
<td style="padding: 18px; background-color: #ffffff; border-radius: 14px; box-shadow: 0 14px 30px rgba(0, 34, 68, 0.12); border: 1px solid rgba(0, 50, 98, 0.06); margin-bottom: 12px;">
<h3 style="margin: 4px 0 10px 0; font-size: 16px; color: #333333;">🌐 Browser (One-click)</h3>
<p style="margin: 0 0 8px 0; color: #66788a; font-size: 13px;">Windows, macOS, Linux</p>
<ul style="margin: 8px 0 0; padding-left: 18px;">
<li style="margin-bottom: 6px;">Open your download link from the section above in any web browser.</li>
<li style="margin-bottom: 6px;">Click <strong>Download</strong> (top-right in the Nextcloud interface) to fetch the entire folder as a zip.</li>
<li>Or click individual files to download them one by one.</li>
</ul>
</td>
</tr>

<tr>
<td style="padding: 18px; background-color: #ffffff; border-radius: 14px; box-shadow: 0 14px 30px rgba(0, 34, 68, 0.12); border: 1px solid rgba(0, 50, 98, 0.06); margin-bottom: 12px;">
<h3 style="margin: 4px 0 10px 0; font-size: 16px; color: #333333;">💻 Command Line (wget)</h3>
<p style="margin: 0 0 8px 0; color: #66788a; font-size: 13px;">Linux / macOS / Windows (WSL)</p>
<ul style="margin: 8px 0 0; padding-left: 18px;">
<li style="margin-bottom: 6px;">Open a terminal and navigate to your target folder.</li>
<li style="margin-bottom: 6px;">Download the entire folder as zip:<br><code style="display: block; background: #0f172a; color: #f7fafc; padding: 8px; border-radius: 6px; margin: 6px 0; font-family: monospace; font-size: 12px; overflow-x: auto;">wget --content-disposition "YOUR_LINK/download"</code></li>
<li style="margin-bottom: 6px;">Or download a single file:<br><code style="display: block; background: #0f172a; color: #f7fafc; padding: 8px; border-radius: 6px; margin: 6px 0; font-family: monospace; font-size: 12px; overflow-x: auto;">wget --content-disposition "YOUR_LINK/download?path=/&files=FILENAME"</code></li>
</ul>
</td>
</tr>

<tr>
<td style="padding: 18px; background-color: #ffffff; border-radius: 14px; box-shadow: 0 14px 30px rgba(0, 34, 68, 0.12); border: 1px solid rgba(0, 50, 98, 0.06); margin-bottom: 12px;">
<h3 style="margin: 4px 0 10px 0; font-size: 16px; color: #333333;">🖥️ HPC / Remote Servers</h3>
<p style="margin: 0 0 8px 0; color: #66788a; font-size: 13px;">Cluster or shared server environments</p>
<ul style="margin: 8px 0 0; padding-left: 18px;">
<li style="margin-bottom: 6px;">SSH to your remote server and navigate to desired directory.</li>
<li style="margin-bottom: 6px;">Use the same <code style="background: #0f172a; color: #f7fafc; padding: 2px 4px; border-radius: 3px; font-family: monospace;">wget</code> commands as above to download directly to the remote filesystem.</li>
<li>For faster transfers, consider using <code style="background: #0f172a; color: #f7fafc; padding: 2px 4px; border-radius: 3px; font-family: monospace;">parallel wget</code> or <code style="background: #0f172a; color: #f7fafc; padding: 2px 4px; border-radius: 3px; font-family: monospace;">aria2</code> for large datasets.</li>
</ul>
</td>
</tr>

<tr>
<td style="padding: 18px; background-color: #ffffff; border-radius: 14px; box-shadow: 0 14px 30px rgba(0, 34, 68, 0.12); border: 1px solid rgba(0, 50, 98, 0.06);">
<h3 style="margin: 4px 0 10px 0; font-size: 16px; color: #333333;">📥 Download Managers</h3>
<p style="margin: 0 0 8px 0; color: #66788a; font-size: 13px;">For resumable/multi-threaded downloads</p>
<ul style="margin: 8px 0 0; padding-left: 18px;">
<li style="margin-bottom: 6px;"><strong>Windows:</strong> VisualWget, Internet Download Manager (IDM)</li>
<li style="margin-bottom: 6px;"><strong>macOS:</strong> iGetter, Downie</li>
<li style="margin-bottom: 6px;"><strong>Cross-platform:</strong> aria2, axel</li>
</ul>
</td>
</tr>
</table>
</div>

<!-- Samples Section Header -->
<h2 style="margin: 32px 0 12px 0; font-size: 20px; letter-spacing: -0.2px; color: #333333;">Sample Details</h2>
<p style="margin: 0 0 14px 0; color: #66788a;">Below are the quality metrics and file information for each sample:</p>
"""
    
    # Find all samples from fastp JSONs
    # Structure: results/fastp/{config_id}/{project}/{stem}.json
    # We need to iterate over config_ids (lanes)
    
    # We can glob: results/fastp/*/{project}/*.json
    json_pattern = os.path.join(fastp_base_dir, "*", project, "*.json")
    print(f"Searching for JSONs with pattern: {json_pattern}")
    json_files = glob.glob(json_pattern)
    print(f"Found {len(json_files)} JSON files.")
    
    # Load renaming maps to get barcode info for 10x/Parse/BD projects
    renaming_maps = {}
    for json_file in json_files:
        parts = json_file.split(os.sep)
        try:
            config_id = parts[-3]
            if config_id not in renaming_maps:
                map_path = f"src/renaming_map_{config_id}.csv"
                if os.path.exists(map_path):
                    try:
                        import pandas as pd
                        renaming_maps[config_id] = pd.read_csv(map_path)
                    except:
                        import csv
                        with open(map_path, 'r') as f:
                            renaming_maps[config_id] = list(csv.DictReader(f))
        except:
            pass
    
    samples = {} # stem -> { 'lanes': { lane_id: { info... } } }
    md5_lines = []
    
    for json_file in json_files:
        # Extract config_id (lane)
        # path: .../results/fastp/{config_id}/{project}/{stem}.json
        parts = json_file.split(os.sep)
        # Assuming standard structure
        try:
            # Find 'fastp' in path to locate config_id
            # It should be the parent of the parent of the file
            # .../fastp/lane1_.../project/file.json
            # So config_id is parts[-3] if file is parts[-1]
            config_id = parts[-3]
            stem = os.path.splitext(os.path.basename(json_file))[0]
        except:
            print(f"Could not parse path: {json_file}")
            continue

        lane_val = parse_lane_from_config(config_id)
        if lane_filter is not None and lane_val != lane_filter:
            continue
            
        # Parse JSON
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            summary = data.get('summary', {}).get('before_filtering', {})
            total_reads = summary.get('total_reads', 0)
            read1_len = summary.get('read1_mean_length', 0)
            read2_len = summary.get('read2_mean_length', 0)
            
            is_paired = read2_len > 0
            
            if is_paired:
                paired_reads = total_reads // 2
            else:
                paired_reads = total_reads
            
            # Extract Barcode from stem or sample_name
            # For 10x/Parse/BD: need to look up barcode from renaming map
            # For default: extract from stem format {run}-L{lane}-G{group}-{position}-{barcode}
            use_illumina_naming = is_parse_or_10x(project)
            
            if use_illumina_naming:
                # Look up barcode from renaming map
                barcode = "Unknown"
                if config_id in renaming_maps:
                    map_data = renaming_maps[config_id]
                    # Find row matching this sample
                    if isinstance(map_data, list):
                        # CSV DictReader format
                        for row in map_data:
                            if str(row.get('Sample_Name', '')).strip() == stem:
                                index1 = str(row.get('index', '')).strip()
                                index2 = str(row.get('index2', '')).strip()
                                if index1 and index1.lower() != 'nan':
                                    if index2 and index2.lower() != 'nan':
                                        barcode = f"{index1}-{index2}"
                                    else:
                                        barcode = index1
                                break
                    else:
                        # Pandas DataFrame format
                        matching = map_data[map_data['Sample_Name'].astype(str).str.strip() == stem]
                        if not matching.empty:
                            row = matching.iloc[0]
                            index1 = str(row.get('index', '')).strip()
                            index2 = str(row.get('index2', '')).strip()
                            if index1 and index1.lower() != 'nan':
                                if index2 and index2.lower() != 'nan':
                                    barcode = f"{index1}-{index2}"
                                else:
                                    barcode = index1
            else:
                # Extract from stem format: {run}-L{lane}-G{group}-{position}-{barcode}
                match = re.search(r'-(P\d{3})-(.+)$', stem)
                if match:
                    position = match.group(1)
                    barcode = match.group(2)
                else:
                    barcode = "Unknown"
                
            # File paths: check if 10x/Parse/BD project (uses Illumina naming) or default (uses stem naming)
            
            if use_illumina_naming:
                # For 10x/Parse/BD: sample_name is the stem in the JSON filename
                # Need to get sample_name from renaming map or construct from pattern
                # Pattern: {sample_name}_S{num}_L{lane:03d}_R{read}_001.fastq.gz
                # We can derive lane from config_id
                lane_num = parse_lane_from_config(config_id)
                if lane_num is None:
                    lane_num = 1
                
                # Try to find the actual sample name from the JSON path or infer from pattern
                # The stem in the JSON filename for 10x is actually the sample_name
                sample_name = stem
                
                # Try to find R1 file with pattern matching
                # Look for any file in the directory that matches the sample pattern
                project_dir = os.path.join(output_base_dir, config_id, project)
                if os.path.exists(project_dir):
                    # Look for R1 files matching the sample name pattern
                    r1_candidates = glob.glob(os.path.join(project_dir, f"{sample_name}_S*_L{lane_num:03d}_R1_001.fastq.gz"))
                    if r1_candidates:
                        r1_path = r1_candidates[0]
                    else:
                        # Fallback: try pattern with any S number
                        r1_candidates = glob.glob(os.path.join(project_dir, f"*{sample_name}*_R1_001.fastq.gz"))
                        r1_path = r1_candidates[0] if r1_candidates else os.path.join(project_dir, f"{sample_name}_S1_L{lane_num:03d}_R1_001.fastq.gz")
                else:
                    r1_path = os.path.join(output_base_dir, config_id, project, f"{sample_name}_S1_L{lane_num:03d}_R1_001.fastq.gz")
            else:
                # Default: use stem format
                r1_path = os.path.join(output_base_dir, config_id, project, f"{stem}-R1.fastq.gz")
                
            r1_size = get_file_size(r1_path)
            
            r1_md5 = "N/A"
            if os.path.exists(r1_path):
                try:
                    cmd = ['md5sum', r1_path]
                    result = subprocess.run(cmd, capture_output=True, text=True)
                    if result.returncode == 0:
                        hash_val = result.stdout.split()[0]
                        md5_lines.append(f"{hash_val}  {os.path.basename(r1_path)}")
                        r1_md5 = hash_val
                except Exception as e:
                    print(f"Error calculating md5 for {r1_path}: {e}")
            
            r2_size = "N/A"
            r2_md5 = "N/A"
            if is_paired:
                if use_illumina_naming:
                    # Construct R2 path for Illumina naming
                    if r1_path and os.path.exists(r1_path):
                        # Replace R1 with R2 in the actual path
                        r2_path = r1_path.replace("_R1_001.fastq.gz", "_R2_001.fastq.gz")
                    else:
                        lane_num = parse_lane_from_config(config_id) or 1
                        sample_name = stem
                        r2_path = os.path.join(output_base_dir, config_id, project, f"{sample_name}_S1_L{lane_num:03d}_R2_001.fastq.gz")
                else:
                    # Stem format
                    r2_path = os.path.join(output_base_dir, config_id, project, f"{stem}-R2.fastq.gz")
                    
                r2_size = get_file_size(r2_path)
                
                if os.path.exists(r2_path):
                    try:
                        cmd = ['md5sum', r2_path]
                        result = subprocess.run(cmd, capture_output=True, text=True)
                        if result.returncode == 0:
                            hash_val = result.stdout.split()[0]
                            md5_lines.append(f"{hash_val}  {os.path.basename(r2_path)}")
                            r2_md5 = hash_val
                    except Exception as e:
                        print(f"Error calculating md5 for {r2_path}: {e}")

            # Index reads (I1/I2) are optional; calculate md5 if present
            for idx_read in ["I1", "I2"]:
                if use_illumina_naming:
                    # Construct index path for Illumina naming
                    if r1_path and os.path.exists(r1_path):
                        idx_path = r1_path.replace("_R1_001.fastq.gz", f"_{idx_read}_001.fastq.gz")
                    else:
                        lane_num = parse_lane_from_config(config_id) or 1
                        sample_name = stem
                        idx_path = os.path.join(output_base_dir, config_id, project, f"{sample_name}_S1_L{lane_num:03d}_{idx_read}_001.fastq.gz")
                else:
                    # Stem format
                    idx_path = os.path.join(output_base_dir, config_id, project, f"{stem}-{idx_read}.fastq.gz")
                    
                if os.path.exists(idx_path):
                    try:
                        cmd = ['md5sum', idx_path]
                        result = subprocess.run(cmd, capture_output=True, text=True)
                        if result.returncode == 0:
                            hash_val = result.stdout.split()[0]
                            md5_lines.append(f"{hash_val}  {os.path.basename(idx_path)}")
                    except Exception as e:
                        print(f"Error calculating md5 for {idx_path}: {e}")
            
            info = {
                'barcode': barcode,
                'paired_reads': paired_reads,
                'is_paired': is_paired,
                'r1_size': r1_size,
                'r2_size': r2_size,
                'r1_md5': r1_md5,
                'r2_md5': r2_md5,
                'json_path': json_file
            }
            
            if stem not in samples:
                samples[stem] = {}
            samples[stem][config_id] = info
            
        except Exception as e:
            print(f"Error processing {json_file}: {e}")
            
    sorted_stems = sorted(samples.keys())
    
    for stem in sorted_stems:
        # Sample Section
        html_content += f"""
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 20px; border: 1px solid #cccccc;">
<tr>
<td style="padding: 15px;">
<h2 style="color: #333333; font-size: 20px; margin: 0 0 15px 0;">Sample: {stem}</h2>
"""
        
        # Basic Info Table
        html_content += """
<h3 style="color: #333333; font-size: 16px; margin: 0 0 10px 0;">Basic Info</h3>
<table width="100%" cellpadding="8" cellspacing="0" style="border-collapse: collapse; margin-bottom: 15px;">
<thead>
<tr style="background-color: #f2f2f2;">
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">Barcode</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">Paired Reads</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">Type</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R1 Size</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R1 MD5</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R2 Size</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R2 MD5</th>
</tr>
</thead>
<tbody>
"""
        
        lane_configs = sorted(samples[stem].keys())
        for config_id in lane_configs:
            info = samples[stem][config_id]
            type_str = "Paired" if info['is_paired'] else "Single"
            html_content += f"""
<tr>
<td style="border: 1px solid #dddddd; padding: 8px;">{info['barcode']}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{info['paired_reads']}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{type_str}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{info['r1_size']}</td>
<td style="border: 1px solid #dddddd; padding: 8px; font-family: monospace; font-size: 11px;">{info['r1_md5']}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{info['r2_size']}</td>
<td style="border: 1px solid #dddddd; padding: 8px; font-family: monospace; font-size: 11px;">{info['r2_md5']}</td>
</tr>
"""
        html_content += "</tbody></table>"
        
        # Plots section using tables
        html_content += "<h3 style='color: #333333; font-size: 16px; margin: 15px 0 10px 0;'>Quality Plots</h3>"
        
        for config_id in lane_configs:
            # Look for plots in fastp_plots_base_dir/{config_id}/{project}/{stem}-*.png
            plot_dir = os.path.join(fastp_plots_base_dir, config_id, project)
            mean_plot = f"{stem}-mean_phred.png"
            base_plot = f"{stem}-base_comp.png"
            
            src_mean = os.path.join(plot_dir, mean_plot)
            src_base = os.path.join(plot_dir, base_plot)
            
            print(f"Checking for plots in {plot_dir} for {stem}")
            if os.path.exists(src_mean):
                print(f"Found mean plot: {src_mean}")
            else:
                print(f"Missing mean plot: {src_mean}")
                
            if os.path.exists(src_base):
                print(f"Found base plot: {src_base}")
            else:
                print(f"Missing base plot: {src_base}")
            
            if os.path.exists(src_mean) or os.path.exists(src_base):
                html_content += f"<p style='font-weight: bold; margin: 10px 0 5px 0;'>{config_id}</p>"
                html_content += "<table width='100%' cellpadding='0' cellspacing='0'><tr>"
                
                if os.path.exists(src_mean):
                    b64_mean = get_image_base64(src_mean)
                    if b64_mean:
                        html_content += f"<td style='padding: 5px; width: 50%;'><img src='data:image/png;base64,{b64_mean}' alt='Mean Phred' style='width: 100%; max-width: 100%; height: auto; border: 1px solid #dddddd;'></td>"
                
                if os.path.exists(src_base):
                    b64_base = get_image_base64(src_base)
                    if b64_base:
                        html_content += f"<td style='padding: 5px; width: 50%;'><img src='data:image/png;base64,{b64_base}' alt='Base Composition' style='width: 100%; max-width: 100%; height: auto; border: 1px solid #dddddd;'></td>"
                
                html_content += "</tr></table>"
        
        html_content += "</td></tr></table>"
        
    # Footer with contact info
    html_content += """
<div style="margin: 40px 0 0 0; padding: 18px 0 0 0; border-top: 1px solid rgba(0, 50, 98, 0.08); color: #66788a; font-size: 13px;">
<p style="margin: 0 0 6px 0;"><strong>Questions?</strong> Contact the UCI Genomics Research and Technology Hub</p>
<p style="margin: 0;">Email: <a href="mailto:mloakes@uci.edu" style="color: #1f6feb; text-decoration: none;">mloakes@uci.edu</a> | Phone: (949) 824-5327 | Fax: (949) 824-2688</p>
<p style="margin: 6px 0 0 0;"><a href="https://genomics.uci.edu/" style="color: #1f6feb; text-decoration: none;">Visit genomics.uci.edu</a></p>
</div>

</td></tr></table></body></html>
"""
    
    with open(os.path.join(report_dir, "index.html"), 'w') as f:
        f.write(html_content)

    # Write md5sums.txt sorted by position number
    md5_file_path = os.path.join(report_dir, "md5sums.txt")
    unique_lines = list(set(md5_lines))
    # Sort by PO number, then by filename
    unique_lines.sort(key=lambda line: (extract_po_number(line), line.split()[1] if len(line.split()) > 1 else line))
    with open(md5_file_path, 'w') as f:
        for line in unique_lines:
            f.write(line + "\n")
    print(f"Generated {md5_file_path}")

if __name__ == "__main__":
    if len(sys.argv) < 7:
        print("Usage: generate_report.py <project> <output_base> <fastp_plots_base> <fastp_base> <report_dir> <fastq_links> [lane]")
        print("  fastq_links: semicolon-separated list of download links")
        sys.exit(1)
        
    project = sys.argv[1]
    output_base = sys.argv[2]
    fastp_plots_base = sys.argv[3]
    fastp_base = sys.argv[4]
    report_dir = sys.argv[5]
    fastq_links = sys.argv[6]
    lane_filter = None
    if len(sys.argv) >= 8:
        try:
            lane_filter = int(sys.argv[7])
        except Exception:
            lane_filter = sys.argv[7]
    
    generate_report(project, output_base, fastp_plots_base, fastp_base, report_dir, fastq_links, lane_filter)

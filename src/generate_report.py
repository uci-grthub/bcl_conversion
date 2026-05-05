import os
import sys
import glob
import shutil
import json
import re
import base64
import subprocess
from io import BytesIO

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

def get_image_base64(path, max_width=600, quality=35):
    """
    Load image, compress it, and return base64-encoded string.
    
    Args:
        path: Path to the image file
        max_width: Maximum width in pixels (maintains aspect ratio)
        quality: JPEG quality (1-95, lower = smaller file)
    
    Returns:
        Base64-encoded compressed image string
    """
    if not os.path.exists(path):
        return None
    
    try:
        from PIL import Image
        
        # Open image
        img = Image.open(path)
        
        # Resize if larger than max_width
        if img.width > max_width:
            ratio = max_width / img.width
            new_height = int(img.height * ratio)
            img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
        
        # Convert RGBA to RGB if needed (for JPEG)
        if img.mode in ('RGBA', 'LA', 'P'):
            background = Image.new('RGB', img.size, (255, 255, 255))
            if img.mode == 'P':
                img = img.convert('RGBA')
            background.paste(img, mask=img.split()[-1] if img.mode in ('RGBA', 'LA') else None)
            img = background
        
        # Save as compressed JPEG to BytesIO
        buffer = BytesIO()
        img.save(buffer, format='JPEG', quality=quality, optimize=True)
        buffer.seek(0)
        
        # Encode to base64
        return base64.b64encode(buffer.read()).decode('utf-8')
        
    except ImportError:
        # Fallback if PIL not available - just encode original
        with open(path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode('utf-8')
    except Exception as e:
        print(f"Error compressing image {path}: {e}")
        # Fallback to original encoding
        try:
            with open(path, "rb") as image_file:
                return base64.b64encode(image_file.read()).decode('utf-8')
        except:
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
    match = re.match(r'lane(\d+)', config_id)
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

def rc_index2(barcode):
    """Return a reverse-complement fallback for barcode matching."""
    if not barcode or barcode == "Unknown":
        return barcode

    def _rc(seq):
        table = str.maketrans("ACGTacgt", "TGCAtgca")
        return seq.translate(table)[::-1]

    parts = str(barcode).split("-")
    if len(parts) == 2:
        return f"{parts[0]}-{_rc(parts[1])}"
    return _rc(str(barcode))

def compose_plots_base64(image_paths, total_width=900, quality=35, background_color=(255, 255, 255)):
    """
    Compose up to three PNG plot images side-by-side into a single JPEG and return base64.
    - image_paths: list of existing file paths (max 3 will be used)
    - total_width: target total width of the composed image in pixels (configurable via config)
    - quality: JPEG quality for output, 1-95 (configurable via config, lower = smaller file)
    - background_color: RGB tuple for canvas background
    Returns base64 string or None on failure.
    """
    try:
        from PIL import Image
    except Exception:
        return None

    try:
        # Filter only existing files and cap at 3
        files = [p for p in image_paths if p and os.path.exists(p)][:3]
        if not files:
            return None

        n = len(files)
        # Per-image width (equal split)
        per_w = max(1, total_width // n)

        resized = []
        max_h = 0
        for p in files:
            img = Image.open(p).convert('RGB')
            w, h = img.size
            if w > per_w:
                # scale down maintaining aspect ratio
                ratio = per_w / float(w)
                new_w = per_w
                new_h = max(1, int(h * ratio))
                img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
                w, h = img.size
            resized.append(img)
            if h > max_h:
                max_h = h

        # Create canvas and paste images horizontally
        total_w = sum(im.size[0] for im in resized)
        canvas = Image.new('RGB', (total_w, max_h), background_color)
        x = 0
        for im in resized:
            # top align; could center vertically if needed
            canvas.paste(im, (x, 0))
            x += im.size[0]

        buffer = BytesIO()
        canvas.save(buffer, format='JPEG', quality=quality, optimize=True)
        buffer.seek(0)
        import base64 as _b64
        return _b64.b64encode(buffer.read()).decode('utf-8')
    except Exception as e:
        print(f"Error composing plots {image_paths}: {e}")
        return None

def parse_flexbar_written_reads(log_path):
    """Parse flexbarOut.log and return per-barcode written read counts.

    Returns:
        dict: {barcode_name: {'r1': int|None, 'r2': int|None}}
    """
    counts = {}
    if not log_path or not os.path.exists(log_path):
        return counts

    try:
        with open(log_path) as fh:
            text = fh.read()

        for m in re.finditer(
            r'Read file:\s+(\S+)\n\s+written reads\s+(\d+)',
            text,
        ):
            fname = os.path.basename(m.group(1))
            written = int(m.group(2))
            name_match = re.match(r'flexbarOut_barcode_(.+?)(?:_R2)?\.fastq\.gz$', fname)
            if not name_match:
                continue
            name = name_match.group(1)
            is_r2 = fname.endswith('_R2.fastq.gz')
            if name not in counts:
                counts[name] = {'r1': None, 'r2': None}
            if is_r2:
                counts[name]['r2'] = written
            else:
                counts[name]['r1'] = written
    except Exception as e:
        print(f"Warning: could not parse flexbar counts from {log_path}: {e}")

    return counts

def parse_fqtk_demux_metrics(metrics_path):
    """Parse fqtk demux-metrics.txt and return per-sample read counts.

    Returns:
        dict: {sample_name: int_reads}
    """
    counts = {}
    if not metrics_path or not os.path.exists(metrics_path):
        return counts

    try:
        with open(metrics_path) as fh:
            header_line = None
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if header_line is None:
                    header_line = parts
                    continue

                row = dict(zip(header_line, parts))
                sample_name = (row.get("barcode_name") or row.get("sample_id") or "").strip()
                reads_raw = (row.get("templates") or row.get("reads") or "0").strip()
                if not sample_name:
                    continue

                try:
                    counts[sample_name] = counts.get(sample_name, 0) + int(reads_raw)
                except ValueError:
                    continue
    except Exception as e:
        print(f"Warning: could not parse fqtk counts from {metrics_path}: {e}")

    return counts

def generate_report(project, output_base_dir, fastp_plots_base_dir, fastp_base_dir, report_dir, fastq_links_str, lane_filter=None, append_mode=False, links_yaml=None, order_id=None, library_name=None, plots_total_width=900, plots_quality=35, orig_project_name=None, project_name_map=None):
    os.makedirs(report_dir, exist_ok=True)
    lane_label = f" (Lane {lane_filter})" if lane_filter is not None else ""

    # Default library name if not provided
    if not library_name:
        library_name = "Unknown"

    # Display name: prefer original metadata project name over renamed directory name
    display_project = (project_name_map or {}).get(project) or orig_project_name or project
    
    # Parse fastq_links (semicolon-separated) for current project
    project_fastq_links = [link.strip() for link in fastq_links_str.split(';') if link.strip()]

    # If appending to an existing report, collect existing download links from the "Your Download Links" section
    html_file_path = os.path.join(report_dir, "index.html")
    existing_samples_html = ""
    existing_download_links = []
    existing_project_links = {}
    
    if append_mode and os.path.exists(html_file_path):
        with open(html_file_path, 'r') as f:
            existing_content = f.read()
        # Extract existing sample sections to append to
        match = re.search(r'(<h2[^>]*>Sample Details</h2>.*?)(<div style="margin: 40px 0 0 0; padding: 18px 0 0 0; border-top:)', existing_content, re.DOTALL)
        if match:
            existing_samples_html = match.group(1)
        
        # Extract existing links between "Your Download Links" and next section "How to Download"
        start_idx = existing_content.find("Your Download Links")
        if start_idx != -1:
            end_idx = existing_content.find("How to Download", start_idx)
            if end_idx == -1:
                end_idx = len(existing_content)
            links_section = existing_content[start_idx:end_idx]
            # Find anchor hrefs in that section
            existing_download_links = re.findall(r"<a\\s+href=['\"]([^'\"]+)['\"][^>]*>", links_section)        
    # Always attempt to pull lane/group metadata from YAML for this order_id
    if links_yaml and order_id and os.path.exists(links_yaml):
        try:
            import yaml
            with open(links_yaml, 'r') as f:
                all_links_data = yaml.safe_load(f) or {}
            # Collect links for all projects in this order_id
            for proj_name, lane_configs in all_links_data.items():
                for lane_config, lane_links in lane_configs.items():
                    if isinstance(lane_links, dict):
                        for oid, link_data in lane_links.items():
                            if oid == order_id:
                                if proj_name not in existing_project_links:
                                    existing_project_links[proj_name] = {}
                                # Handle both old format (string) and new format (dict with link/group)
                                if isinstance(link_data, dict):
                                    existing_project_links[proj_name][lane_config] = link_data
                                else:
                                    # Old format: just a string link
                                    existing_project_links[proj_name][lane_config] = {'link': link_data, 'group': ''}
        except Exception as e:
            print(f"Warning: Could not read links from YAML: {e}")    
    
    # Build consolidated list of all download links with metadata
    # Format: list of dicts with {link, project, config_id, lane, run, group}
    seen = set()
    all_download_links = []

    def _extract_group_from_name(name):
        if not name:
            return ''
        m = re.search(r'_L\d+_G(\d+)', name)
        if m:
            return m.group(1)
        m = re.search(r'_G(\d+)', name)
        if m:
            return m.group(1)
        m = re.search(r'-G(\d+)', name)
        if m:
            return m.group(1)
        return ''

    def _infer_group_from_renaming_maps(project, lane_filter=None):
        groups = set()
        try:
            for map_path in glob.glob('results/renaming_map_*.csv'):
                try:
                    with open(map_path) as mf:
                        header = mf.readline().strip().split(',')
                        cols = {c: i for i, c in enumerate(header)}
                        for line in mf:
                            parts = line.strip().split(',')
                            if len(parts) < len(header):
                                continue
                            sp_idx = cols.get('Sample_Project')
                            lane_idx = cols.get('Lane')
                            group_idx = cols.get('Group')
                            sample_project = parts[sp_idx].strip() if (sp_idx is not None and sp_idx < len(parts)) else ''
                            lane = parts[lane_idx].strip() if (lane_idx is not None and lane_idx < len(parts)) else ''
                            group = parts[group_idx].strip() if (group_idx is not None and group_idx < len(parts)) else ''
                            if not sample_project:
                                continue
                            if sample_project == project:
                                if lane_filter:
                                    try:
                                        lf = int(lane_filter) if not isinstance(lane_filter, (list, tuple)) else int(lane_filter[0])
                                    except Exception:
                                        lf = None
                                    if lf is not None and lane and int(lane) != lf:
                                        continue
                                if group and group.lower() not in ('', 'nan'):
                                    groups.add(group)
                except Exception:
                    continue
        except Exception:
            return ''
        if groups:
            # Return the smallest numeric group if possible, else any
            try:
                nums = sorted(int(g) for g in groups)
                return str(nums[0])
            except Exception:
                return sorted(groups)[0]
        return ''
    
    # Add existing links from HTML (no metadata available)
    for lk in existing_download_links:
        if lk not in seen:
            seen.add(lk)
            all_download_links.append({'link': lk, 'project': 'Unknown', 'config_id': '', 'lane': '', 'run': library_name, 'group': ''})
    
    # Add links from other projects in the order_id from YAML
    for proj_name, config_links in existing_project_links.items():
        for config_id, link_data in config_links.items():
            # Extract link and group from dict
            if isinstance(link_data, dict):
                lk = link_data.get('link', '')
                group = link_data.get('group', '')
            else:
                lk = link_data
                group = ''
            
            if lk and lk not in seen:
                seen.add(lk)
                # Extract lane from config_id (format: lane1_R1-151_I1-8_I2-8_R2-151)
                lane_match = re.match(r'lane(\d+)', config_id)
                lane_num = lane_match.group(1) if lane_match else ''
                # If group missing, try to infer from project name
                group_inferred = group or _extract_group_from_name(proj_name) or _extract_group_from_name((project_name_map or {}).get(proj_name, '')) or _extract_group_from_name(orig_project_name) or _infer_group_from_renaming_maps(proj_name, lane_num)
                all_download_links.append({
                    'link': lk,
                    'project': (project_name_map or {}).get(proj_name, proj_name),
                    'config_id': config_id,
                    'lane': lane_num,
                    'run': library_name,
                    'group': group_inferred
                })
    
    # Add current project's links if not already added from YAML
    for lk in project_fastq_links:
        if lk not in seen:
            seen.add(lk)
            # Try to determine config_id from the link path or from available data
            # For now, use basic metadata
            group_inferred = _extract_group_from_name(display_project) or _extract_group_from_name(orig_project_name) or _infer_group_from_renaming_maps(display_project, lane_filter)
            all_download_links.append({
                'link': lk,
                'project': display_project,
                'config_id': '', 
                'lane': str(lane_filter) if lane_filter else '',
                'run': library_name,
                'group': group_inferred
            })

    # Sort links by lane (numeric) then group (try numeric, fallback to string)
    def sort_key(link_info):
        try:
            lane_num = int(link_info['lane']) if link_info['lane'] else 999999
        except (ValueError, TypeError):
            lane_num = 999999
        try:
            group_num = int(link_info['group']) if link_info['group'] else 999999
        except (ValueError, TypeError):
            group_num = 999999
        return (lane_num, group_num, link_info['group'])
    
    all_download_links.sort(key=sort_key)

    # HTML for top "Your Download Links" section with metadata
    all_download_links_html = ""
    if all_download_links:
        all_download_links_html = "<table style='width: 100%; border-collapse: collapse; margin: 5px 0 10px 0;'>\n"
        all_download_links_html += "<thead><tr style='background: rgba(0,0,0,0.05); font-weight: bold; font-size: 12px;'>"
        all_download_links_html += "<th style='padding: 6px 8px; text-align: left; border-bottom: 2px solid rgba(0,0,0,0.1);'>Project</th>"
        all_download_links_html += "<th style='padding: 6px 8px; text-align: left; border-bottom: 2px solid rgba(0,0,0,0.1);'>Run</th>"
        all_download_links_html += "<th style='padding: 6px 8px; text-align: left; border-bottom: 2px solid rgba(0,0,0,0.1);'>Lane</th>"
        all_download_links_html += "<th style='padding: 6px 8px; text-align: left; border-bottom: 2px solid rgba(0,0,0,0.1);'>Group</th>"
        all_download_links_html += "<th style='padding: 6px 8px; text-align: left; border-bottom: 2px solid rgba(0,0,0,0.1);'>Download Link</th>"
        all_download_links_html += "</tr></thead>\n<tbody>\n"
        
        for link_info in all_download_links:
            all_download_links_html += "<tr style='border-bottom: 1px solid rgba(0,0,0,0.05);'>"
            all_download_links_html += f"<td style='padding: 6px 8px; font-size: 13px;'>{link_info['project']}</td>"
            all_download_links_html += f"<td style='padding: 6px 8px; font-size: 13px;'>{link_info['run']}</td>"
            all_download_links_html += f"<td style='padding: 6px 8px; font-size: 13px;'>{link_info['lane']}</td>"
            all_download_links_html += f"<td style='padding: 6px 8px; font-size: 13px;'>{link_info['group']}</td>"
            all_download_links_html += f"<td style='padding: 6px 8px;'><a href='{link_info['link']}' style='color: #0066cc; font-size: 12px; word-break: break-all;'>{link_info['link']}</a></td>"
            all_download_links_html += "</tr>\n"
        
        all_download_links_html += "</tbody></table>\n"

    # HTML for per-project links inside the project section
    project_download_links_html = ""
    if project_fastq_links:
        # Only render the list of links here; the section header already includes the project name
        project_download_links_html = "<ul style='margin: 5px 0 10px 20px; padding: 0;'>\n"
        for link in project_fastq_links:
            project_download_links_html += f"<li style='margin-bottom: 5px;'><a href='{link}' style='color: #0066cc;'>{link}</a></li>\n"
        project_download_links_html += "</ul>\n"
    
    # Load pre-computed md5 sums from all config directories
    md5_lookup = {}  # {basename: md5_hash} - for fast lookups
    md5_lines_for_report = []  # Lines to write to consolidated md5sums.txt
    
    # Find all md5sums.txt files in output directories
    # Priority: Load from project-level first (output/*/*/md5sums.txt), then lane-level (output/*/md5sums.txt)
    
    def _md5_key_variants(basename):
        variants = [basename]
        normalized = re.sub(r'_S\d+_', '_S_', basename)
        if normalized not in variants:
            variants.append(normalized)
        return variants

    # First pass: load project-level md5s (these have the actual file checksums)
    for md5_file in glob.glob("output/*/*/md5sums.txt"):
        try:
            project_from_path = os.path.basename(os.path.dirname(md5_file))
            with open(md5_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    parts = line.split(None, 1)
                    if len(parts) == 2:
                        md5_hash, filepath = parts
                        # Normalize path - remove leading ./
                        filepath_normalized = filepath.lstrip('./')
                        # Store with basename as key for lookup (most common case)
                        basename = os.path.basename(filepath_normalized)
                        for key in _md5_key_variants(basename):
                            md5_lookup[key] = md5_hash
                        
                        # Also collect for this specific project
                        if project == project_from_path:
                            md5_lines_for_report.append(f"{md5_hash}  {filepath_normalized}")
        except Exception as e:
            print(f"Error reading md5 file {md5_file}: {e}")
    
    # Second pass: load lane-level consolidated files (only for lanes without project files)
    for md5_file in glob.glob("output/*/md5sums.txt"):
        try:
            with open(md5_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    parts = line.split(None, 1)
                    if len(parts) == 2:
                        md5_hash, filepath = parts
                        filepath_normalized = filepath.lstrip('./')
                        basename = os.path.basename(filepath_normalized)
                        # Only add if not already in lookup (project-level takes priority)
                        for key in _md5_key_variants(basename):
                            if key not in md5_lookup:
                                md5_lookup[key] = md5_hash
        except Exception as e:
            print(f"Error reading md5 file {md5_file}: {e}")
    
    # existing_samples_html populated above when append_mode
    
    # Gmail-compatible HTML with inline styles and table-based layout
    html_content = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Report for {display_project}{lane_label}</title>
</head>
<body style="font-family: 'Public Sans', 'Work Sans', Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f7fb; color: #1c2b36;">
<table width="100%" cellpadding="0" cellspacing="0" style="max-width: 900px; margin: 0 auto;">
<tr>
<td>

<!-- Introduction Section -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 24px;">
<tr>
<td style="padding: 18px; background-color: #ffffff; border-radius: 14px; box-shadow: 0 14px 30px rgba(0, 34, 68, 0.12); border: 1px solid rgba(0, 50, 98, 0.06);">
<p style="margin: 0 0 10px 0; line-height: 1.6;"><strong>Dear GRTHub User,</strong></p>
<p style="margin: 0 0 10px 0; line-height: 1.6;">The sequencing data for the samples you submitted to the GRTHub has been processed and is now available for downloading in FastQ file format. If you would like to work with your data on UCI HPC3, GRTHub staff can transfer the data directly for you; please contact GRTHub directly to facilitate this.</p>
<p style="margin: 0 0 10px 0; line-height: 1.6;">Your fastq files will remain available for downloading during a period of <strong>1 month only</strong>. Please download your files immediately and verify their integrity using the provided md5sum values as soon as possible, and before the end of this period. After 1 month, the FastQ files will be deleted from our servers.</p>
<p style="margin: 0; line-height: 1.6;"><strong>A file containing the md5sum for your FastQ files is included in this report. Instructions for downloading the files are attached.</strong></p>
</td>
</tr>
</table>

<!-- Download Links Section -->
<div style="margin-bottom: 24px;">
<h2 style="margin: 0 0 12px 0; font-size: 20px; letter-spacing: -0.2px; color: #333333;">Your Download Links</h2>
<div style="background: #fff9ec; border: 1px solid rgba(245, 183, 0, 0.5); color: #7a5800; padding: 14px 16px; border-radius: 14px; margin-bottom: 16px; box-shadow: 0 8px 18px rgba(245, 183, 0, 0.12);">
<strong style="display: block; margin-bottom: 8px;">📋 Direct Links:</strong>
{all_download_links_html}
<div style="margin-top: 10px; padding-top: 10px; border-top: 1px solid rgba(0, 0, 0, 0.1); font-size: 13px;">
<strong>To download entire folder as zip:</strong> Append <code style="background: rgba(0,0,0,0.1); padding: 2px 4px; border-radius: 3px;">/download</code> to the link above.
</div>
</div>
</div>

<!-- Samples Section Header -->
<h2 style="margin: 32px 0 12px 0; font-size: 20px; letter-spacing: -0.2px; color: #333333;">Sample Details</h2>
<p style="margin: 0 0 14px 0; color: #66788a;">Below are the quality metrics and file information for each sample:</p>

"""
    
    # If appending, include existing samples first
    if existing_samples_html:
        # Extract only prior sample tables, excluding any md5 sections
        samples_match = re.search(r'<p style=.*?Below are the quality metrics.*?</p>\s*(.*)', existing_samples_html, re.DOTALL)
        if samples_match:
            prior_block = samples_match.group(1)
            md5_idx = prior_block.find("md5 Checksums")
            if md5_idx != -1:
                prior_block = prior_block[:md5_idx]
            html_content += prior_block
    
    # Add a project separator for this new project's samples
    html_content += f"""
<div style="background: #e6f2ff; border-left: 4px solid #0066cc; padding: 12px 16px; margin: 24px 0 16px 0; border-radius: 6px;">
<h3 style="margin: 0; color: #003d82; font-size: 18px;">Project: {display_project}</h3>
{project_download_links_html}
</div>
"""
    
    # Find all samples from fastp JSONs.
    # Structure: results/{config_id}/{project}/{stem}.fastp.json
    # Some flexbar projects keep fastp outputs under the original project name,
    # while the report is rendered for the renamed folder name. Search both.
    fastp_lookup_names = []
    fastp_lookup_name = orig_project_name or project
    for candidate in (project, orig_project_name):
        if candidate and candidate not in fastp_lookup_names:
            fastp_lookup_names.append(candidate)

    json_files = []
    for fastp_lookup_name in fastp_lookup_names:
        json_pattern = os.path.join(fastp_base_dir, "*", fastp_lookup_name, "*.fastp.json")
        print(f"Searching for JSONs with pattern: {json_pattern}")
        json_files.extend(glob.glob(json_pattern))

    # Deduplicate while preserving order.
    json_files = list(dict.fromkeys(json_files))
    print(f"Found {len(json_files)} JSON files.")
    
    # Load renaming maps to get barcode info for 10x/Parse/BD projects
    renaming_maps = {}
    for json_file in json_files:
        parts = json_file.split(os.sep)
        try:
            config_id = parts[-3]
            if config_id not in renaming_maps:
                map_path = f"results/renaming_map_{config_id}.csv"
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
    
    samples = {} # stem -> { config_id: { info... } }
    demux_stats_cache = {}  # config_id -> {(orig_project, index): num_reads}
    fqtk_counts_cache = {}   # config_id -> {sample_name: num_reads}
    flexbar_counts_cache = {}  # config_id -> {barcode_name: {'r1': int|None, 'r2': int|None}}
    flexbar_label_cache = {}   # config_id -> {barcode_label: sample_name}

    for json_file in json_files:
        # Extract config_id (lane)
        # path: .../results/{config_id}/{project}/{stem}.fastp.json
        parts = json_file.split(os.sep)
        try:
            config_id = parts[-3]
            stem = os.path.splitext(os.path.basename(json_file))[0]
            if stem.endswith('.fastp'):
                stem = stem[:-6]
        except:
            print(f"Could not parse path: {json_file}")
            continue

        # Lazily load Demultiplex_Stats.csv for this config_id
        if config_id not in demux_stats_cache:
            demux_csv = os.path.join(output_base_dir, config_id, "Reports", "Demultiplex_Stats.csv")
            demux_stats_cache[config_id] = {}
            if os.path.exists(demux_csv):
                try:
                    import csv as _csv
                    with open(demux_csv, 'r') as _f:
                        for _row in _csv.DictReader(_f):
                            _proj = _row.get('Sample_Project', '').strip()
                            _idx = _row.get('Index', '').strip().rstrip('-')
                            _reads = _row.get('# Reads', '').strip()
                            if _proj and _idx and _reads:
                                try:
                                    demux_stats_cache[config_id][(_proj, _idx)] = int(_reads)
                                except ValueError:
                                    pass
                except Exception as _e:
                    print(f"Warning: Could not load demux stats from {demux_csv}: {_e}")

        lane_val = parse_lane_from_config(config_id)
        if lane_filter is not None:
            if isinstance(lane_filter, list):
                if lane_val not in lane_filter:
                    continue
            elif lane_val != lane_filter:
                continue
        
        # Validate that FASTQ files exist for this sample before processing
        # This filters out deprecated samples that only have fastp JSON but no actual FASTQ files
        project_dir = os.path.join(output_base_dir, config_id, project)
        # Use fastp_lookup_name (orig_project_name) for the naming-style check:
        # after renaming the project name no longer contains "10x", "parse", etc.
        use_illumina_naming = is_parse_or_10x(fastp_lookup_name)

        fastq_exists = False
        if use_illumina_naming:
            # For 10x/Parse/BD: check if any R1 file matching the stem pattern exists
            r1_candidates = glob.glob(os.path.join(project_dir, f"*{stem}*_R1_001.fastq.gz"))
            fastq_exists = len(r1_candidates) > 0
        else:
            # For default naming: check if {stem}-R1.fastq.gz exists
            r1_path = os.path.join(project_dir, f"{stem}-R1.fastq.gz")
            fastq_exists = os.path.exists(r1_path)
        
        if not fastq_exists:
            print(f"Skipping sample {stem} - no FASTQ files found (deprecated/stale sample)")
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
            # For flexbar projects, fastp only sees R1 so read2_mean_length is 0.
            # Detect pairing by checking whether the seqtk-generated R2 file exists.
            if not is_paired and not is_parse_or_10x(fastp_lookup_name):
                candidate_r2 = os.path.join(output_base_dir, config_id, project, f"{stem}-R2.fastq.gz")
                if os.path.exists(candidate_r2):
                    is_paired = True
            paired_reads = None

            # Extract Barcode from stem or sample_name
            # For 10x/Parse/BD: need to look up barcode from renaming map
            # For default: extract from stem format {run}-L{lane}-G{group}-{position}-{barcode}
            use_illumina_naming = is_parse_or_10x(fastp_lookup_name)
            
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

            _cache = demux_stats_cache.get(config_id, {})
            demux_reads = _cache.get((fastp_lookup_name, barcode)) or _cache.get((fastp_lookup_name, rc_index2(barcode)))
            paired_reads = demux_reads if (demux_reads is not None and demux_reads > 0) else "N/A"

            # Fallback: for fqtk-staged reads, derive paired reads from fqtk demux-metrics.
            if paired_reads == "N/A":
                if config_id not in fqtk_counts_cache:
                    fqtk_metrics_candidates = [
                        os.path.join(output_base_dir, config_id, project, "demux-metrics.txt"),
                        os.path.join(output_base_dir, config_id, "fqtk", "demux-metrics.txt"),
                        os.path.join(output_base_dir, config_id, "demux-metrics.txt"),
                    ]
                    fqtk_counts_cache[config_id] = {}
                    for fqtk_metrics in fqtk_metrics_candidates:
                        if os.path.exists(fqtk_metrics):
                            fqtk_counts_cache[config_id] = parse_fqtk_demux_metrics(fqtk_metrics)
                            break

                _fqtk_counts = fqtk_counts_cache.get(config_id, {})
                fqtk_reads = _fqtk_counts.get(stem)
                if isinstance(fqtk_reads, int) and fqtk_reads > 0:
                    paired_reads = fqtk_reads

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
            
            # Lookup md5 from pre-computed files
            r1_basename = os.path.basename(r1_path)
            r1_md5 = md5_lookup.get(r1_basename, "N/A")
            # If not found by basename, try to search for a partial match in md5s
            if r1_md5 == "N/A":
                # Try matching by searching through all keys for similar names
                for key in md5_lookup:
                    if key in r1_basename or r1_basename in key:
                        r1_md5 = md5_lookup[key]
                        break
            
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
                # Lookup md5 from pre-computed files
                r2_basename = os.path.basename(r2_path)
                r2_md5 = md5_lookup.get(r2_basename, "N/A")
                # If not found by basename, try to search for a partial match in md5s
                if r2_md5 == "N/A":
                    # Try matching by searching through all keys for similar names
                    for key in md5_lookup:
                        if key in r2_basename or r2_basename in key:
                            r2_md5 = md5_lookup[key]
                            break

            # Fallback: for flexbar-staged FASTQs, derive paired reads from flexbarOut.log
            # by looking up the barcode label in the flexbar barcodes file to get sample_name.
            if paired_reads == "N/A":
                if config_id not in flexbar_counts_cache:
                    flexbar_log = os.path.join(output_base_dir, config_id, "flexbar", "flexbarOut.log")
                    flexbar_counts_cache[config_id] = parse_flexbar_written_reads(flexbar_log)

                _flex_counts = flexbar_counts_cache.get(config_id, {})
                if _flex_counts:
                    if config_id not in flexbar_label_cache:
                        _label_map = {}
                        _bc_file = os.path.join("metadata", f"flexbar_barcodes_{config_id}.txt")
                        if os.path.exists(_bc_file):
                            with open(_bc_file) as _bfh:
                                for _bline in _bfh:
                                    _bp = _bline.strip().split('\t')
                                    if len(_bp) >= 2 and _bp[0].strip() and _bp[1].strip():
                                        _label_map[_bp[1].strip()] = _bp[0].strip()
                        flexbar_label_cache[config_id] = _label_map

                    _label_map = flexbar_label_cache.get(config_id, {})
                    _sample_name = _label_map.get(barcode)
                    if _sample_name and _sample_name in _flex_counts:
                        rec = _flex_counts[_sample_name]
                        r1_written = rec.get('r1')
                        r2_written = rec.get('r2')
                        if isinstance(r1_written, int) and isinstance(r2_written, int):
                            paired_reads = min(r1_written, r2_written)
                        elif isinstance(r1_written, int):
                            paired_reads = r1_written

            # Skip index read md5 calculation (too slow for large files)
            
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
<h2 style="color: #333333; font-size: 20px; margin: 0 0 15px 0;">{stem}</h2>
"""
        
        # Basic Info Table
        html_content += """
<table width="100%" cellpadding="8" cellspacing="0" style="border-collapse: collapse; margin-bottom: 15px;">
<thead>
<tr style="background-color: #f2f2f2;">
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">Barcode</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">Paired Reads</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">Type</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R1 Size</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R1 md5sum</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R2 Size</th>
<th style="border: 1px solid #dddddd; padding: 8px; text-align: left; font-weight: bold;">R2 md5sum</th>
</tr>
</thead>
<tbody>
"""
        
        lane_configs = sorted(samples[stem].keys())
        for config_id in lane_configs:
            info = samples[stem][config_id]
            type_str = "Paired" if info['is_paired'] else "Single"
            pr = info['paired_reads']
            pr_str = f"{pr:,}" if isinstance(pr, int) else pr
            html_content += f"""
<tr>
<td style="border: 1px solid #dddddd; padding: 8px;">{info['barcode']}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{pr_str}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{type_str}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{info['r1_size']}</td>
<td style="border: 1px solid #dddddd; padding: 8px; font-family: monospace; font-size: 11px;">{info['r1_md5']}</td>
<td style="border: 1px solid #dddddd; padding: 8px;">{info['r2_size']}</td>
<td style="border: 1px solid #dddddd; padding: 8px; font-family: monospace; font-size: 11px;">{info['r2_md5']}</td>
</tr>
"""
        html_content += "</tbody></table>"
        
        # Plots section using tables (composed image of up to three plots)
        html_content += "<h3 style='color: #333333; font-size: 16px; margin: 15px 0 10px 0;'>Quality Plots</h3>"

        for config_id in lane_configs:
            # Look for plots in fastp_plots_base_dir/{config_id}/{project}/{stem}-*.png
            # Use orig_project_name for file lookups if provided (fastp runs before rename)
            plot_dir = os.path.join(fastp_plots_base_dir, config_id, fastp_lookup_name)
            expected = [
                os.path.join(plot_dir, f"{stem}-mean_phred.png"),
                os.path.join(plot_dir, f"{stem}-base_comp.png"),
                # Optional third plot type if present (future-proof): pick any third matching pattern
            ]

            # If fewer than 3 expected plots exist, try to find additional matching images
            candidates = [p for p in expected if os.path.exists(p)]
            if len(candidates) < 3 and os.path.exists(plot_dir):
                wildcard_matches = sorted(glob.glob(os.path.join(plot_dir, f"{stem}-*.png")))
                for m in wildcard_matches:
                    if m not in candidates:
                        candidates.append(m)
                    if len(candidates) >= 3:
                        break

            print(f"Checking for plots in {plot_dir} for {stem}")
            for c in candidates:
                print(f"Found plot: {c}")
            if not candidates:
                print("No plots found for sample.")

            if candidates:
                html_content += f"<p style='font-weight: bold; margin: 10px 0 5px 0;'>{config_id}</p>"
                html_content += "<div style='margin-bottom: 12px;'>"

                # Compose up to three plots into one image
                composed_b64 = compose_plots_base64(candidates, total_width=plots_total_width, quality=plots_quality)
                if composed_b64:
                    html_content += f"<img src='data:image/jpeg;base64,{composed_b64}' alt='Quality plots' style='width: 100%; max-width: 100%; height: auto; border: 1px solid #dddddd;'>"
                else:
                    # Fallback: embed individually (compressed)
                    for c in candidates:
                        b64 = get_image_base64(c)
                        if b64:
                            html_content += f"<img src='data:image/jpeg;base64,{b64}' alt='Plot' style='width: 32%; max-width: 32%; margin-right: 1%; height: auto; border: 1px solid #dddddd;'>"

                html_content += "</div>"
        
        html_content += "</td>\n</tr>\n</table>"
        
    # Footer Section
    html_content += """
<div style="margin: 40px 0 0 0; padding: 18px 0 0 0; border-top: 1px solid rgba(0, 50, 98, 0.08); color: #66788a; font-size: 13px;">
<p style="margin: 0 0 6px 0;"><strong>Questions?</strong> Contact the UCI Genomics Research and Technology Hub</p>
<p style="margin: 0;">Email: <a href="mailto:mloakes@uci.edu" style="color: #1f6feb; text-decoration: none;">mloakes@uci.edu</a> | Phone: (949) 824-5327 | Fax: (949) 824-2688</p>
<p style="margin: 6px 0 0 0;"><a href="https://genomics.uci.edu/" style="color: #1f6feb; text-decoration: none;">Visit genomics.uci.edu</a></p>
</div>

</td>
</tr>
</table>
</body>
</html>
"""
    
    with open(os.path.join(report_dir, "index.html"), 'w') as f:
        f.write(html_content)

    # Write consolidated md5sums.txt with pre-computed md5 values
    md5_file_path = os.path.join(report_dir, "md5sums.txt")
    
    # In append mode, merge with existing md5 sums
    if append_mode and os.path.exists(md5_file_path):
        with open(md5_file_path, 'r') as f:
            existing_lines = [line.strip() for line in f if line.strip() and not line.startswith('#')]
        md5_lines_for_report.extend(existing_lines)
    
    # Remove duplicates and sort
    unique_lines = list(set(md5_lines_for_report))
    unique_lines.sort(key=lambda line: (extract_po_number(line), line.split()[1] if len(line.split()) > 1 else line))
    
    with open(md5_file_path, 'w') as f:
        f.write("# md5 checksums for FASTQ files\n")
        for line in unique_lines:
            f.write(line + "\n")
    
    # Generate Download Instructions PDF (only once, not in append mode)
    if not append_mode:
        pdf_path = os.path.join(report_dir, "Download_Instructions.pdf")
        pdf_script = os.path.join(os.path.dirname(__file__), "generate_download_instructions_pdf.py")
        try:
            subprocess.run(["python3", pdf_script, pdf_path], check=True, capture_output=True, text=True)
            print(f"Download instructions PDF generated: {pdf_path}")
        except subprocess.CalledProcessError as e:
            print(f"Warning: Could not generate download instructions PDF: {e.stderr}")
        except Exception as e:
            print(f"Warning: Could not generate download instructions PDF: {e}")
    
    
    print(f"Report generated: {os.path.join(report_dir, 'index.html')}")
    print(f"md5 sums written: {md5_file_path} ({len(unique_lines)} files)")

if __name__ == "__main__":
    if len(sys.argv) < 7:
        print("Usage: generate_report.py <project> <output_base> <fastp_plots_base> <fastp_base> <report_dir> <fastq_links> [lane] [links_yaml] [order_id] [library_name] [plots_total_width] [plots_quality]")
        print("  fastq_links: semicolon-separated list of download links")
        print("  lane: optional lane filter")
        print("  links_yaml: optional path to project_links.yaml file")
        print("  order_id: optional order_id for consolidating links from all projects")
        print("  library_name: optional library/run name to display in reports")
        print("  plots_total_width: optional total width for composed plots (default: 900)")
        print("  plots_quality: optional JPEG quality for composed plots (default: 35)")
        sys.exit(1)
        
    project = sys.argv[1]
    output_base = sys.argv[2]
    fastp_plots_base = sys.argv[3]
    fastp_base = sys.argv[4]
    report_dir = sys.argv[5]
    fastq_links = sys.argv[6]
    lane_filter = None
    links_yaml = None
    order_id = None
    library_name = None
    
    if len(sys.argv) >= 8:
        arg7 = sys.argv[7]
        if arg7 != "None":
            if ',' in arg7:
                try:
                    lane_filter = [int(x) for x in arg7.split(',')]
                except Exception:
                    lane_filter = arg7
            else:
                try:
                    lane_filter = int(arg7)
                except Exception:
                    lane_filter = arg7
    
    if len(sys.argv) >= 9:
        links_yaml = sys.argv[8]
    
    if len(sys.argv) >= 10:
        order_id = sys.argv[9]
    
    if len(sys.argv) >= 11:
        library_name = sys.argv[10]
    
    plots_total_width = 900
    if len(sys.argv) >= 12:
        try:
            plots_total_width = int(sys.argv[11])
        except ValueError:
            plots_total_width = 900
    
    plots_quality = 35
    if len(sys.argv) >= 13:
        try:
            plots_quality = int(sys.argv[12])
        except ValueError:
            plots_quality = 35

    orig_project_name = None
    if len(sys.argv) >= 14:
        val = sys.argv[13]
        if val and val != "None":
            orig_project_name = val

    project_name_map = None
    if len(sys.argv) >= 15:
        val = sys.argv[14]
        if val and val != "None":
            try:
                import json as _json
                project_name_map = _json.loads(val)
            except Exception:
                pass

    # If report_dir already exists with an index.html, this is a continuation (multiple projects for same order_id)
    append_mode = os.path.exists(os.path.join(report_dir, "index.html"))

    generate_report(project, output_base, fastp_plots_base, fastp_base, report_dir, fastq_links, lane_filter, append_mode=append_mode, links_yaml=links_yaml, order_id=order_id, library_name=library_name, plots_total_width=plots_total_width, plots_quality=plots_quality, orig_project_name=orig_project_name, project_name_map=project_name_map)

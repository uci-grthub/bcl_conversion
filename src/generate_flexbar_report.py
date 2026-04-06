"""
Generate an HTML report for a flexbar-demuxed order.

Parses flexbarOut.log for per-barcode read counts and filtering statistics,
size.txt for file sizes, and md5sum.txt for checksums.

Usage:
    python3 generate_flexbar_report.py <flexbar_dir> <report_dir> <links_yaml>
                                        <order_id> <library_name>

    flexbar_dir  : e.g. output/lane8/flexbar
    report_dir   : e.g. Reports/order_0326I-32
    links_yaml   : e.g. logs/flexbar_project_links_lane8.yaml
    order_id     : e.g. 0326I-32
    library_name : e.g. xR087
"""

import os
import re
import sys
import yaml


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def parse_flexbar_log(log_path):
    """Return (barcodes, per_barcode_stats, filtering_stats).

    barcodes: dict  {name: sequence}
    per_barcode_stats: dict  {name: {written_reads, short_reads}}
    filtering_stats: dict with keys processed/skipped_uncalled/skipped_short/
                     discarded/remaining/remaining_pct
    """
    barcodes = {}
    per_barcode = {}
    filtering = {}

    if not os.path.exists(log_path):
        return barcodes, per_barcode, filtering

    with open(log_path) as fh:
        text = fh.read()

    # --- barcode name/sequence table ---
    # Lines look like:  "293T-1                 NNNNNCGTGATNNNN"
    # preceded by the header "Barcode:               Sequence:"
    barcode_section = re.search(
        r'Barcode:\s+Sequence:\s*\n(.*?)(?:\n\n|\nAdapter:|\nProcessing)',
        text, re.DOTALL
    )
    if barcode_section:
        for line in barcode_section.group(1).splitlines():
            parts = line.split()
            if len(parts) >= 2:
                barcodes[parts[0]] = parts[1]

    # --- per-file output stats ---
    # Each block:
    #   Read file:               .../flexbarOut_barcode_293T-1.fastq.gz
    #     written reads          60565116
    #     short reads            54596
    for m in re.finditer(
        r'Read file:\s+(\S+)\s+written reads\s+(\d+)\s+short reads\s+(\d+)',
        text
    ):
        fname = os.path.basename(m.group(1))
        written = int(m.group(2))
        short   = int(m.group(3))
        # extract barcode name from filename
        # flexbarOut_barcode_293T-1.fastq.gz  -> 293T-1
        # flexbarOut_barcode_293T-1_R2.fastq.gz  -> 293T-1 (R2)
        name_match = re.match(r'flexbarOut_barcode_(.+?)(?:_R2)?\.fastq\.gz$', fname)
        if name_match:
            name = name_match.group(1)
            is_r2 = '_R2.fastq.gz' in fname
            if name not in per_barcode:
                per_barcode[name] = {}
            key = 'r2_written' if is_r2 else 'r1_written'
            per_barcode[name][key] = written
            if not is_r2:
                per_barcode[name]['r1_short'] = short

    # --- filtering stats ---
    filt_m = re.search(
        r'Filtering statistics\s*={3,}\s*'
        r'Processed reads\s+([\d,]+).*?'
        r'skipped due to uncalled bases\s+([\d,]+).*?'
        r'finally skipped short reads\s+([\d,]+).*?'
        r'Discarded reads overall\s+([\d,]+).*?'
        r'Remaining reads\s+([\d,]+)\s+\((\d+)%\)',
        text, re.DOTALL
    )
    if filt_m:
        def _i(s): return int(s.replace(',', ''))
        filtering = {
            'processed':        _i(filt_m.group(1)),
            'skipped_uncalled': _i(filt_m.group(2)),
            'skipped_short':    _i(filt_m.group(3)),
            'discarded':        _i(filt_m.group(4)),
            'remaining':        _i(filt_m.group(5)),
            'remaining_pct':    int(filt_m.group(6)),
        }

    return barcodes, per_barcode, filtering


def parse_size_file(size_path):
    """Return {filename: size_string} e.g. {'flexbarOut_barcode_293T-1.fastq.gz': '2.0G'}."""
    sizes = {}
    if not os.path.exists(size_path):
        return sizes
    with open(size_path) as fh:
        for line in fh:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                sizes[parts[1].strip()] = parts[0].strip()
    return sizes


def parse_md5_file(md5_path):
    """Return {filename: md5hash}."""
    md5s = {}
    if not os.path.exists(md5_path):
        return md5s
    with open(md5_path) as fh:
        for line in fh:
            parts = line.strip().split()
            if len(parts) == 2:
                md5s[os.path.basename(parts[1])] = parts[0]
    return md5s


def get_download_link(links_yaml_path, order_id):
    """Extract the download link for order_id from the links YAML."""
    if not links_yaml_path or not os.path.exists(links_yaml_path):
        return ""
    with open(links_yaml_path) as fh:
        data = yaml.safe_load(fh) or {}
    for proj, cfg_data in data.items():
        for cfg, oid_data in cfg_data.items():
            if isinstance(oid_data, dict) and order_id in oid_data:
                entry = oid_data[order_id]
                if isinstance(entry, dict):
                    return entry.get('link', '')
                return entry
    return ""


# ---------------------------------------------------------------------------
# SVG bar chart
# ---------------------------------------------------------------------------

def make_bar_chart_svg(labels, values, title="Reads per Barcode",
                       width=700, bar_height=36, padding=60, label_width=130):
    """Return an inline SVG bar chart string."""
    if not labels:
        return ""

    max_val = max(values) if values else 1
    chart_w = width - label_width - padding * 2
    row_h = bar_height + 8
    svg_h = len(labels) * row_h + padding + 50  # title space

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{svg_h}" '
        f'style="font-family: Arial, sans-serif; background:#fff; border:1px solid #ddd; border-radius:6px;">',
        # title
        f'<text x="{width//2}" y="28" text-anchor="middle" font-size="14" font-weight="bold" fill="#333">{title}</text>',
    ]

    colors = ['#4e79a7', '#f28e2b', '#e15759', '#76b7b2', '#59a14f',
              '#edc948', '#b07aa1', '#ff9da7', '#9c755f', '#bab0ac']

    for i, (label, val) in enumerate(zip(labels, values)):
        y = padding + i * row_h
        bar_w = int(val / max_val * chart_w) if max_val > 0 else 0
        color = colors[i % len(colors)]
        pct = val / max_val * 100

        # background strip
        lines.append(
            f'<rect x="{label_width}" y="{y}" width="{chart_w}" height="{bar_height}" fill="#f5f5f5"/>'
        )
        # bar
        if bar_w > 0:
            lines.append(
                f'<rect x="{label_width}" y="{y}" width="{bar_w}" height="{bar_height}" '
                f'fill="{color}" rx="3"/>'
            )
        # label
        lines.append(
            f'<text x="{label_width - 6}" y="{y + bar_height//2 + 5}" '
            f'text-anchor="end" font-size="12" fill="#333">{label}</text>'
        )
        # value text
        val_str = f'{val:,}'
        lines.append(
            f'<text x="{label_width + bar_w + 5}" y="{y + bar_height//2 + 5}" '
            f'font-size="11" fill="#555">{val_str}</text>'
        )

    lines.append('</svg>')
    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def generate_report(flexbar_dir, report_dir, links_yaml_path, order_id, library_name):
    os.makedirs(report_dir, exist_ok=True)

    log_path  = os.path.join(flexbar_dir, 'flexbarOut.log')
    size_path = os.path.join(flexbar_dir, 'size.txt')
    md5_path  = os.path.join(flexbar_dir, 'md5sum.txt')

    barcodes, per_barcode, filtering = parse_flexbar_log(log_path)
    sizes = parse_size_file(size_path)
    md5s  = parse_md5_file(md5_path)
    download_link = get_download_link(links_yaml_path, order_id)

    # Detect if output is paired-end (any _R2 file present)
    is_paired = any(k.endswith('_R2.fastq.gz') for k in sizes)

    # Ordered barcode list (exclude unassigned for chart, but include in table)
    assigned_names = [n for n in barcodes]
    all_names = assigned_names + ['unassigned'] if 'unassigned' in per_barcode else assigned_names

    # Total assigned reads (R1 only)
    total_assigned = sum(per_barcode.get(n, {}).get('r1_written', 0) for n in assigned_names)
    total_all = sum(per_barcode.get(n, {}).get('r1_written', 0) for n in (all_names if all_names else []))

    # --- Download link HTML ---
    if download_link:
        dl_html = f"""
<table style='width:100%;border-collapse:collapse;margin:5px 0 10px 0;'>
<thead><tr style='background:rgba(0,0,0,0.05);font-weight:bold;font-size:12px;'>
<th style='padding:6px 8px;text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);'>Project</th>
<th style='padding:6px 8px;text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);'>Run</th>
<th style='padding:6px 8px;text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);'>Download Link</th>
</tr></thead>
<tbody>
<tr style='border-bottom:1px solid rgba(0,0,0,0.05);'>
<td style='padding:6px 8px;font-size:13px;'>{order_id}</td>
<td style='padding:6px 8px;font-size:13px;'>{library_name}</td>
<td style='padding:6px 8px;'><a href='{download_link}' style='color:#0066cc;font-size:12px;word-break:break-all;'>{download_link}</a></td>
</tr>
</tbody></table>
"""
    else:
        dl_html = "<p style='color:#cc0000;'>No download link available.</p>"

    # --- Filtering stats HTML ---
    if filtering:
        def fmt(n): return f"{n:,}"
        filt_html = f"""
<table width='100%' cellpadding='8' cellspacing='0' style='border-collapse:collapse;margin-bottom:15px;'>
<thead><tr style='background-color:#f2f2f2;'>
<th style='border:1px solid #ddd;padding:8px;text-align:left;'>Metric</th>
<th style='border:1px solid #ddd;padding:8px;text-align:right;'>Value</th>
</tr></thead>
<tbody>
<tr><td style='border:1px solid #ddd;padding:8px;'>Processed reads</td>
    <td style='border:1px solid #ddd;padding:8px;text-align:right;'>{fmt(filtering['processed'])}</td></tr>
<tr><td style='border:1px solid #ddd;padding:8px;'>Skipped (uncalled bases)</td>
    <td style='border:1px solid #ddd;padding:8px;text-align:right;'>{fmt(filtering['skipped_uncalled'])}</td></tr>
<tr><td style='border:1px solid #ddd;padding:8px;'>Skipped (short reads)</td>
    <td style='border:1px solid #ddd;padding:8px;text-align:right;'>{fmt(filtering['skipped_short'])}</td></tr>
<tr><td style='border:1px solid #ddd;padding:8px;'>Discarded overall</td>
    <td style='border:1px solid #ddd;padding:8px;text-align:right;'>{fmt(filtering['discarded'])}</td></tr>
<tr style='font-weight:bold;background:#e8f4e8;'><td style='border:1px solid #ddd;padding:8px;'>Remaining reads</td>
    <td style='border:1px solid #ddd;padding:8px;text-align:right;'>{fmt(filtering['remaining'])} ({filtering['remaining_pct']}%)</td></tr>
</tbody></table>
"""
    else:
        filt_html = "<p style='color:#888;'>Filtering statistics not available.</p>"

    # --- Demux table HTML ---
    r2_cols = ""
    if is_paired:
        r2_cols = """
<th style='border:1px solid #ddd;padding:8px;text-align:left;'>R2 Size</th>
<th style='border:1px solid #ddd;padding:8px;text-align:left;font-family:monospace;font-size:11px;'>R2 md5sum</th>"""

    demux_html = f"""
<table width='100%' cellpadding='8' cellspacing='0' style='border-collapse:collapse;margin-bottom:15px;'>
<thead><tr style='background-color:#f2f2f2;'>
<th style='border:1px solid #ddd;padding:8px;text-align:left;'>Barcode</th>
<th style='border:1px solid #ddd;padding:8px;text-align:left;'>Sequence</th>
<th style='border:1px solid #ddd;padding:8px;text-align:right;'>R1 Reads</th>
<th style='border:1px solid #ddd;padding:8px;text-align:right;'>% of Assigned</th>
<th style='border:1px solid #ddd;padding:8px;text-align:left;'>R1 Size</th>
<th style='border:1px solid #ddd;padding:8px;text-align:left;font-family:monospace;font-size:11px;'>R1 md5sum</th>
{r2_cols}
</tr></thead>
<tbody>
"""
    for name in all_names:
        stats   = per_barcode.get(name, {})
        r1_reads = stats.get('r1_written', 0)
        seq      = barcodes.get(name, '—')
        pct      = f"{r1_reads / total_assigned * 100:.1f}%" if (total_assigned and name != 'unassigned') else '—'
        r1_fname = f"flexbarOut_barcode_{name}.fastq.gz"
        r1_size  = sizes.get(r1_fname, 'N/A')
        r1_md5   = md5s.get(r1_fname, 'N/A')

        row_style = "background:#fff8f8;" if name == 'unassigned' else ""
        r2_cells = ""
        if is_paired:
            r2_fname = f"flexbarOut_barcode_{name}_R2.fastq.gz"
            r2_size  = sizes.get(r2_fname, 'N/A')
            r2_md5   = md5s.get(r2_fname, 'N/A')
            r2_cells = f"""
<td style='border:1px solid #ddd;padding:8px;{row_style}'>{r2_size}</td>
<td style='border:1px solid #ddd;padding:8px;font-family:monospace;font-size:11px;{row_style}'>{r2_md5}</td>"""

        demux_html += f"""
<tr style='{row_style}'>
<td style='border:1px solid #ddd;padding:8px;font-weight:{"bold" if name=="unassigned" else "normal"};'>{name}</td>
<td style='border:1px solid #ddd;padding:8px;font-family:monospace;font-size:11px;'>{seq}</td>
<td style='border:1px solid #ddd;padding:8px;text-align:right;'>{r1_reads:,}</td>
<td style='border:1px solid #ddd;padding:8px;text-align:right;'>{pct}</td>
<td style='border:1px solid #ddd;padding:8px;'>{r1_size}</td>
<td style='border:1px solid #ddd;padding:8px;font-family:monospace;font-size:11px;'>{r1_md5}</td>
{r2_cells}
</tr>
"""
    demux_html += "</tbody></table>"

    # --- Bar chart (assigned barcodes only) ---
    chart_labels = assigned_names
    chart_values = [per_barcode.get(n, {}).get('r1_written', 0) for n in chart_labels]
    bar_chart_svg = make_bar_chart_svg(chart_labels, chart_values,
                                       title="Assigned Reads per Barcode")

    # --- Full HTML ---
    html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Report for order {order_id} ({library_name})</title>
</head>
<body style="font-family:'Public Sans','Work Sans',Arial,sans-serif;margin:0;padding:20px;background-color:#f5f7fb;color:#1c2b36;">
<table width="100%" cellpadding="0" cellspacing="0" style="max-width:900px;margin:0 auto;">
<tr><td>

<!-- Introduction -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
<tr><td style="padding:18px;background:#fff;border-radius:14px;box-shadow:0 14px 30px rgba(0,34,68,0.12);border:1px solid rgba(0,50,98,0.06);">
<p style="margin:0 0 10px 0;line-height:1.6;"><strong>Dear GRTHub User,</strong></p>
<p style="margin:0 0 10px 0;line-height:1.6;">The sequencing data for the samples you submitted to the GRTHub has been processed and is now available for downloading in FastQ file format.</p>
<p style="margin:0 0 10px 0;line-height:1.6;">Your fastq files will remain available for downloading during a period of <strong>1 month only</strong>. Please download your files immediately and verify their integrity using the provided md5sum values as soon as possible, and before the end of this period.</p>
<p style="margin:0;line-height:1.6;"><strong>A file containing the md5sum for your FastQ files is included in this report. Instructions for downloading the files are attached.</strong></p>
</td></tr></table>

<!-- Download Links -->
<div style="margin-bottom:24px;">
<h2 style="margin:0 0 12px 0;font-size:20px;letter-spacing:-0.2px;color:#333;">Your Download Links</h2>
<div style="background:#fff9ec;border:1px solid rgba(245,183,0,0.5);color:#7a5800;padding:14px 16px;border-radius:14px;margin-bottom:16px;box-shadow:0 8px 18px rgba(245,183,0,0.12);">
<strong style="display:block;margin-bottom:8px;">📋 Direct Links:</strong>
{dl_html}
<div style="margin-top:10px;padding-top:10px;border-top:1px solid rgba(0,0,0,0.1);font-size:13px;">
<strong>To download entire folder as zip:</strong> Append <code style="background:rgba(0,0,0,0.1);padding:2px 4px;border-radius:3px;">/download</code> to the link above.
</div>
</div>
</div>

<!-- Demultiplexing Summary -->
<h2 style="margin:32px 0 12px 0;font-size:20px;letter-spacing:-0.2px;color:#333;">Demultiplexing Summary</h2>
<p style="margin:0 0 14px 0;color:#66788a;">Reads were demultiplexed from Undetermined reads using flexbar inline barcode matching.</p>

<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;border:1px solid #ccc;">
<tr><td style="padding:15px;">
<h3 style="color:#333;font-size:16px;margin:0 0 12px 0;">Filtering Statistics</h3>
{filt_html}
<h3 style="color:#333;font-size:16px;margin:20px 0 12px 0;">Per-Barcode Read Counts</h3>
{demux_html}
</td></tr></table>

<!-- Bar Chart -->
<h2 style="margin:32px 0 12px 0;font-size:20px;letter-spacing:-0.2px;color:#333;">Reads per Barcode</h2>
<div style="margin-bottom:24px;background:#fff;padding:18px;border-radius:14px;box-shadow:0 4px 12px rgba(0,34,68,0.08);border:1px solid rgba(0,50,98,0.06);">
{bar_chart_svg}
</div>

<!-- Footer -->
<div style="margin:40px 0 0 0;padding:18px 0 0 0;border-top:1px solid rgba(0,50,98,0.08);color:#66788a;font-size:13px;">
<p style="margin:0 0 6px 0;"><strong>Questions?</strong> Contact the UCI Genomics Research and Technology Hub</p>
<p style="margin:0;">Email: <a href="mailto:mloakes@uci.edu" style="color:#1f6feb;text-decoration:none;">mloakes@uci.edu</a> | Phone: (949) 824-5327 | Fax: (949) 824-2688</p>
<p style="margin:6px 0 0 0;"><a href="https://genomics.uci.edu/" style="color:#1f6feb;text-decoration:none;">Visit genomics.uci.edu</a></p>
</div>

</td></tr>
</table>
</body>
</html>
"""
    with open(os.path.join(report_dir, 'index.html'), 'w') as fh:
        fh.write(html)
    print(f"Report written: {os.path.join(report_dir, 'index.html')}")


if __name__ == "__main__":
    if len(sys.argv) < 6:
        print(__doc__)
        sys.exit(1)

    generate_report(
        flexbar_dir   = sys.argv[1],
        report_dir    = sys.argv[2],
        links_yaml_path = sys.argv[3],
        order_id      = sys.argv[4],
        library_name  = sys.argv[5],
    )

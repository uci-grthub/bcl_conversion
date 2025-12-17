import os
import sys
import glob
import shutil

def generate_report(project, output_base_dir, fastp_plots_base_dir, report_dir):
    os.makedirs(report_dir, exist_ok=True)
    
    html_content = f"<html><head><title>Report for {project}</title>"
    html_content += """
    <style>
        body { font-family: sans-serif; margin: 20px; }
        h1, h2, h3 { color: #333; }
        img { max-width: 100%; border: 1px solid #ddd; }
        .sample-section { border: 1px solid #ccc; padding: 15px; margin-bottom: 20px; border-radius: 5px; }
        .basic-info { background-color: #f9f9f9; padding: 10px; border: 1px solid #eee; overflow-x: auto; margin-bottom: 10px; }
        .plots-container { display: flex; flex-wrap: wrap; gap: 20px; }
        .plot-pair { display: flex; flex-direction: column; margin-bottom: 10px; width: 100%; }
        .lane-header { font-weight: bold; margin-top: 10px; }
        .plots-row { display: flex; gap: 10px; width: 100%; }
        .plot-img { flex: 1; min-width: 0; }
    </style>
    </head><body>
    """
    html_content += f"<h1>Report for Project: {project}</h1>"
    
    project_output_dir = os.path.join(output_base_dir, project)
    
    # Collect all sample IDs
    samples = set()
    
    # From SampleBasicInfo
    if os.path.exists(project_output_dir):
        for f in os.listdir(project_output_dir):
            if f.endswith("-SampleBasicInfo.txt"):
                samples.add(f[:-20]) # Remove -SampleBasicInfo.txt
    
    # From Plots
    lane_dirs = glob.glob(os.path.join(fastp_plots_base_dir, "lane*"))
    for lane_dir in lane_dirs:
        project_lane_dir = os.path.join(lane_dir, project)
        if os.path.exists(project_lane_dir):
            for f in os.listdir(project_lane_dir):
                if f.endswith("-mean_phred.png"):
                    samples.add(f[:-15])
                elif f.endswith("-base_comp.png"):
                    samples.add(f[:-14])

    sorted_samples = sorted(list(samples))
    
    for sample in sorted_samples:
        html_content += f"<div class='sample-section'><h2>Sample: {sample}</h2>"
        
        # 1. Basic Info
        info_file = f"{sample}-SampleBasicInfo.txt"
        src_info = os.path.join(project_output_dir, info_file)
        if os.path.exists(src_info):
            dst_info = os.path.join(report_dir, info_file)
            shutil.copy2(src_info, dst_info)
            try:
                with open(src_info, 'r') as f:
                    content = f.read()
                html_content += f"<div class='basic-info'><h3>Basic Info</h3><pre>{content}</pre></div>"
            except Exception as e:
                html_content += f"<p>Error reading info: {e}</p>"
        
        # 2. Plots (per lane)
        html_content += "<div class='plots-container'>"
        for lane_dir in sorted(lane_dirs):
            lane_name = os.path.basename(lane_dir)
            project_lane_dir = os.path.join(lane_dir, project)
            
            mean_plot = f"{sample}-mean_phred.png"
            base_plot = f"{sample}-base_comp.png"
            
            src_mean = os.path.join(project_lane_dir, mean_plot)
            src_base = os.path.join(project_lane_dir, base_plot)
            
            if os.path.exists(src_mean) or os.path.exists(src_base):
                html_content += f"<div class='plot-pair'><div class='lane-header'>{lane_name}</div><div class='plots-row'>"
                
                if os.path.exists(src_mean):
                    dst_mean = f"{lane_name}_{mean_plot}"
                    shutil.copy2(src_mean, os.path.join(report_dir, dst_mean))
                    html_content += f"<div class='plot-img'><img src='{dst_mean}' title='Mean Phred'></div>"
                
                if os.path.exists(src_base):
                    dst_base = f"{lane_name}_{base_plot}"
                    shutil.copy2(src_base, os.path.join(report_dir, dst_base))
                    html_content += f"<div class='plot-img'><img src='{dst_base}' title='Base Composition'></div>"
                
                html_content += "</div></div>"
        
        html_content += "</div></div>" # End plots-container and sample-section

    html_content += "</body></html>"
    
    with open(os.path.join(report_dir, "index.html"), "w") as f:
        f.write(html_content)

if __name__ == "__main__":
    # Usage: python generate_report.py <project> <output_base> <fastp_plots_base> <report_dir>
    if len(sys.argv) < 5:
        print("Usage: python generate_report.py <project> <output_base> <fastp_plots_base> <report_dir>")
        sys.exit(1)
        
    project = sys.argv[1]
    output_base = sys.argv[2]
    fastp_plots_base = sys.argv[3]
    report_dir = sys.argv[4]
    generate_report(project, output_base, fastp_plots_base, report_dir)

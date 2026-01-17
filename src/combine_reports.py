#!/usr/bin/env python3
"""
Combine sequencing reports according to report_combinations.yaml configuration.

This script:
1. Reads the report combinations config
2. Combines multiple project reports into single HTML documents
3. Aggregates md5sum files
4. Optionally sends emails with the combined reports
"""

import os
import sys
import yaml
import shutil
import argparse
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Tuple
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ReportCombiner:
    """Combines sequencing reports according to configuration."""
    
    def __init__(self, config_path: str, reports_dir: str = "Reports", output_dir: str = "Reports"):
        """
        Initialize the report combiner.
        
        Args:
            config_path: Path to report_combinations.yaml
            reports_dir: Path to Reports directory
            output_dir: Path for combined output reports
        """
        self.config_path = config_path
        self.reports_dir = reports_dir
        self.output_dir = output_dir
        self.config = self._load_config()
        
    def _load_config(self) -> Dict:
        """Load YAML configuration file."""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            logger.error(f"Failed to load config file {self.config_path}: {e}")
            sys.exit(1)
    
    def _get_project_report_path(self, project: str, lane: int) -> str:
        """Get the path to a project's report for a given lane."""
        return os.path.join(self.reports_dir, project, f"lane{lane}")
    
    def _project_lane_exists(self, project: str, lane: int) -> bool:
        """Check if a project report exists for a given lane."""
        path = self._get_project_report_path(project, lane)
        return os.path.exists(os.path.join(path, "index.html"))
    
    def _read_html_file(self, filepath: str) -> str:
        """Read HTML file content."""
        try:
            with open(filepath, 'r') as f:
                return f.read()
        except Exception as e:
            logger.warning(f"Failed to read {filepath}: {e}")
            return ""
    
    def _read_md5_file(self, filepath: str) -> List[str]:
        """Read md5sums file and return lines."""
        try:
            with open(filepath, 'r') as f:
                return f.readlines()
        except Exception as e:
            logger.warning(f"Failed to read {filepath}: {e}")
            return []
    
    def _extract_html_body(self, html: str) -> str:
        """Extract body content from HTML, removing html/body tags."""
        if not html:
            return ""
        
        # Try to extract content between <body> tags
        start = html.lower().find('<body')
        if start != -1:
            start = html.find('>', start) + 1
            end = html.lower().find('</body>')
            if end != -1:
                return html[start:end].strip()
        
        # If no body tags, return the whole HTML
        return html
    
    def _generate_combined_html(self, reports_data: List[Tuple[str, str, int, str]]) -> str:
        """
        Generate a combined HTML report from multiple project reports.
        
        Args:
            reports_data: List of (project_name, project_display, lane, html_content) tuples
        
        Returns:
            Combined HTML content
        """
        html_parts = [
            """<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Combined Sequencing Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background-color: #2c3e50;
            color: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 30px;
        }
        .header h1 {
            margin: 0;
            font-size: 28px;
        }
        .header p {
            margin: 5px 0 0 0;
            font-size: 14px;
            opacity: 0.9;
        }
        .project-section {
            background-color: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            margin-bottom: 30px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .project-title {
            background-color: #3498db;
            color: white;
            padding: 15px;
            margin: -20px -20px 20px -20px;
            border-radius: 5px 5px 0 0;
            font-size: 18px;
            font-weight: bold;
        }
        .project-meta {
            font-size: 12px;
            color: #666;
            margin-bottom: 15px;
            padding: 10px;
            background-color: #ecf0f1;
            border-radius: 3px;
        }
        .project-content {
            margin-top: 15px;
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Combined Sequencing Report</h1>
        <p>Generated on: """ + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + """</p>
    </div>
"""
        ]
        
        # Add each project's report
        for project_name, project_display, lane, content in reports_data:
            html_parts.append(f"""
    <div class="project-section">
        <div class="project-title">{project_display} (Lane {lane})</div>
        <div class="project-meta">
            <strong>Project:</strong> {project_name}<br>
            <strong>Lane:</strong> {lane}
        </div>
        <div class="project-content">
            {content}
        </div>
    </div>
""")
        
        html_parts.append("""
    <div class="footer">
        <p>This is a combined report containing multiple sequencing projects.</p>
    </div>
</body>
</html>
""")
        
        return "".join(html_parts)
    
    def _combine_md5sums(self, md5_data: List[Tuple[str, str, int, List[str]]]) -> str:
        """
        Combine md5sum files with project/lane headers.
        
        Args:
            md5_data: List of (project_name, project_display, lane, md5_lines) tuples
        
        Returns:
            Combined md5sums content
        """
        combined = []
        
        for project_name, project_display, lane, lines in md5_data:
            combined.append(f"# {project_display} - Lane {lane}\n")
            combined.extend(lines)
            combined.append("\n")
        
        return "".join(combined)
    
    def process_combination(self, combination: Dict) -> bool:
        """
        Process a single report combination.
        
        Args:
            combination: Report combination configuration dictionary
        
        Returns:
            True if successful, False otherwise
        """
        name = combination.get('name', 'Unknown')
        logger.info(f"Processing: {name}")
        
        # Extract lane and project information
        lanes_config = combination.get('lanes', [])
        projects = combination.get('projects', [])
        
        if not lanes_config or not projects:
            logger.warning(f"Skipping {name}: Missing lanes or projects configuration")
            return False
        
        # Collect reports to combine
        reports_data = []
        md5_data = []
        
        for lane_config in lanes_config:
            lane = lane_config.get('lane')
            if not lane:
                continue
            
            for project in projects:
                # Check if report exists
                report_path = self._get_project_report_path(project, lane)
                html_file = os.path.join(report_path, "index.html")
                md5_file = os.path.join(report_path, "md5sums.txt")
                
                if not os.path.exists(html_file):
                    logger.warning(f"Report not found: {html_file}")
                    continue
                
                # Read HTML content
                html_content = self._read_html_file(html_file)
                body_content = self._extract_html_body(html_content)
                
                # Create display name
                project_display = project
                reports_data.append((project, project_display, lane, body_content))
                
                # Read md5sums
                if os.path.exists(md5_file):
                    md5_lines = self._read_md5_file(md5_file)
                    md5_data.append((project, project_display, lane, md5_lines))
        
        if not reports_data:
            logger.warning(f"No reports found for combination: {name}")
            return False
        
        # Create output directory
        # Use the first project name as base for output directory
        first_project = projects[0] if projects else "combined"
        output_subdir = os.path.join(self.output_dir, first_project, f"lane{lanes_config[0]['lane']}")
        
        # For combined reports, create a special naming
        if len(reports_data) > 1:
            # Create a combined directory structure
            combined_name = f"combined_{'_'.join([p for p in projects])}"
            output_subdir = os.path.join(self.output_dir, combined_name, 
                                        f"lane{'_'.join([str(lc['lane']) for lc in lanes_config])}")
        
        os.makedirs(output_subdir, exist_ok=True)
        logger.info(f"Output directory: {output_subdir}")
        
        # Generate combined HTML
        combined_html = self._generate_combined_html(reports_data)
        html_output_path = os.path.join(output_subdir, "index.html")
        
        try:
            with open(html_output_path, 'w') as f:
                f.write(combined_html)
            logger.info(f"Created combined HTML: {html_output_path}")
        except Exception as e:
            logger.error(f"Failed to write HTML file: {e}")
            return False
        
        # Generate combined md5sums
        if md5_data:
            combined_md5 = self._combine_md5sums(md5_data)
            md5_output_path = os.path.join(output_subdir, "md5sums.txt")
            
            try:
                with open(md5_output_path, 'w') as f:
                    f.write(combined_md5)
                logger.info(f"Created combined md5sums: {md5_output_path}")
            except Exception as e:
                logger.error(f"Failed to write md5sums file: {e}")
                return False
        
        logger.info(f"Successfully processed: {name}")
        return True
    
    def run(self) -> None:
        """Process all report combinations."""
        combinations = self.config.get('report_combinations', [])
        
        if not combinations:
            logger.warning("No report combinations found in config")
            return
        
        logger.info(f"Processing {len(combinations)} report combinations...")
        
        successful = 0
        failed = 0
        
        for combination in combinations:
            try:
                if self.process_combination(combination):
                    successful += 1
                else:
                    failed += 1
            except Exception as e:
                logger.error(f"Error processing combination {combination.get('name')}: {e}")
                failed += 1
        
        logger.info(f"Completed: {successful} successful, {failed} failed")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Combine sequencing reports according to configuration"
    )
    parser.add_argument(
        '--config',
        default='metadata/report_combinations.yaml',
        help='Path to report_combinations.yaml file'
    )
    parser.add_argument(
        '--reports-dir',
        default='Reports',
        help='Path to Reports directory'
    )
    parser.add_argument(
        '--output-dir',
        default='Reports',
        help='Output directory for combined reports'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Verify config file exists
    if not os.path.exists(args.config):
        logger.error(f"Config file not found: {args.config}")
        sys.exit(1)
    
    # Verify reports directory exists
    if not os.path.exists(args.reports_dir):
        logger.error(f"Reports directory not found: {args.reports_dir}")
        sys.exit(1)
    
    # Create output directory if needed
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Run the combiner
    combiner = ReportCombiner(args.config, args.reports_dir, args.output_dir)
    combiner.run()


if __name__ == '__main__':
    main()

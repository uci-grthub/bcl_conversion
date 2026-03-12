#!/usr/bin/env python
"""
Standalone validation script for metadata files.
Imports the shared validation function from src/metadata_validation.py
"""
import sys
import os
import argparse
import yaml

# Add src directory to path so we can import the shared validation module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from metadata_validation import validate_metadata_and_write_report

# Main execution
if __name__ == "__main__":
    # Load default metadata path from config file
    config_file = "snakemake_config_project.yaml"
    default_metadata = None
    
    if os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
                default_metadata = config.get('metadata')
        except Exception as e:
            print(f"Warning: Could not read config file {config_file}: {e}")
    
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Validate metadata Excel file')
    parser.add_argument(
        'metadata_file',
        nargs='?',
        default=default_metadata,
        help=f'Path to metadata Excel file (default: {default_metadata})'
    )
    args = parser.parse_args()
    
    metadata_file = args.metadata_file
    
    if not metadata_file:
        parser.error('metadata_file is required (provide as argument or set in config file)')
    
    output_xlsx = os.path.join('metadata', f"metadata_validation_{os.path.basename(metadata_file)}.xlsx")
    
    print(f"Starting metadata validation...")
    print(f"Input:  {metadata_file}")
    print(f"Output: {output_xlsx}")
    print("=" * 80)
    
    try:
        validate_metadata_and_write_report(metadata_file, out_xlsx=output_xlsx)
        print("=" * 80)
        print("✓ Validation completed successfully!")
        print(f"Validation report saved to: {output_xlsx}")
    except Exception as e:
        print("=" * 80)
        print(f"✗ Error during validation: {e}")
        import traceback
        traceback.print_exc()
        exit(1)

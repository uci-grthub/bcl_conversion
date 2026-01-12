import os
import sys
import pandas as pd
import glob

def is_parse_or_10x(project_name: str) -> bool:
    """Check if project uses Illumina default naming.
    
    Returns True for: 10x (including VisiumHD, 5'V2, 3'V3, ATAC, etc.), Parse, BD.
    These platforms require Illumina default naming for downstream tools.
    """
    try:
        p = (project_name or "").lower()
    except Exception:
        p = ""
    # Respect FASTQ_RENAME.md: 10x (all products), Parse, and BD keep Illumina default naming
    return ("10x" in p) or ("parse" in p) or ("bd" in p)

def rename_fastqs(config_id, output_dir, map_file):
    if not os.path.exists(map_file):
        print(f"Map file {map_file} not found.")
        return

    try:
        df = pd.read_csv(map_file)
    except Exception as e:
        print(f"Error reading map file: {e}")
        return

    print(f"Renaming files in {output_dir} using {map_file}")

    for i, row in df.iterrows():
        sample_name = str(row['Sample_Name']).strip()
        project = str(row['Sample_Project']).strip()
        try:
            lane = int(row['Lane'])
        except:
            lane = 0
            
        try:
            # Convert to float first to handle "1.0" or 1.0, then int to remove decimal
            group = str(int(float(row['Group'])))
        except:
            group = str(row['Group']).strip()
            if group.lower() == 'nan': group = "Undetermined"
        
        run = str(row['Run']).strip()
        
        index1 = str(row['index']).strip()
        if index1.lower() == 'nan': index1 = ""
        
        index2 = str(row['index2']).strip()
        if index2.lower() == 'nan': index2 = ""
        
        if index2:
            barcode = f"{index1}-{index2}"
        else:
            barcode = index1
            
        position = str(row.get('Position', f"P{i+1:03d}")).strip()
            
        # Construct old filename pattern
        # {Sample_Name}_S{i+1}_L{Lane:03d}_R{Read}_001.fastq.gz
        s_num = i + 1
        
        # Determine project subdirectory
        project_dir = output_dir
        if project and project.lower() != 'nan':
            project_dir = os.path.join(output_dir, project)
            
        if not os.path.exists(project_dir):
            # It might be that bcl-convert didn't create project subdir if sample sheet didn't specify it correctly?
            # But we set --bcl-sampleproject-subdirectories true
            # If project is empty, it goes to root.
            if not project or project.lower() == 'nan':
                project_dir = output_dir
            else:
                print(f"Project directory {project_dir} not found.")
                continue
            
        # For 10x, Parse, and BD projects: ensure files are in Illumina default naming
        # Check if files are already in Illumina format, or if they're in stem format and need reverse-renaming
        if is_parse_or_10x(project):
            for read_type in ['R1', 'R2', 'I1', 'I2']:
                illumina_name = f"{sample_name}_S{s_num}_L{lane:03d}_{read_type}_001.fastq.gz"
                illumina_path = os.path.join(project_dir, illumina_name)
                stem_name = f"{run}-L{lane}-G{group}-{position}-{barcode}-{read_type}.fastq.gz"
                stem_path = os.path.join(project_dir, stem_name)
                
                # If already in Illumina format, all good
                if os.path.exists(illumina_path):
                    continue
                
                # If in stem format, reverse-rename to Illumina
                if os.path.exists(stem_path):
                    print(f"Reverse-renaming 10x/Parse/BD from stem to Illumina: {stem_name} -> {illumina_name}")
                    try:
                        if os.path.exists(illumina_path):
                            os.remove(illumina_path)
                        os.rename(stem_path, illumina_path)
                    except Exception as e:
                        print(f"Error reverse-renaming {stem_path}: {e}")
                    continue
                
                # If neither exists, that's OK (R2/I1/I2 may not exist for single-end or non-indexed)
                if read_type == 'R1':
                    print(f"Missing FASTQ for 10x/Parse/BD: {illumina_path}")
            continue

        # Default: rename to custom xR0<run>-L<lane>-G<group>-P<position>-<barcode>-R<read>.fastq.gz
        for read_type in ['R1', 'R2', 'I1', 'I2']:
            old_name = f"{sample_name}_S{s_num}_L{lane:03d}_{read_type}_001.fastq.gz"
            old_path = os.path.join(project_dir, old_name)

            new_name = f"{run}-L{lane}-G{group}-{position}-{barcode}-{read_type}.fastq.gz"
            new_path = os.path.join(project_dir, new_name)

            if not os.path.exists(old_path):
                # Check if already renamed
                if os.path.exists(new_path):
                    continue

                # If R2/I1/I2 doesn't exist, skip
                if read_type in ['R2', 'I1', 'I2']:
                    continue
                print(f"File not found: {old_path}")
                continue

            print(f"Renaming {old_name} -> {new_name}")
            try:
                if os.path.exists(new_path):
                    os.remove(new_path)
                os.rename(old_path, new_path)
            except Exception as e:
                print(f"Error renaming {old_path}: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python rename_fastqs.py <config_id> <output_dir> <map_file>")
        sys.exit(1)
        
    config_id = sys.argv[1]
    output_dir = sys.argv[2]
    map_file = sys.argv[3]
    
    rename_fastqs(config_id, output_dir, map_file)

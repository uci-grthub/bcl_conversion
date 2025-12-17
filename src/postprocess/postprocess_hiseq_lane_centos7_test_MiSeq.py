#!/usr/bin/env python3
import sys
import os
import subprocess
import re

def main():
    if len(sys.argv) != 5:
        print("\n  USAGE : ./postprocess_hiseq_lane_centos7_test_MiSeq.py sample_sheet num_reads lane_number library_name\n")
        sys.exit(1)

    sample_sheet = sys.argv[1]
    try:
        num_reads = int(sys.argv[2])
        lane = int(sys.argv[3])
    except ValueError:
        print("num_reads and lane_number must be integers")
        sys.exit(1)
    name = sys.argv[4]

    if not os.path.exists(sample_sheet):
        print("Cannot find sample sheet")
        sys.exit(1)
    
    if num_reads not in [1, 2]:
        print("Num reads must be 1 or 2")
        sys.exit(1)
        
    if not (1 <= lane <= 8):
        print("Lane must between 1 and 8")
        sys.exit(1)

    # Paths to analysis scripts
    # Assuming they are in the parent directory of this script's directory (Tools/)
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    process_single = os.path.join(base_dir, "analyze", "analyze_single_reads.py")
    process_paired = os.path.join(base_dir, "analyze", "analyze_paired_reads.py")
    
    # Load Sample Information
    is_barcoded = False
    barcodes = []
    prefixes = []
    generic = []
    
    try:
        with open(sample_sheet, 'r') as f:
            lines = f.readlines()
            
        if len(lines) < 2:
            print("Incorrect file header (Too short)")
            sys.exit(1)
            
        if "Data" not in lines[0]:
            print("Incorrect file header (Line 1)")
            sys.exit(1)
        if "Project,Lane,SampleID" not in lines[1]:
            print("Incorrect file header (Line 2)")
            sys.exit(1)
            
        generic_sample_id = 1
        
        for line in lines[2:]:
            line = line.strip()
            if not line: continue
            d = line.split(',')
            
            # d indices: 0=Project, 1=Lane, 2=SampleID, 3=?, 4=Barcode1, 5=Barcode2
            if len(d) > 1 and d[1].isdigit() and int(d[1]) == lane:
                if len(d) <= 4 or d[4] == "": # Not barcoded?
                    prefix = d[2]
                    if is_barcoded or len(barcodes) > 0:
                        print("Inconsistent sample sheet")
                        sys.exit(1)
                    
                    if not re.match(f"^R[0-9]{{3}}-L{lane}$", prefix):
                        print("Inconsistent sample prefix.")
                        sys.exit(1)
                    prefixes.append(prefix)
                else:
                    is_barcoded = True
                    barcode = d[4]
                    if len(d) > 5 and d[5] != "":
                        barcode = f"{d[4]}-{d[5]}"
                    
                    barcodes.append(barcode)
                    prefixes.append(d[2])
                    generic.append(str(generic_sample_id))
            
            generic_sample_id += 1
            
    except Exception as e:
        print(f"Error reading sample sheet: {e}")
        sys.exit(1)

    if not is_barcoded:
        print("Samples not barcoded : write corresponding code")
        sys.exit(1)
    else:
        print(f"\n  Found {len(barcodes)} Barcodes For Lane {lane} ({name})\n")
        
        for i in range(len(barcodes)):
            barcode = barcodes[i]
            prefix = prefixes[i]
            genid = generic[i]
            
            print(f"  Processing Library \"{name}\" - Barcode {barcode} ({prefix})...")
            
            file_in_R1 = f"{prefix}_S{genid}_L00{lane}_R1_001.fastq"
            file_in_R2 = f"{prefix}_S{genid}_L00{lane}_R2_001.fastq"
            
            if not os.path.exists(file_in_R1):
                print(f"Cannot find fastq file {file_in_R1}")
                sys.exit(1)
            if num_reads == 2 and not os.path.exists(file_in_R2):
                print(f"Cannot find fastq file {file_in_R2}")
                sys.exit(1)
                
            if num_reads == 1:
                file_out = f"{prefix}-{barcode}-Sequences.txt"
                subprocess.run(["mv", file_in_R1, file_out], check=True)
                
                cmd = [sys.executable, process_single, file_out, f"{prefix}-{barcode}", name]
                subprocess.run(cmd, check=True)
                
                subprocess.run(f"chmod 770 {prefix}*", shell=True, check=True)
                subprocess.run(f"gzip -f {file_out}", shell=True, check=True)
                subprocess.run(f"chmod 770 {file_out}.gz", shell=True, check=True)
                subprocess.run(f"md5sum {file_out}.gz >> md5sum_lane{lane}.txt", shell=True, check=True)
                
            elif num_reads == 2:
                file_out_R1 = f"{prefix}-{barcode}-READ1-Sequences.txt"
                file_out_R2 = f"{prefix}-{barcode}-READ2-Sequences.txt"
                
                subprocess.run(["mv", file_in_R1, file_out_R1], check=True)
                subprocess.run(["mv", file_in_R2, file_out_R2], check=True)
                
                print(f"  Processing check Library \"{name}\" - Barcode {prefix} -{barcode} ...")
                
                cmd = [sys.executable, process_paired, file_out_R1, file_out_R2, f"{prefix}-{barcode}", name]
                subprocess.run(cmd, check=True)
                
                subprocess.run(f"chmod 770 {prefix}*", shell=True, check=True)
                subprocess.run(f"gzip -f {file_out_R1}", shell=True, check=True)
                subprocess.run(f"chmod 770 {file_out_R1}.gz", shell=True, check=True)
                subprocess.run(f"gzip -f {file_out_R2}", shell=True, check=True)
                subprocess.run(f"chmod 770 {file_out_R2}.gz", shell=True, check=True)
                
                subprocess.run(f"md5sum {file_out_R1}.gz >> md5sum_lane{lane}.txt", shell=True, check=True)
                subprocess.run(f"md5sum {file_out_R2}.gz >> md5sum_lane{lane}.txt", shell=True, check=True)

        # Trash / Undetermined
        if len(prefixes) > 0:
            d = prefixes[0].split('-')
            if len(d) >= 2:
                prefix = f"{d[0]}-{d[1]}"
                
                if not re.match(f"^(4R|mR|R)[0-9]{{3}}-L{lane}$", prefix):
                    print("Cannot process trash")
                    sys.exit(1)
                    
                prefix = f"{prefix}-PrNotRecog"
                print(f"  Processing Library \"{name}\" - Barcode Not Recognized ({prefix})...")
                
                file_in_R1 = f"Undetermined_S0_L00{lane}_R1_001.fastq"
                file_in_R2 = f"Undetermined_S0_L00{lane}_R2_001.fastq"
                
                if not os.path.exists(file_in_R1):
                    print(f"Cannot find fastq file {file_in_R1}")
                    sys.exit(1)
                if num_reads == 2 and not os.path.exists(file_in_R2):
                    print(f"Cannot find fastq file {file_in_R2}")
                    sys.exit(1)
                    
                if num_reads == 1:
                    file_out = f"{prefix}-Sequences.txt"
                    subprocess.run(["mv", file_in_R1, file_out], check=True)
                    
                    cmd = [sys.executable, process_single, file_out, prefix, name]
                    subprocess.run(cmd, check=True)
                    
                    subprocess.run(f"chmod 770 {prefix}*", shell=True, check=True)
                    subprocess.run(f"gzip -f {file_out}", shell=True, check=True)
                    subprocess.run(f"chmod 770 {file_out}.gz", shell=True, check=True)
                    subprocess.run(f"md5sum {file_out}.gz >> md5sum_lane{lane}.txt", shell=True, check=True)
                    
                elif num_reads == 2:
                    file_out_R1 = f"{prefix}-READ1-Sequences.txt"
                    file_out_R2 = f"{prefix}-READ2-Sequences.txt"
                    
                    subprocess.run(["mv", file_in_R1, file_out_R1], check=True)
                    subprocess.run(["mv", file_in_R2, file_out_R2], check=True)
                    
                    cmd = [sys.executable, process_paired, file_out_R1, file_out_R2, prefix, name]
                    subprocess.run(cmd, check=True)
                    
                    subprocess.run(f"chmod 770 {prefix}*", shell=True, check=True)
                    subprocess.run(f"gzip -f {file_out_R1}", shell=True, check=True)
                    subprocess.run(f"chmod 770 {file_out_R1}.gz", shell=True, check=True)
                    subprocess.run(f"gzip -f {file_out_R2}", shell=True, check=True)
                    subprocess.run(f"chmod 770 {file_out_R2}.gz", shell=True, check=True)
                    
                    subprocess.run(f"md5sum {file_out_R1}.gz >> md5sum_lane{lane}.txt", shell=True, check=True)
                    subprocess.run(f"md5sum {file_out_R2}.gz >> md5sum_lane{lane}.txt", shell=True, check=True)

if __name__ == "__main__":
    main()

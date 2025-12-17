#!/usr/bin/env python3
import sys
import os
import subprocess
import shutil

def main():
    if len(sys.argv) < 5 or len(sys.argv) > 6:
        print("\n  USAGE : ./postprocess_hiseq_lane_centos7_test_gzip.py sample_sheet num_reads lane_number library_name [optional start S number, blank is S1]\n")
        sys.exit(1)
        
    start_s_id = 1
    if len(sys.argv) == 6:
        print(f"Using Start S number of {sys.argv[5]}")
        start_s_id = int(sys.argv[5])
        
    sample_sheet = sys.argv[1]
    num_reads = int(sys.argv[2])
    lane = int(sys.argv[3])
    name = sys.argv[4]
    
    if not os.path.isfile(sample_sheet):
        print("Cannot find sample sheet")
        sys.exit(1)
        
    if num_reads not in [1, 2]:
        print("Num reads must be 1 or 2")
        sys.exit(1)
        
    if not (1 <= lane <= 8):
        print("Lane must between 1 and 8")
        sys.exit(1)
        
    print(f"Start id S number ={start_s_id}")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # Assuming analyze scripts are in the same directory and unified
    process_single = os.path.join(script_dir, "analyze_single_reads.py")
    process_paired = os.path.join(script_dir, "analyze_paired_reads.py")
    
    # Load Sample Information
    is_barcoded = 0
    num_barcodes = 0
    barcodes = []
    prefixes = []
    generic = []
    
    try:
        with open(sample_sheet, 'r') as f:
            lines = f.readlines()
            if "Data" not in lines[0]:
                print("Incorrect file header")
                sys.exit(1)
            if "Project,Lane,SampleID" not in lines[1]:
                print("Incorrect file header")
                sys.exit(1)
                
            generic_sample_id = 1
            for l in lines[2:]:
                l = l.strip()
                if not l: continue
                d = l.split(",")
                if int(d[1]) == lane:
                    if d[4] == "":
                        prefix = d[2]
                        if is_barcoded != 0 or num_barcodes != 0:
                            print("Inconsistent sample sheet")
                            sys.exit(1)
                        # Regex check for prefix: R[0-9]{3}-L$lane
                        prefixes.append(prefix)
                    else:
                        is_barcoded = 1
                        num_barcodes += 1
                        if d[5] == "":
                            barcodes.append(d[4])
                        else:
                            barcodes.append(f"{d[4]}-{d[5]}")
                        prefixes.append(d[2])
                        generic.append(str(generic_sample_id))
                    print(f"in check {d[2]}")
                generic_sample_id += 1
    except Exception as e:
        print(f"Error reading sample sheet: {e}")
        sys.exit(1)

    if is_barcoded == 0:
        print("Samples not barcoded : write corresponding code")
        sys.exit(1)
    else:
        print(f"\n  Found {num_barcodes} Barcodes For Lane {lane} ({name})\n")
        
        for i in range(num_barcodes):
            barcode = barcodes[i]
            prefix = prefixes[i]
            genid = int(generic[i]) + start_s_id - 1
            
            print(f"  Processing Library \"{name}\" - Barcode {barcode} ({prefix})... genid={genid}")
            
            file_in_R1 = f"{prefix}_S{genid}_L00{lane}_R1_001.fastq.gz"
            file_in_R2 = f"{prefix}_S{genid}_L00{lane}_R2_001.fastq.gz"
            
            if not os.path.isfile(file_in_R1):
                print(f"Cannot find fastq file 1 {file_in_R1}")
                sys.exit(1)
            if num_reads == 2 and not os.path.isfile(file_in_R2):
                print("Cannot find fastq file")
                sys.exit(1)
                
            if num_reads == 1:
                file_out = f"{prefix}-{barcode}-Sequences.txt.gz"
                shutil.move(file_in_R1, file_out)
                
                subprocess.run([sys.executable, process_single, file_out, f"{prefix}-{barcode}", name], check=True)
                
                subprocess.run(f"chmod 770 {prefix}*", shell=True)
                subprocess.run(f"chmod 770 {file_out}", shell=True)
                
                print(f"case A {file_out}")
                with open(f"md5sum_lane{lane}.txt", "a") as md5:
                    subprocess.run(["md5sum", file_out], stdout=md5, check=True)
                    
            elif num_reads == 2:
                file_out_R1 = f"{prefix}-{barcode}-READ1-Sequences.txt.gz"
                file_out_R2 = f"{prefix}-{barcode}-READ2-Sequences.txt.gz"
                
                shutil.move(file_in_R1, file_out_R1)
                shutil.move(file_in_R2, file_out_R2)
                
                subprocess.run([sys.executable, process_paired, file_out_R1, file_out_R2, f"{prefix}-{barcode}", name], check=True)
                
                subprocess.run(f"chmod 770 {prefix}*", shell=True)
                subprocess.run(f"chmod 770 {file_out_R1}", shell=True)
                subprocess.run(f"chmod 770 {file_out_R2}", shell=True)
                
                with open(f"md5sum_lane{lane}.txt", "a") as md5:
                    subprocess.run(["md5sum", file_out_R1], stdout=md5, check=True)
                    subprocess.run(["md5sum", file_out_R2], stdout=md5, check=True)

        # Undetermined
        d = prefixes[0].split("-")
        prefix = f"{d[0]}-{d[1]}"
        # Regex check skipped
        prefix = f"{prefix}-PrNotRecog"
        
        print(f"  Processing Library \"{name}\" - Barcode Not Recognized ({prefix})...")
        
        file_in_R1 = f"Undetermined_S0_L00{lane}_R1_001.fastq.gz"
        file_in_R2 = f"Undetermined_S0_L00{lane}_R2_001.fastq.gz"
        
        if not os.path.isfile(file_in_R1):
            print("Cannot find fastq file")
            sys.exit(1)
        if num_reads == 2 and not os.path.isfile(file_in_R2):
            print("Cannot find fastq file")
            sys.exit(1)
            
        if num_reads == 1:
            file_out = f"{prefix}-Sequences.txt.gz"
            shutil.move(file_in_R1, file_out)
            
            subprocess.run([sys.executable, process_single, file_out, prefix, name], check=True)
            
            subprocess.run(f"chmod 770 {prefix}*", shell=True)
            subprocess.run(f"chmod 770 {file_out}", shell=True)
            
            print(f"case B {file_out}")
            with open(f"md5sum_lane{lane}.txt", "a") as md5:
                subprocess.run(["md5sum", file_out], stdout=md5, check=True)
                
        elif num_reads == 2:
            file_out_R1 = f"{prefix}-READ1-Sequences.txt.gz"
            file_out_R2 = f"{prefix}-READ2-Sequences.txt.gz"
            
            shutil.move(file_in_R1, file_out_R1)
            shutil.move(file_in_R2, file_out_R2)
            
            subprocess.run([sys.executable, process_paired, file_out_R1, file_out_R2, prefix, name], check=True)
            
            subprocess.run(f"chmod 770 {prefix}*", shell=True)
            subprocess.run(f"chmod 770 {file_out_R1}", shell=True)
            subprocess.run(f"chmod 770 {file_out_R2}", shell=True)
            
            with open(f"md5sum_lane{lane}.txt", "a") as md5:
                subprocess.run(["md5sum", file_out_R1], stdout=md5, check=True)
                subprocess.run(["md5sum", file_out_R2], stdout=md5, check=True)

if __name__ == "__main__":
    main()

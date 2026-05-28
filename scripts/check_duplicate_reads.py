import gzip

def compare_fastq_volumes(file_small, file_large):
    """
    Checks if the large file contains exactly 2x the reads 
    or just double the information per read.
    """
    with gzip.open(file_small, 'rt') as f1, gzip.open(file_large, 'rt') as f2:
        # Count lines in a chunk
        small_lines = [next(f1) for _ in range(400)]
        large_lines = [next(f2) for _ in range(400)]
        
        print(f"Small file sample header: {small_lines[0].strip()}")
        print(f"Large file sample header: {large_lines[0].strip()}")
        
        if small_lines[1] == large_lines[1]:
            return "Sequence content matches; likely a lane-merge or file duplication issue."
        else:
            return "Sequence content differs; likely a Read1 vs Read1+Read2 issue."

# Example usage
# print(compare_fastq_volumes("sample_S1_L001_R1.fastq.gz", "sample_S1_merged_R1.fastq.gz"))
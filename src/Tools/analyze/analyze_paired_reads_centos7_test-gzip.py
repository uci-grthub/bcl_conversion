#!/usr/bin/env python3
import argparse
import gzip
import os
import sys
from datetime import datetime
from multiprocessing import Pool
from functools import partial
import subprocess

# Default runtime flags
verbose = True
workers = 16
write_raw_stats_pos = False
batch_size = 1000000


def format_int(number):
    return f"{number:,}"


def log_msg(msg, log_fh=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line)
    if log_fh:
        log_fh.write(line + "\n")


def compute_local_stats(batch_seq1, batch_qual1, batch_seq2, batch_qual2, offset):
    local_calls_r1 = {}
    local_calls_r2 = {}
    local_phred_r1 = []
    local_phred_r2 = []
    local_reads = 0

    for i in range(len(batch_seq1)):
        seq1 = batch_seq1[i]
        qual1 = batch_qual1[i]
        seq2 = batch_seq2[i]
        qual2 = batch_qual2[i]

        len1 = len(seq1)
        if len(local_phred_r1) < len1:
            local_phred_r1 += [0] * (len1 - len(local_phred_r1))
        for k, nt in enumerate(seq1):
            local_calls_r1[f"{k}-{nt}"] = local_calls_r1.get(f"{k}-{nt}", 0) + 1
        for k, qch in enumerate(qual1):
            local_phred_r1[k] += (ord(qch) - offset)

        len2 = len(seq2)
        if len(local_phred_r2) < len2:
            local_phred_r2 += [0] * (len2 - len(local_phred_r2))
        for k, nt in enumerate(seq2):
            local_calls_r2[f"{k}-{nt}"] = local_calls_r2.get(f"{k}-{nt}", 0) + 1
        for k, qch in enumerate(qual2):
            local_phred_r2[k] += (ord(qch) - offset)

        local_reads += 1

    return {"pr1": local_phred_r1, "cr1": local_calls_r1, "pr2": local_phred_r2, "cr2": local_calls_r2, "nr": local_reads}


def main():
    parser = argparse.ArgumentParser(description="Analyze paired gzipped FASTQ reads")
    parser.add_argument("fastqR1")
    parser.add_argument("fastqR2")
    parser.add_argument("prefix")
    parser.add_argument("sample", nargs="?")
    parser.add_argument("-w", "--workers", type=int, default=workers)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    global verbose
    verbose = args.verbose
    w = args.workers

    fastqR1 = args.fastqR1
    fastqR2 = args.fastqR2
    prefix = args.prefix
    library = args.sample or prefix

    multiplex = False
    barcode = ""
    if "-" in prefix:
        for cand in prefix.split("-"):
            l = len(cand)
            if 4 <= l <= 12 and all(ch in "ACGT" for ch in cand):
                multiplex = True
                barcode = cand if barcode == "" else f"{barcode}-{cand}"
            if cand == "PrNotRecog":
                multiplex = True
                barcode = "Not Recognized"

    log_dir = "logs"
    os.makedirs(log_dir, exist_ok=True)
    timestamp_fn = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = os.path.join(log_dir, f"{library}_{timestamp_fn}.log")
    log_fh = open(log_file, "w")
    log_msg(f"Log file created: {log_file}", log_fh)

    if not os.path.isfile(fastqR1):
        print("Input Fastq File 1 Not Found.")
        sys.exit(1)
    if not os.path.isfile(fastqR2):
        print("Input Fastq File 2 Not Found.")
        sys.exit(1)

    if verbose:
        log_msg(f"\n  FASTQ IN 1 : {fastqR1}\n  FASTQ IN 2 : {fastqR2}\n  PREFIX OUT : {prefix}\n  SAMPLE ID  : {library}\n  MULTIPLEX  : {multiplex}\n  BARCODE    : {barcode}\n", log_fh)

    raw_stats_pos_out = f"{prefix}-RawStatsPerPos.tsv"
    basic_description = f"{prefix}-SampleBasicInfo.txt"
    gnuplot_phred_out = f"{prefix}-PhredQualScores.png"
    gnuplot_callsR1_out = f"{prefix}-READ1-BaseComposition.png"
    gnuplot_callsR2_out = f"{prefix}-READ2-BaseComposition.png"
    gnuplot_source = f"{prefix}-gnuplot.src"
    gnuplot_data = f"{prefix}-gnuplot.dat"

    NTS = ["A", "C", "G", "T", "N"]
    offset = 33

    POS_PHRED_R1 = []
    POS_CALLS_R1 = {}
    POS_PHRED_R2 = []
    POS_CALLS_R2 = {}
    num_POS_R1 = 0
    num_POS_R2 = 0
    num_reads = 0

    pos_min = 1
    pos_xtics = 5
    phred_min = 60
    phred_max = 0

    tmp_dir = "tmp"
    os.makedirs(tmp_dir, exist_ok=True)

    results = []
    pool = Pool(processes=w)
    tasks = []

    if verbose:
        log_msg("  Analyzing fastq files (long process)...", log_fh)

    # Read gzipped FASTQ in batches
    with gzip.open(fastqR1, 'rt') as IN1, gzip.open(fastqR2, 'rt') as IN2:
        while True:
            batch_seq1 = []
            batch_qual1 = []
            batch_seq2 = []
            batch_qual2 = []

            for _ in range(batch_size):
                h1 = IN1.readline()
                if not h1:
                    break
                if not h1.startswith('@'):
                    print("1 not in FastQ file format.")
                    sys.exit(1)
                h2 = IN2.readline()
                if not h2:
                    print("Inputs are not paired-reads.")
                    sys.exit(1)
                if not h2.startswith('@'):
                    print("Input 2 not in FastQ file format.")
                    sys.exit(1)

                seq1 = IN1.readline().rstrip('\n')
                plus1 = IN1.readline()
                qual1 = IN1.readline().rstrip('\n')

                seq2 = IN2.readline().rstrip('\n')
                plus2 = IN2.readline()
                qual2 = IN2.readline().rstrip('\n')

                batch_seq1.append(seq1)
                batch_qual1.append(qual1)
                batch_seq2.append(seq2)
                batch_qual2.append(qual2)

            if len(batch_seq1) == 0:
                break

            # submit to pool
            tasks.append(pool.apply_async(compute_local_stats, (batch_seq1, batch_qual1, batch_seq2, batch_qual2, offset)))

    pool.close()
    for t in tasks:
        h = t.get()
        nr = h.get('nr', 0)
        num_reads += nr

        pr1 = h.get('pr1', [])
        for i, v in enumerate(pr1):
            if i >= len(POS_PHRED_R1):
                POS_PHRED_R1 += [0] * (i - len(POS_PHRED_R1) + 1)
            POS_PHRED_R1[i] += v
        pr2 = h.get('pr2', [])
        for i, v in enumerate(pr2):
            if i >= len(POS_PHRED_R2):
                POS_PHRED_R2 += [0] * (i - len(POS_PHRED_R2) + 1)
            POS_PHRED_R2[i] += v

        for k, v in h.get('cr1', {}).items():
            POS_CALLS_R1[k] = POS_CALLS_R1.get(k, 0) + v
        for k, v in h.get('cr2', {}).items():
            POS_CALLS_R2[k] = POS_CALLS_R2.get(k, 0) + v

    pool.join()

    if num_reads == 0:
        print("Empty FastQ Files!")
        sys.exit(1)
    if verbose:
        log_msg(f"  Done! {num_reads} paired-reads found in input.", log_fh)

    num_POS_R1 = len(POS_PHRED_R1)
    num_POS_R2 = len(POS_PHRED_R2)

    # finalize and normalize
    POS_ID_R1 = [str(i+1) for i in range(num_POS_R1)]
    POS_ID_R2 = [str(i+1) for i in range(num_POS_R2)]

    sum_nocall = 0
    for i in range(num_POS_R1):
        for nt in NTS:
            POS_CALLS_R1.setdefault(f"{i}-{nt}", 0)
        sum_nocall += POS_CALLS_R1.get(f"{i}-N", 0)
    for i in range(num_POS_R2):
        for nt in NTS:
            POS_CALLS_R2.setdefault(f"{i}-{nt}", 0)
        sum_nocall += POS_CALLS_R2.get(f"{i}-N", 0)

    # Write raw stats per position if desired
    if verbose and write_raw_stats_pos:
        log_msg("  Writing stats per position...", log_fh)
    if write_raw_stats_pos:
        with open(raw_stats_pos_out, 'w') as OUT:
            OUT.write("Position\tPHRED (1)\tA (1)\tC (1)\tG (1)\tT (1)\tN (1)\tPHRED (2)\tA (2)\tC (2)\tG (2)\tT (2)\tN (2)\n")
            max_pos = max(num_POS_R1, num_POS_R2)
            for i in range(max_pos):
                pos = str(i+1)
                OUT.write(pos)
                if i < num_POS_R1:
                    ph1 = POS_PHRED_R1[i] / num_reads
                    OUT.write(f"\t{ph1:.2f}")
                else:
                    OUT.write("\t")
                for nt in NTS:
                    if i < num_POS_R1:
                        v = POS_CALLS_R1.get(f"{i}-{nt}", 0) / num_reads
                        OUT.write(f"\t{v:.4f}")
                    else:
                        OUT.write("\t")
                if i < num_POS_R2:
                    ph2 = POS_PHRED_R2[i] / num_reads
                    OUT.write(f"\t{ph2:.2f}")
                else:
                    OUT.write("\t")
                for nt in NTS:
                    if i < num_POS_R2:
                        v = POS_CALLS_R2.get(f"{i}-{nt}", 0) / num_reads
                        OUT.write(f"\t{v:.4f}")
                    else:
                        OUT.write("\t")
                OUT.write("\n")
        os.chmod(raw_stats_pos_out, 0o770)
    else:
        if os.path.exists(raw_stats_pos_out):
            try:
                os.remove(raw_stats_pos_out)
            except Exception:
                pass

    # Basic sample description
    if verbose:
        log_msg("  Writing basic sample info...", log_fh)
    with open(basic_description, 'w') as OUT:
        OUT.write(f"Files   : {prefix}-*\n")
        if multiplex:
            OUT.write(f"Library : {library}\n")
            OUT.write(f"Barcode : {barcode}\n")
        else:
            OUT.write(f"Sample  : {library}\n")
        OUT.write(f"#Reads  : {format_int(num_reads)}\n")
        OUT.write(f"Cycles1 : {num_POS_R1}\n")
        OUT.write(f"Cycles2 : {num_POS_R2}\n")
    os.chmod(basic_description, 0o770)

    # Extracting graph features
    if verbose:
        log_msg("  Extracting graph features...", log_fh)

    max_pos = max(num_POS_R1, num_POS_R2)
    pos_max = max_pos
    while (pos_max / pos_xtics) > 21:
        pos_xtics += 5

    for i in range(num_POS_R1):
        ph = POS_PHRED_R1[i] / num_reads
        if ph < phred_min:
            phred_min = ph
        if ph > phred_max:
            phred_max = ph
    for i in range(num_POS_R2):
        ph = POS_PHRED_R2[i] / num_reads
        if ph < phred_min:
            phred_min = ph
        if ph > phred_max:
            phred_max = ph

    phred_min -= 1
    phred_max += 1

    # Generate gnuplot data for PHRED
    if verbose:
        log_msg("  Generating plot for quality scores...", log_fh)
    with open(gnuplot_data, 'w') as OUT:
        for i in range(max_pos):
            pos = str(i+1)
            line = pos
            if i < num_POS_R1:
                line += f" {POS_PHRED_R1[i]/num_reads:.2f}"
            else:
                line += " ?"
            if i < num_POS_R2:
                line += f" {POS_PHRED_R2[i]/num_reads:.2f}\n"
            else:
                line += " ?\n"
            OUT.write(line)

    title_lane1 = f"Sample '{library}'" if not multiplex else f"Library '{library}' - Barcode '{barcode}'"
    title_lane2 = ""
    title_lane3 = "Sequencing Data Quality"

    plot_width = 820
    plot_height = 540
    gdfont_path = "/usr/share/fonts/dejavu-sans-fonts:/usr/share/fonts/dejavu-serif-fonts:/usr/share/fonts/dejavu-sans-mono-fonts"

    with open(gnuplot_source, 'w') as OUT:
        OUT.write(f"set term png size {plot_width},{plot_height} \n")
        OUT.write(f"set output \"{gnuplot_phred_out}\"\n")
        OUT.write(f"set title \"{title_lane1}\n{title_lane2}\n{title_lane3}\"\n")
        OUT.write(f"set xrange [{pos_min}:{pos_max}]\n")
        OUT.write(f"set xtics {pos_xtics}\n")
        OUT.write(f"set grid xtics\n")
        OUT.write(f"set xlabel \"Sequence Position\"\n")
        OUT.write(f"set yrange [{phred_min}:{phred_max}]\n")
        OUT.write(f"set ylabel \"Mean PHRED Quality Score\"\n")
        OUT.write(f"plot \"{gnuplot_data}\" using 1:2 with lines title \"READ 1\", \"{gnuplot_data}\" using 1:3 with lines title \"READ 2\"\n")

    try:
        env = os.environ.copy()
        env['GDFONTPATH'] = gdfont_path
        subprocess.run(['gnuplot', gnuplot_source], check=False, env=env)
    except Exception:
        pass

    # Base composition plots
    if verbose:
        log_msg("  Generating plot for base composition R1...", log_fh)
    with open(f"{prefix}-gnuplot_callsR1.dat", 'w') as OUT:
        for i in range(num_POS_R1):
            vals = [POS_CALLS_R1.get(f"{i}-{nt}", 0) for nt in NTS]
            OUT.write(str(i+1) + ' ' + ' '.join(str(v) for v in vals) + '\n')
    if verbose:
        log_msg("  Generating plot for base composition R2...", log_fh)
    with open(f"{prefix}-gnuplot_callsR2.dat", 'w') as OUT:
        for i in range(num_POS_R2):
            vals = [POS_CALLS_R2.get(f"{i}-{nt}", 0) for nt in NTS]
            OUT.write(str(i+1) + ' ' + ' '.join(str(v) for v in vals) + '\n')

    log_fh.close()


if __name__ == '__main__':
    main()

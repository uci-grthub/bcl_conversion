DRAGEN is designed to be "self-tuning," meaning it automatically detects your system's hardware resources (CPU cores and memory) and configures its internal threading model dynamically.

However, the term AsyncIoThreads is actually a specific parameter from the older bcl2fastq2 software. In the newer DRAGEN/BCL Convert architecture, this has been replaced by more granular "dynamic" thread pools.
## How DRAGEN Auto-Configures Threads

When you run dragen --bcl-conversion-only, it automatically balances four main thread types based on your server's available nproc:

    Decompression Threads: Handles reading the raw .cbcl files from disk.

    Parallel Tiles: Determines how many flow cell tiles are processed at the exact same time.

    Conversion Threads: The "worker" threads that handle demultiplexing and base-calling logic.

    Compression Threads: The most CPU-intensive part, which handles the gzip (or .ora) compression for the final FASTQ files.

    Note: If you are running this on an Apple Silicon Mac (via Rosetta/Colima as we discussed before), DRAGEN might not be able to "see" the underlying hardware correctly. In that specific case, you might need to manually override these values.

## When to Manually Override

You should only move away from "Auto" if you are on a shared HPC cluster (like the UCI clusters) where you aren't allowed to use all the cores, or if you notice your disk I/O cannot keep up with the CPU.

If you need to manually tune the performance, you use these flags instead of the old AsyncIoThreads:
Parameter	Recommended Manual Value
--bcl-num-parallel-tiles	1 to 4 (Higher uses more RAM)
--bcl-num-conversion-threads	8 to 16
--bcl-num-compression-threads	16 to 32 (This is the usual bottleneck)
--bcl-num-decompression-threads	8
### The Formula for Total Threads

DRAGEN calculates its total CPU footprint using this logic:
Total Threads=(Parallel Tiles×Conversion Threads)+Compression+Decompression
## Pro-Tip: Checking the "Auto" Decisions

To see what DRAGEN actually decided to do for your specific run, look at the top of your log output or the Reports/Dragen_BCL_Log.txt. It will print a block called Hardware Resources that shows exactly how many threads were allocated for each step.
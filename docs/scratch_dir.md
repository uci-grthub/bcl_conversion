The answer depends on what scratch_dir points to:

Yes, IO load increases if scratch_dir is on a different physical device than the final output — DRAGEN writes FASTQs to scratch, then you mv them to the JBOD RAID. If scratch and destination are on different filesystems, mv falls back to a full copy (read + write), doubling the IO for every FASTQ.

No extra IO if scratch is on the same filesystem as the output (same mount), since mv is just a rename (metadata-only).

The benefit scratch gives you is writing at local SSD speeds during the DRAGEN run itself, which reduces DRAGEN runtime and avoids hammering the JBOD RAID during peak demux. The copy cost on the back end is a sequential bulk transfer, which is much friendlier to the RAID than the random scattered writes DRAGEN produces mid-run.

So the tradeoff is: more total bytes transferred, but better RAID health and likely faster wall-clock time if the scratch device is fast (NVMe/local SSD).
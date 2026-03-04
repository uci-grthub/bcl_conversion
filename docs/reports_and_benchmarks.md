snakemake --report is partially robust to --touch, but with a meaningful gap:

What happens to the timeline:

Rules that were actually executed get starttime/endtime recorded → appear in the timeline correctly
Rules that were only --touched get no timing entries written → they are silently omitted from the timeline
In this run you can see exactly that split. The --touch log shows email_sent.done, fastp_lane1_default.done, etc. were touched. Those rules (compile_read_counts, summarize_project_reads, generate_renaming_map, generate_samplesheets, project_link, verify_project_link, report_order_id, generate_exclude_indexes, consolidate_project_links) all have .bench files but are absent from the timeline in report.html.

So the report doesn't lie, but it's incomplete — the timeline only reflects the partial execution from the non-touched portion.

Impact on the two scripts:

Script	Source	--touch impact
parse_timeline.py	report.html timeline	Omits touched rules — total wall time is understated
summarize_benchmarks.py	.bench files	Unaffected — --touch never writes benchmark files
Bottom line: If you used --touch on some rules before running snakemake --report, the resulting report.html timeline (and timeline_entries.csv) represents only the jobs that actually ran, not the full workflow. The benchmark summary is more reliable in that case since it only reflects genuine executions.
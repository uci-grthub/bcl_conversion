# Running a sequencing run from the web page

The page does everything the SOP does by hand: it sets up the run folder, checks the
sample sheet, waits for your approval, then schedules the run. Once scheduled, the run
starts on its own when the sequencer finishes. It processes the data, emails customers,
publishes to the share, backs up to HPC3 (and to a USB drive if you give one), then
removes itself from the schedule.

## Open the page

1. Log in to the server and start the page (leave this window open while you use it):

   ```bash
   cd /staging/nextcloud/testing_illumina/NovaSeqX/.bcl_gui
   pixi run gui
   ```

2. It prints two things. On **your own computer**, open a second terminal and paste the
   `ssh -N -L ...` line it printed (it stays quiet; leave it running).
3. Paste the `http://localhost:.../?token=...` link into your browser.

Closing the page or pressing Ctrl+C in step 1 does **not** stop scheduled runs.

## A new run, step by step

1. **New run**: type the run ID (e.g. `xR123`) and pick the lab's sample sheet from the
   list (newest first), or upload it. Press *Set up run* and wait for the log to finish.
2. **Settings**: check the sequencer data folder and put **your** email address in
   *Send results to*. Press *Save settings*.
3. **Readiness checks**: every line should show ✓. A ✗ on HPC3 or Nextcloud means your
   login for that service needs setting up; ask the pipeline maintainer.
4. **Check metadata**: reads the sheet and builds the workflow plan without processing
   anything. If it lists issues, read them (or download the highlighted sheet). Fix the
   sheet with the lab if needed, upload it as a new run, and check again.
5. **Approve**, then **Schedule**. Done. The run list shows progress:

| Status | Meaning |
| --- | --- |
| Needs checking / Checked, awaiting approval | Steps 4–5 are still to do |
| Scheduled | Waiting for the sequencer; checked every 30 minutes |
| Processing | The workflow is running (several hours) |
| Published; backing up | Customers have their data; backups running |
| Finished and backed up | Nothing left to do |
| Stopped before publishing / Approval withdrawn | Needs a person; see below |

## When something needs attention

- **Approval withdrawn**: the sheet or settings changed after you approved. Check again
  and re-approve.
- **Stopped before publishing**: the workflow failed. Open the run, pick *Workflow
  (snakemake)* in the log list, and send the end of it to the pipeline maintainer. The
  page deliberately has no "run again" button: a re-run re-emails every customer.
- **Published; backup retrying**: a backup failed and retries every 30 minutes. If it
  keeps failing, check the *Cron* log and the HPC3 readiness check.

## For the maintainer

- Set up the control clone once per platform folder:
  `git clone https://github.com/uci-grthub/bcl_conversion <platform>/.bcl_gui && cd $_ && pixi install`.
  `git pull` there updates the page and the pipeline version new runs get (new run dirs
  are cloned from it).
- Each operator runs their own copy of the page: cron entries go into their crontab and
  use their `~/.env` and hpc3 SSH key. The port is `8000 + uid % 1000`; `--port` overrides.
- The page binds `127.0.0.1` and requires the printed token, since every account on the
  host can reach a local port.
- Approval is `.metadata_approved` in the run dir, holding a sha256 of the sheet + project
  config. `run_when_ready.sh` refuses to start without a matching one; a run scheduled by
  hand (no GUI) needs `REQUIRE_APPROVAL=0` on its cron line.
- GUI cron entries end in `# bclgui:<run_id>`; `run_and_backup_when_ready.sh` deletes that
  line once every backup step has its `.post_<step>.done` marker.

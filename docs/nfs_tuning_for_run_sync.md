# NFS tuning request for run-sync throughput

## Summary / ask

We mirror NovaSeqX/MiSeq run directories (~2.6 TB each, almost entirely
FASTQ.gz) from a compute host to the NFS share on `128.195.12.36`. A single
`rsync` stream only fills ~21% of the available 10 GbE link, so transfers take
~2.8 h when the link could do it in ~45–60 min.

We would like the mount tuned to use more of the link. Two requests, in order
of leverage:

1. **Remount `/mnt/jbod_localdisk` with `nconnect=8`** (multiple TCP
   connections per mount).
2. **Consider switching `soft` → `hard`** for this mount, since we are about to
   drive the server harder (see "Interaction with current mount options").

Client-side we have also parallelized the transfer (4 concurrent `rsync`
streams across the per-lane `output/` subdirs), which helps independently of
`nconnect`. The two approaches compound.

## Current state (measured)

Client `128.195.12.34` → server `128.195.12.36`.

Mount (`/proc/mounts`):

```
128.195.12.36:/localdisk on /mnt/jbod_localdisk type nfs4
  (rw,relatime,vers=4.2,rsize=1048576,wsize=1048576,namlen=255,soft,
   proto=tcp,timeo=30,retrans=2,sec=sys,clientaddr=128.195.12.34,
   local_lock=none,addr=128.195.12.36)
```

- NFS traffic goes over `enp26s0f1`, link speed **10000 Mb/s (10 GbE)**.
- **No `nconnect`** → a single TCP connection per mount.
- During a live single-stream transfer (`sar -n DEV 1 3`):

  | metric | value |
  |---|---|
  | tx throughput | ~257 MB/s (~2.1 Gb/s) |
  | link utilization (`%ifutil`) | ~21% |

So ~79% of the 10 GbE pipe is idle. A single NFS write stream is
**latency-bound, not bandwidth-bound** — the classic case where additional TCP
connections (`nconnect`) and/or concurrent streams raise aggregate throughput.

## Why `nconnect` helps here

`nconnect=N` opens N TCP connections per client↔server mount, letting the
client keep more requests in flight and hide per-RPC round-trip latency. On a
10 GbE link with a single latency-bound stream, this typically multiplies
throughput until the link or server saturates.

- Supported in mainline Linux since kernel 5.3; we are on NFSv4.2, which
  supports it.
- Recommended range **4–8**; kernel caps at 16. Values above 8 give little
  extra throughput and consume more server-side connection state.
- It is a mount-time option, so it requires unmount/remount (transfers must be
  stopped first). Ideally all clients of this server use a consistent value.

## Does this risk disk failure or mount instability?

- **Disk failure: no.** `nconnect` only changes the number of TCP connections.
  It does not change total bytes written, does not touch the server disks
  directly, and does not increase disk wear. The only effect is that the
  server's disks run at higher sustained utilization *while a transfer is
  active* — normal operating load, not a failure driver.
- **Mount stability:** `nconnect` itself is mature and stable. Keep it ≤8.

## Interaction with current mount options (the real caveat)

The mount is currently `soft,timeo=30,retrans=2`:

- `soft` → NFS **returns an I/O error** (rather than waiting) when the server
  does not respond in time.
- `timeo=30` = 3.0 s; `retrans=2` → gives up after ~2 retries.

When we drive the server harder — via `nconnect` *or* the parallel client-side
`rsync` — a momentarily slow/overloaded server is more likely to trip that 3 s
timeout and **fail part of a transfer with EIO**. This does not corrupt
already-written data and rsync is restartable, but it can abort a run mid-way.

For large sequential writes, a **`hard`** mount (operations wait and retry
instead of erroring out) is the safer-integrity choice. If you are remounting
for `nconnect` anyway, pairing `nconnect=8` with `hard` avoids
timeout-driven I/O errors at higher throughput.

## Suggested mount options

```
rw,vers=4.2,nconnect=8,hard,proto=tcp,rsize=1048576,wsize=1048576,sec=sys
```

(`rsize`/`wsize` already at 1 MB — no change needed there.)

## How to verify after the change

On the client, during a transfer:

```
sar -n DEV 1 5 | grep enp26s0f1     # watch %ifutil / txkB/s climb
nfsiostat 3 2                        # per-mount NFS throughput
```

Expect `%ifutil` to rise well above the current ~21% as connections/streams
increase, plateauing when the link or server saturates.

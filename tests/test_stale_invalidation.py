"""The sheet-derived artifacts the Snakefile drops when a sample sheet changes.

A regenerated SampleSheet_{cid}.csv does not reschedule the rules that consume it
through ancient(), so the Snakefile deletes their outputs at parse time instead. The
list has to keep pace with the rules: these tests derive the ancient() chain from the
shipped rule definitions and fail when a link is missing.
"""
import os
import re

from _helpers import REPO, load_snakefile_function

CONFIG_ID = "lane3"
SHEET = "results/{config_id}/SampleSheet_{config_id}.csv"


def _stale_artifacts(config_id=CONFIG_ID):
    fn = load_snakefile_function(
        "_stale_samplesheet_artifacts",
        "# Spawned job subprocesses re-parse this file",
    )
    return list(fn(config_id))


def _snakefile():
    with open(os.path.join(REPO, "Snakefile")) as handle:
        return handle.read()


def _rule_blocks(source):
    """(name, body) for every rule, body running to the next top-level rule."""
    starts = [(m.group(1), m.start()) for m in re.finditer(r"^rule (\w+):", source, re.M)]
    for i, (name, start) in enumerate(starts):
        end = starts[i + 1][1] if i + 1 < len(starts) else len(source)
        yield name, source[start:end]


def _input_section(body):
    """The input: block of a rule, ending at the next section keyword."""
    match = re.search(r"^    input:\n(.*?)(?=^    \w+:)", body, re.M | re.S)
    return match.group(1) if match else ""


def _declared_outputs(body):
    match = re.search(r"^    output:\n(.*?)(?=^    \w+:)", body, re.M | re.S)
    if not match:
        return []
    return re.findall(r'"([^"]+\{config_id\}[^"]*)"', match.group(1))


def test_rc_chain_is_invalidated():
    """The RC chain replays superseded barcodes if these survive a sheet correction."""
    stale = _stale_artifacts()
    for path in (
        f"logs/{CONFIG_ID}/rc_candidates_{CONFIG_ID}.json",
        f"results/{CONFIG_ID}/SampleSheet_{CONFIG_ID}_rc.csv",
        f"results/{CONFIG_ID}/SampleSheet_{CONFIG_ID}_rc_validated.csv",
    ):
        assert path in stale, f"{path} not invalidated when the sample sheet changes"


# Demux products. These are in the ancient() chain too, but parse-time deletion stops
# short of them on purpose: use_ancient exists so that correcting a sheet does not
# silently discard hours of DRAGEN output and terabytes of FASTQ. Redoing a demux is an
# operator decision, made explicitly:
#
#     snakemake --config use_ancient=false --forcerun bcl_convert
#
# The cost of that boundary is that a corrected sheet leaves the previous orientation's
# demux on disk for pick_orientation to weigh. That is safe only because the superseded
# barcodes lose on read count; it is not a guarantee. Widening this set is a decision
# about destroying data, not a bookkeeping fix.
OPERATOR_REBUILT = {
    ".output_rc/{config_id}",
    ".output_rc/{config_id}/.done",
    "results/{config_id}/fqtk_{config_id}.done",
}


def _ancient_chain(source):
    """Fixpoint walk outward from the sample sheet over maybe_ancient() edges."""
    blocks = list(_rule_blocks(source))
    chain = {SHEET}
    for _ in range(len(blocks)):  # bounded: the chain grows by >=1 or we stop
        grown = False
        for _name, body in blocks:
            ancient = set(re.findall(r'maybe_ancient\(\s*"([^"]+)"', _input_section(body)))
            if not (ancient & chain):
                continue
            for out in _declared_outputs(body):
                if out not in chain:
                    chain.add(out)
                    grown = True
        if not grown:
            break
    return chain


def test_every_ancient_consumer_of_the_sheet_is_invalidated():
    """Derive the chain from the rules, so a new link cannot be added silently.

    Any rule taking a chain member as maybe_ancient() puts its own {config_id}
    outputs in the chain too. Everything the walk reaches must be either invalidated
    at parse time or named in OPERATOR_REBUILT.
    """
    stale = set(_stale_artifacts())
    chain = _ancient_chain(_snakefile()) - {SHEET} - OPERATOR_REBUILT

    missing = sorted(
        out.format(config_id=CONFIG_ID)
        for out in chain
        if out.format(config_id=CONFIG_ID) not in stale
    )
    assert not missing, (
        "rules take these as ancient() outputs of the sample-sheet chain, but a "
        "regenerated sheet leaves them stale. Add them to "
        "_stale_samplesheet_artifacts, or to OPERATOR_REBUILT if rebuilding them "
        "destroys demux output: " + ", ".join(missing)
    )


def test_operator_rebuilt_paths_are_really_in_the_chain():
    """Keep OPERATOR_REBUILT from drifting into a place to park inconvenient paths."""
    chain = _ancient_chain(_snakefile())
    stragglers = sorted(OPERATOR_REBUILT - chain)
    assert not stragglers, (
        "no longer reachable from the sample sheet via ancient(); drop from "
        "OPERATOR_REBUILT: " + ", ".join(stragglers)
    )


def test_artifacts_are_scoped_to_the_config_id():
    """No path may leak into a lane the sheet change did not touch."""
    for path in _stale_artifacts("lane7"):
        assert "lane7" in path
        assert "{config_id}" not in path

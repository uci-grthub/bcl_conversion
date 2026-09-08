"""The email receipt guard and publish have to agree about who gets to send.

send_order_email short-circuits on Reports/order_<id>/.email_receipt so that a
bare `snakemake` on a finished run stops re-mailing every order: the rule sits
behind the pick_orientation checkpoint, so it is scheduled on every DAG build
whether or not it has anything to do, and mail is not idempotent.

Publishing is the deliberate case. publish_run.sh reaches the rule through
--forcerun, and --forcerun re-runs the job without caring what the body then
decides -- so unless publish clears the receipts first, the rule runs, declines
to send, and publish reports success having mailed nothing.
"""
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBLISH = os.path.join(REPO, "scripts", "publish_run.sh")
SNAKEFILE = os.path.join(REPO, "Snakefile")

RECEIPT = ".email_receipt"


def publish_source():
    return open(PUBLISH).read()


def test_the_rule_still_short_circuits_on_a_receipt():
    """If this stops being true, the clearing below is pointless, not harmless."""
    source = open(SNAKEFILE).read()
    start = source.index("rule send_order_email:")
    body = source[start:source.index("\nrule ", start + 1)]
    assert RECEIPT in body, "send_order_email no longer references the receipt"
    assert "os.path.exists(receipt)" in body


def test_publish_clears_receipts_before_forcing_the_run():
    """Order matters: clearing after the forcerun would be a no-op for this run."""
    source = publish_source()
    cleared = source.index("rm -f Reports/order_*/" + RECEIPT)
    forced = source.index("--forcerun send_order_email\n", cleared)
    assert cleared < forced


def test_publish_clears_each_sweep_variants_receipts():
    """Each variant is its own workdir, with its own Reports/ and its own receipts."""
    source = publish_source()
    assert re.search(r'rm -f "\$sweep"/Reports/order_\*/' + re.escape(RECEIPT), source), \
        "step 6 does not clear the variant's receipts"


def test_the_receipt_is_not_a_declared_output():
    """Snakemake must not manage it, or it gets cleaned up with the rest of the job.

    The point of the receipt is that it survives whatever the scheduler decides
    to redo; a declared output would be removed on the next forced run.
    """
    source = open(SNAKEFILE).read()
    start = source.index("rule send_order_email:")
    body = source[start:source.index("\nrule ", start + 1)]
    output_block = body[body.index("    output:"):body.index("    log:")]
    assert RECEIPT not in output_block

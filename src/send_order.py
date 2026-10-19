"""Rank orders so their emails go out in reverse sample-sheet order.

The Snakefile applies these ranks to project_link, one generated copy per
project (Snakemake's priority is per rule, not per job). Links run one at a time
and every order's report waits on its links, so link order is the order in which
emails become ready. A priority only decides which of the jobs ready *now*
starts first; nothing here makes a ready email wait for one that is not.
"""
import re

# bcl_convert (100) and bcl_convert_rc (90) share project_link's serial_operation
# slot. Keep every rank below the lowest prioritized rule (send_read_counts_email,
# 80) so ranking orders can never push a link ahead of a DRAGEN demux.
PRIORITY_CEILING = 50.0


def order_positions(order_ids, order_id_lookup, fallback_lanes=None):
    """Map each order to its (lane, group) position in the sample sheet.

    An order spanning several lane/groups takes its highest one, so in reverse
    order it goes out with the latest group it belongs to. Orders absent from
    order_id_lookup (flexbar/fqtk) fall back to their highest lane in
    fallback_lanes with group 0, else (0, 0).
    """
    fallback_lanes = fallback_lanes or {}
    positions = {}
    for oid in order_ids:
        spots = [lg for lg, o in order_id_lookup.items() if o == oid]
        if spots:
            positions[oid] = max(spots)
        elif fallback_lanes.get(oid):
            positions[oid] = (max(fallback_lanes[oid]), 0)
        else:
            positions[oid] = (0, 0)
    return positions


def send_priorities(order_ids, order_id_lookup, fallback_lanes=None,
                    ceiling=PRIORITY_CEILING):
    """Map each order to a distinct priority in (0, ceiling).

    Higher lane/group gets the higher priority, so lane N's last group starts
    first and lane 1 group 1 last. Ties (unplaced orders) break on order ID so
    the result is stable from one DAG build to the next.
    """
    order_ids = list(dict.fromkeys(order_ids))
    positions = order_positions(order_ids, order_id_lookup, fallback_lanes)
    ranked = sorted(order_ids, key=lambda oid: (positions[oid], oid))
    n = len(ranked)
    return {oid: round(ceiling * (i + 1) / (n + 1), 4) for i, oid in enumerate(ranked)}


def lanes_from_config_ids(config_ids):
    """['lane6', 'lane8_x'] -> [6, 8]; config IDs without a lane are skipped."""
    lanes = []
    for cid in config_ids:
        m = re.match(r"lane(\d+)", cid)
        if m:
            lanes.append(int(m.group(1)))
    return lanes


def rule_suffix(*keys):
    """Turn order IDs / config IDs / project names into a rule-name suffix."""
    return "_".join(re.sub(r"\W", "_", str(k)) for k in keys)

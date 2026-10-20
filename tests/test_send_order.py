"""Order ranking for reverse sample-sheet email order (src/send_order.py)."""
from send_order import (PRIORITY_CEILING, lanes_from_config_ids, order_positions,
                        rule_suffix, send_priorities)

# (lane, group) -> order_id, shaped like the Snakefile's ORDER_ID_LOOKUP.
# 1026I-26 spans L7G2 and L8G1, as on xR122.
LOOKUP = {
    (1, 1): "1026I-05",
    (6, 2): "0826I-49",
    (7, 2): "1026I-26",
    (7, 14): "0926I-56",
    (8, 1): "1026I-26",
}


def ranked(priorities):
    """Order IDs, first-to-start first."""
    return sorted(priorities, key=priorities.get, reverse=True)


def test_reverse_sample_sheet_order():
    pri = send_priorities(["1026I-05", "0826I-49", "0926I-56", "1026I-26"], LOOKUP)
    assert ranked(pri) == ["1026I-26", "0926I-56", "0826I-49", "1026I-05"]


def test_multi_lane_order_ranks_at_its_latest_position():
    assert order_positions(["1026I-26"], LOOKUP) == {"1026I-26": (8, 1)}


def test_unplaced_orders_fall_back_to_lane_then_rank_last():
    pri = send_priorities(["1026I-05", "FLEX-1", "GHOST"], LOOKUP, {"FLEX-1": [3]})
    assert ranked(pri) == ["FLEX-1", "1026I-05", "GHOST"]


def test_priorities_are_distinct_and_below_the_ceiling():
    """DRAGEN (100/90) shares project_link's serial slot; ranks must stay under it."""
    oids = [f"O-{i}" for i in range(200)]
    pri = send_priorities(oids, {(1, i): oid for i, oid in enumerate(oids)})
    assert len(set(pri.values())) == len(oids)
    assert all(0 < p < PRIORITY_CEILING for p in pri.values())


def test_duplicate_order_ids_are_ranked_once():
    assert list(send_priorities(["1026I-05", "1026I-05"], LOOKUP)) == ["1026I-05"]


def test_lanes_from_config_ids():
    assert lanes_from_config_ids(["lane6", "lane8_flexbar", "sweep"]) == [6, 8]


def test_rule_suffix_is_an_identifier():
    suffix = rule_suffix("lane7", "LinE_1026I-26_xR122_L7_G2")
    assert suffix == "lane7_LinE_1026I_26_xR122_L7_G2"
    assert suffix.isidentifier()

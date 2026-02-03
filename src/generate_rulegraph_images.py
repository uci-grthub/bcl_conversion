import colorsys
import os
import re
import subprocess

RULEGRAPH_FILE = "rulegraph.txt"
OUTPUT_DIR = "rulegraph_images"
DOT_CMD = "dot"
OUTPUT_FORMAT = "svg"

def parse_dot_file(dot_path):
    with open(dot_path) as f:
        lines = f.readlines()
    nodes = {}
    edges = []
    for line in lines:
        node_match = re.match(r'\s*(\d+)\[label = "([^"]+)",', line)
        edge_match = re.match(r'\s*(\d+) -> (\d+)', line)
        if node_match:
            idx, label = node_match.groups()
            nodes[idx] = label
        elif edge_match:
            src, dst = edge_match.groups()
            edges.append((src, dst))
    return nodes, edges

def get_rule_subgraph(rule_idx, nodes, edges):
    # Find direct parents and children
    parents = [src for src, dst in edges if dst == rule_idx]
    children = [dst for src, dst in edges if src == rule_idx]
    sub_nodes = set([rule_idx] + parents + children)
    sub_edges = [e for e in edges if e[0] in sub_nodes and e[1] in sub_nodes]
    return sub_nodes, sub_edges

def _color_for_label(label):
    # Deterministic pastel color based on label
    hue = (abs(hash(label)) % 360) / 360.0
    r, g, b = colorsys.hsv_to_rgb(hue, 0.35, 0.95)
    return f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"


def write_dot(sub_nodes, sub_edges, nodes, out_path):
    with open(out_path, "w") as f:
        f.write("digraph subdag {\n")
        f.write("    graph[bgcolor=white];\n")
        f.write("    node[shape=box, style=\"rounded,filled\", fontname=sans, fontsize=10, penwidth=2];\n")
        f.write("    edge[penwidth=2, color=grey];\n")
        for idx in sub_nodes:
            color = _color_for_label(nodes[idx])
            f.write(f'    {idx}[label = "{nodes[idx]}", fillcolor="{color}"];\n')
        for src, dst in sub_edges:
            f.write(f'    {src} -> {dst};\n')
        f.write("}\n")

def generate_images():
    nodes, edges = parse_dot_file(RULEGRAPH_FILE)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for idx, label in nodes.items():
        sub_nodes, sub_edges = get_rule_subgraph(idx, nodes, edges)
        dot_path = os.path.join(OUTPUT_DIR, f"{label}.dot")
        svg_path = os.path.join(OUTPUT_DIR, f"{label}.{OUTPUT_FORMAT}")
        write_dot(sub_nodes, sub_edges, nodes, dot_path)
        subprocess.run([DOT_CMD, f"-T{OUTPUT_FORMAT}", dot_path, "-o", svg_path])
        print(f"Generated {svg_path}")

if __name__ == "__main__":
    generate_images()
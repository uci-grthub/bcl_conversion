# Advanced Hamming Distance & RC Implementation

This directory contains a git worktree for the **advanced/experimental** barcode Hamming distance + RC logic.

## Worktree Structure

```
.claude/
└── hamming-distance-rc/         # Named worktree (git branch: hamming-distance-rc)
    ├── scripts/
    │   ├── validate_barcode_hamming_distance.py        (simple validation)
    │   └── analyze_hamming_distance_rc_candidates.py   (advanced analysis)
    └── [Snakefile and other files]
```

## Approach

### Simple (main branch)
- **Pre-flight validation**: Checks all sample sheets for barcode Hamming distance conflicts
- **Fails fast** with clear error report if conflicts detected
- Suggests RC as a potential fix

### Advanced (hamming-distance-rc worktree)
- **Conflict detection AND analysis**: Analyzes conflicts and determines which indices (i7 or i5) 
  should be reverse-complemented to resolve them
- **Automatic RC candidate determination**: For each conflicting pair of projects, tries:
  - RC i7 only for project A
  - RC i7 only for project B  
  - RC both i7s
  - RC i5 only for project A
  - RC i5 only for project B
  - RC both i5s
- **Pre-emptive RC**: Marks projects for RC *before* first bcl_convert attempt, preventing 
  Hamming distance errors from stopping the pipeline
- **Integration with RC rules**: Extends `detect_rc_candidates` and `bcl_convert_rc` rules 
  to include Hamming distance conflicts

## Key Scripts

### analyze_hamming_distance_rc_candidates.py
Analyzes conflicts and produces JSON output:
```json
{
  "conflicts_found": true,
  "num_conflicts": 3,
  "conflicts": [
    {
      "lane": "5",
      "project1": "ProjectA",
      "project2": "ProjectB",
      "failing_index": "i7"
    }
  ],
  "rc_candidates": {
    "ProjectA": {
      "i7_rc": true,
      "i5_rc": false,
      "conflicts": ["Lane 5: i7 conflict with ProjectB"]
    }
  }
}
```

## Development Notes

- Both approaches coexist: simple on `main`, advanced on `hamming-distance-rc`
- Worktree allows parallel development without branch switching
- Advanced approach can be tested/refined independently
- When ready, merge onto main or keep as reference implementation

## To Use This Worktree

```bash
cd .claude/hamming-distance-rc
git status
git log
# Make changes...
git add -A && git commit -m "..."
git push origin hamming-distance-rc
```

## To View Differences

```bash
git diff main hamming-distance-rc -- Snakefile scripts/
```

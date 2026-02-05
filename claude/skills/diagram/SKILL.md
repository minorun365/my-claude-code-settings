# AWS Diagram Generator
Generate AWS architecture diagrams using the `diagrams` Python library.

## Steps:
1. Use only `diagrams.aws.*` built-in icons
2. Set graph_attr: rankdir=TB, splines=ortho, nodesep=1.0
3. Group related services in Cluster blocks
4. Test render before adding complexity
5. Output as PNG with 300 DPI

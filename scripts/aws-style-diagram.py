#!/usr/bin/env python3
"""AWS-style architecture diagram for the IDP golden path.

Requires:
    brew install graphviz
    pip3 install diagrams

Usage:
    python3 scripts/aws-style-diagram.py
    → docs/assets/architecture-aws.png
"""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.compute import ECR
from diagrams.aws.management import CloudwatchAlarm, CloudwatchLogs
from diagrams.k8s.compute import Deployment
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.gitops import ArgoCD
from diagrams.onprem.monitoring import Prometheus
from diagrams.onprem.vcs import Github

OUT = Path(__file__).resolve().parent.parent / "docs" / "assets"

graph_attrs = {
    "fontsize": "14",
    "fontname": "Helvetica",
    "bgcolor": "white",
    "rankdir": "LR",
    "pad": "0.4",
    "nodesep": "0.45",
    "ranksep": "0.7",
}
node_attrs = {"fontsize": "11", "fontname": "Helvetica", "shape": "box", "style": "filled,rounded"}
edge_attrs = {"fontsize": "10", "fontname": "Helvetica", "color": "#555555", "fontcolor": "#333333"}

with Diagram(
    "Golden Path IDP on AWS",
    filename=str(OUT / "architecture-aws"),
    outformat="png",
    show=False,
    graph_attr=graph_attrs,
    node_attr=node_attrs,
    edge_attr=edge_attrs,
):
    dev = Node("Developer", fillcolor="#e8e8e8")

    with Cluster("Self-service portal", graph_attr={"bgcolor": "#f7f9fc", "color": "#94a3b8", "labeljust": "l"}):
        backstage = Node("Backstage UI", fillcolor="#dbeafe")
        template = Node("Software Template", fillcolor="#dbeafe")

    with Cluster("GitHub", graph_attr={"bgcolor": "#f7f9fc", "color": "#94a3b8", "labeljust": "l"}):
        repo = Github("Golden-path repo")
        actions = GithubActions("lint · test · sign")

    registry = ECR("ECR")

    with Cluster("Amazon EKS", graph_attr={"bgcolor": "#f7f9fc", "color": "#94a3b8", "labeljust": "l"}):
        argo = ArgoCD("Argo CD")
        kyverno = Node("Kyverno\n(label gate)", fillcolor="#fef3c7")
        workloads = Deployment("Service pods")

    with Cluster("Observability", graph_attr={"bgcolor": "#f7f9fc", "color": "#94a3b8", "labeljust": "l"}):
        prom = Prometheus("Prometheus")
        logs = CloudwatchLogs("Log group")
        alarm = CloudwatchAlarm("5xx alarm")

    terraform = Node("Terraform\nmodules", fillcolor="#ede9fe")
    catalog = Node("Software Catalog", fillcolor="#dbeafe")

    dev >> backstage >> template
    template >> repo
    template - Edge(style="dashed") >> catalog
    repo >> actions
    actions >> registry
    actions - Edge(label="manifests") >> argo
    registry - Edge(label="signed image") >> workloads
    argo - Edge(label="sync") >> workloads
    kyverno - Edge(label="admission") >> workloads
    workloads - Edge(label="/metrics") >> prom
    workloads - Edge(label="logs") >> logs
    logs >> alarm
    terraform - Edge(style="dashed", label="provisions") >> registry
    terraform - Edge(style="dashed") >> logs
    terraform - Edge(style="dashed") >> alarm

print(f"wrote {OUT / 'architecture-aws.png'}")

#!/usr/bin/env python3
"""Security gate: read every scanner's JSON report, apply gate-policy.json, decide.

usage: gate.py <results-dir> [--summary <markdown file>]
Exit code 0 = PASS, 1 = BLOCKED, 2 = a required report is missing (fail closed).
"""

import json
import sys
from pathlib import Path

RANK = {"UNKNOWN": 0, "INFO": 0, "LOW": 1, "WARNING": 2, "MEDIUM": 2, "ERROR": 3, "HIGH": 3, "CRITICAL": 4}
POLICY = json.loads((Path(__file__).parent / "gate-policy.json").read_text())

REPORTS = {
    "bandit": "bandit.json",
    "semgrep": "semgrep.json",
    "pip_audit": "pip-audit.json",
    "trivy_fs": "trivy-fs.json",
    "trivy_config": "trivy-config.json",
    "gitleaks": "gitleaks.json",
    "trivy_image": "trivy-image.json",
}


def at_least(sev: str, threshold: str) -> bool:
    return threshold == "ANY" or RANK.get(sev.upper(), 0) >= RANK[threshold]


def bandit(doc, pol):
    for r in doc.get("results", []):
        yield (r["issue_severity"], f'{r["test_id"]} {r["filename"]}:{r["line_number"]}',
               at_least(r["issue_severity"], pol["block_at"])
               and RANK[r["issue_confidence"]] >= RANK[pol["min_confidence"]])


def semgrep(doc, pol):
    for r in doc.get("results", []):
        sev = r["extra"]["severity"]
        yield sev, f'{r["check_id"].split(".")[-1]} {r["path"]}:{r["start"]["line"]}', at_least(sev, pol["block_at"])


def pip_audit(doc, pol):
    for dep in doc.get("dependencies", []):
        for v in dep.get("vulns", []):
            fix = ",".join(v.get("fix_versions", [])) or "none"
            yield "VULN", f'{dep["name"]}=={dep["version"]} {v["id"]} (fix: {fix})', True


def trivy_vulns(doc, pol):
    for res in doc.get("Results", []) or []:
        for v in res.get("Vulnerabilities", []) or []:
            fixed = bool(v.get("FixedVersion"))
            block = at_least(v["Severity"], pol["block_at"]) and (fixed or not pol.get("only_if_fix_available"))
            yield v["Severity"], f'{v["PkgName"]} {v["VulnerabilityID"]} fix={v.get("FixedVersion") or "none"}', block


def trivy_config(doc, pol):
    for res in doc.get("Results", []) or []:
        for m in res.get("Misconfigurations", []) or []:
            if m.get("Status") == "FAIL":
                yield m["Severity"], f'{m["ID"]} {res["Target"]}: {m["Title"]}', at_least(m["Severity"], pol["block_at"])


def gitleaks(doc, pol):
    for f in doc or []:
        yield "SECRET", f'{f["RuleID"]} {f["File"]}:{f["StartLine"]}', True


PARSERS = {"bandit": bandit, "semgrep": semgrep, "pip_audit": pip_audit, "trivy_fs": trivy_vulns,
           "trivy_config": trivy_config, "gitleaks": gitleaks, "trivy_image": trivy_vulns}


def main() -> int:
    results = Path(sys.argv[1])
    summary = Path(sys.argv[sys.argv.index("--summary") + 1]) if "--summary" in sys.argv else None
    rows, blocked, missing = [], [], []
    for tool, fname in REPORTS.items():
        path = next(results.rglob(fname), None)
        if path is None:
            missing.append(tool)
            rows.append((tool, "-", "-", "MISSING REPORT"))
            continue
        text = path.read_text().strip()
        findings = list(PARSERS[tool](json.loads(text) if text else [], POLICY[tool]))
        blocking = [f for f in findings if f[2]]
        blocked += [(tool, *f[:2]) for f in blocking]
        rows.append((tool, len(findings), len(blocking), "BLOCK" if blocking else "pass"))

    verdict = "MISSING REPORTS" if missing else ("BLOCKED" if blocked else "PASSED")
    lines = ["## Security gate: " + verdict, "",
             "| scanner | policy (block at) | findings | blocking | result |", "|---|---|---|---|---|"]
    for tool, n, b, res in rows:
        lines.append(f'| {tool} | {POLICY[tool]["block_at"]} | {n} | {b} | {res} |')
    if blocked:
        lines += ["", "### Blocking findings", "", "| scanner | severity | finding |", "|---|---|---|"]
        lines += [f"| {t} | {s} | `{d}` |" for t, s, d in blocked]
    report = "\n".join(lines)
    print(report)
    if summary:
        with summary.open("a") as fh:
            fh.write(report + "\n")
    return 2 if missing else (1 if blocked else 0)


if __name__ == "__main__":
    sys.exit(main())

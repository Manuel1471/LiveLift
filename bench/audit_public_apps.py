"""Run the LiveLift source audit against the pinned public application corpus."""

import os
import re
import subprocess
from collections import Counter
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "bench" / "public_apps.tsv"
SUMMARY = re.compile(r"^(\d+)/(\d+) handlers compatible with the current subset$", re.M)
HANDLER = re.compile(r"^.+\.handle_event\([^\n]*\): (compatible$|blocked:)", re.M)
DIAGNOSTIC = re.compile(r"\((E\d{3})\)")


def checkout(repo, commit, destination):
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    git = ["git", "-c", "core.hooksPath=/dev/null", "-C", str(destination)]
    url = f"https://github.com/{repo}.git"
    subprocess.run([*git, "init", "--quiet"], env=env, check=True)
    subprocess.run(
        [*git, "fetch", "--quiet", "--no-tags", "--depth=1", url, commit],
        env=env, check=True, timeout=180,
    )
    subprocess.run([*git, "checkout", "--quiet", "--detach", commit], env=env, check=True)


def summarize_audit(output):
    summaries = SUMMARY.findall(output)
    if len(summaries) != 1:
        raise ValueError("Expected exactly one LiveLift audit summary")
    compatible, total = map(int, summaries[0])

    handlers = list(HANDLER.finditer(output))
    diagnostics = Counter()
    for index, handler in enumerate(handlers):
        if handler[1] == "compatible":
            continue
        end = handlers[index + 1].start() if index + 1 < len(handlers) else len(output)
        diagnostic = DIAGNOSTIC.search(output, handler.end(), end)
        if not diagnostic:
            raise ValueError("Audit contains a source parse failure or an unclassified block")
        diagnostics[diagnostic[1]] += 1

    if len(handlers) != total or compatible + sum(diagnostics.values()) != total:
        raise ValueError("Audit summary does not match its individual results")
    return compatible, total, diagnostics


def main():
    print("| Source revision | Audited directory | Candidate clauses | Total clauses |", flush=True)
    print("| --- | --- | ---: | ---: |", flush=True)
    count_compatible = count_total = 0
    blockers = Counter()
    parser_results = []

    for line in MANIFEST.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        repo, commit, source_dir = line.split("\t")
        with TemporaryDirectory(prefix="livelift-audit-") as directory:
            checkout(repo, commit, directory)
            output = subprocess.check_output(
                ["mix", "live_lift.audit", "--path", str(Path(directory) / source_dir)],
                cwd=ROOT, text=True, timeout=180,
            )
            compatible, total, diagnostics = summarize_audit(output)
            parser_output = subprocess.check_output(
                ["mix", "run", "bench/compare_template_parsers.exs", "public",
                 str(Path(directory) / source_dir)],
                cwd=ROOT, text=True, timeout=180,
            )
            matched, rejected, different_rejection, different_tree = map(
                int, parser_output.splitlines()[-1].split("\t")
            )
            parser_results.append((repo, matched, rejected, different_rejection, different_tree))

        url = f"https://github.com/{repo}/tree/{commit}/{source_dir}"
        print(f"| [{repo} @ {commit[:7]}]({url}) | `{source_dir}` | {compatible} | {total} |", flush=True)
        count_compatible += compatible
        count_total += total
        blockers.update(diagnostics)

    print(f"| **Total** | | **{count_compatible}** | **{count_total}** |")
    print()
    print("| First blocker per clause | Clauses |")
    print("| --- | ---: |")
    for code, total in sorted(blockers.items(), key=lambda pair: (-pair[1], pair[0])):
        print(f"| `{code}` | {total} |")

    print()
    print("| HEEx corpus | Same compiled tree | Same rejection code | Different rejection code | Compilation mismatch |")
    print("| --- | ---: | ---: | ---: | ---: |")
    for row in parser_results:
        print("| " + " | ".join(map(str, row)) + " |")


if __name__ == "__main__":
    main()

"""Summarize paired natural-position continuations, clustering by source seed.

The index reports Godot's step-by-step replay verification. This script checks
that evidence and groups samples; it does not execute the game engine itself.
"""
import argparse
import collections
import csv
import hashlib
import json
import random
from pathlib import Path


def summarize(rows, predicate, repetitions=4000):
    chosen = [row for row in rows if predicate(row)]
    if not chosen:
        return None
    clusters = collections.defaultdict(list)
    for row in chosen:
        clusters[row["seed"]].append(row)
    totals = []
    for group in clusters.values():
        totals.append((len(group), sum(r["legacy_win"] for r in group),
                       sum(r["saved_win"] for r in group)))
    rng = random.Random(20261005)
    differences = []
    for _ in range(repetitions):
        sampled = rng.choices(totals, k=len(totals))
        n = sum(t[0] for t in sampled)
        differences.append(sum(t[2] - t[1] for t in sampled) / n)
    differences.sort()
    n = len(chosen)
    legacy = sum(r["legacy_win"] for r in chosen) / n
    saved = sum(r["saved_win"] for r in chosen) / n
    return {
        "pairs": n, "seed_clusters": len(clusters), "legacy_rate": legacy,
        "saved_rate": saved, "difference": saved - legacy,
        "difference_ci95": [differences[int(.025 * (repetitions - 1))],
                            differences[int(.975 * (repetitions - 1))]],
        "flipped_to_win": sum(not r["legacy_win"] and r["saved_win"] for r in chosen),
        "flipped_to_loss": sum(r["legacy_win"] and not r["saved_win"] for r in chosen),
        "legacy_capped": sum(r["legacy_capped"] for r in chosen),
        "saved_capped": sum(r["saved_capped"] for r in chosen),
        "legacy_mean_turns": sum(r["legacy_turns"] for r in chosen) / n,
        "saved_mean_turns": sum(r["saved_turns"] for r in chosen) / n,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("indexes", nargs="+")
    parser.add_argument("--output", default="artifacts/natural-analysis")
    args = parser.parse_args()
    destination = Path(args.output)
    destination.mkdir(parents=True, exist_ok=True)
    rows, reports, seen = [], [], set()
    pool_hashes = {}
    evidence = {"source_games": 0, "positions": 0, "verified_continuations": 0,
                "matched_source_continuations": 0, "capped_continuations": 0,
                "balanced_positions": 0, "capped_source_games": 0}
    for filename in args.indexes:
        path = Path(filename)
        report = json.loads(path.read_text(encoding="utf-8"))
        if report["origin"] != "natural_simulation" or report["failures"]:
            raise ValueError(f"Expected successful natural sampling: {filename}")
        manifest = report.get("pool_manifest", {})
        if manifest:
            content = {key: value for key, value in manifest.items() if key != "sha256"}
            # Frozen v1 definitions contain strings, lists and integral values;
            # this is the same sorted JSON canonical form used by BattleRepro.
            digest = hashlib.sha256(json.dumps(content, ensure_ascii=False, sort_keys=True,
                                               separators=(",", ":")).encode("utf-8")).hexdigest()
            if digest != manifest["sha256"]:
                raise ValueError(f"Pool manifest content does not match fingerprint: {filename}")
            prior = pool_hashes.setdefault(manifest["id"], manifest["sha256"])
            if prior != manifest["sha256"]:
                raise ValueError(f"Different definitions for frozen pool {manifest['id']}")
        reports.append({"index": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "ai": report["ai"], "source_sha256": report["source_sha256"],
                        "pool_manifest": manifest,
                        "sampling": report["sampling"], "elapsed_ms": report["elapsed_ms"]})
        evidence["source_games"] += len(report["source_games"])
        for source in report["source_games"]:
            if not source["stable"]:
                raise ValueError(f"Unstable source game: {source}")
            evidence["capped_source_games"] += int(source.get("capped", False))
        for item in report["positions"]:
            metadata, position = item["metadata"], item["position"]
            if manifest and (metadata["pool"] != manifest["id"] or metadata.get("pool_sha256") != manifest["sha256"]):
                raise ValueError(f"Snapshot pool fingerprint differs from index: {item['id']}")
            identity = (metadata["pool"], report["ai"], metadata["seed"],
                        position["turn"], position["current_player"])
            if identity in seen:
                raise ValueError(f"Duplicate sample: {identity}")
            seen.add(identity)
            if not (path.parent / item["file"]).is_file():
                raise ValueError(f"Missing position file: {item['file']}")
            variants = item["variants"]
            for name in ("saved", "legacy"):
                trial = variants[name]
                if not trial["stable"] or not trial["verified"]:
                    raise ValueError(f"Invalid continuation: {item['id']} {name}")
                if not (path.parent / trial["file"]).is_file():
                    raise ValueError(f"Missing continuation file: {trial['file']}")
                evidence["verified_continuations"] += 1
                evidence["capped_continuations"] += int(trial["capped"])
            if variants["saved"]["matches_source"] is True:
                evidence["matched_source_continuations"] += 1
            elif not variants["saved"]["capped"]:
                raise ValueError(f"Saved rules do not match source: {item['id']}")
            evidence["positions"] += 1
            players = position["players"]
            gap = abs(players["1"]["units"] - players["2"]["units"])
            if gap == 0:
                evidence["balanced_positions"] += 1
                continue
            trailer = 1 if players["1"]["units"] < players["2"]["units"] else 2
            trailing = players[str(trailer)]
            rows.append({
                "id": item["id"], "index": str(path), "ai": report["ai"],
                "pool": metadata["pool"], "seed": metadata["seed"],
                "turn": position["turn"], "trailer": trailer, "unit_gap": gap,
                "empty": trailing["units"] == 0, "trailer_next": position["current_player"] == trailer,
                "trailer_hero_hp": trailing["hero_hp"],
                **{f"{name}_{metric}": (int(trial["winner"] == f"p{trailer}_wins") if metric == "win" else trial[metric])
                   for name, trial in variants.items() for metric in ("win", "turns", "capped")},
            })
    summary = {"evidence": evidence, "sources": reports, "comparisons": [],
               "definition": "trailing player has fewer living units; excludes equal unit counts",
               "interval": "95% percentile bootstrap resampling source seed clusters within each AI/pool",
               "limitations": "small selected AI sample; AP-generated states, future rules changed only; not human comeback rates"}
    predicates = {
        "unit_deficit": lambda r: True,
        "unit_gap_at_least_2": lambda r: r["unit_gap"] >= 2,
        "empty_board": lambda r: r["empty"],
        "trailer_acts_next": lambda r: r["trailer_next"],
        "leader_acts_next": lambda r: not r["trailer_next"],
    }
    for ai, pool in sorted({(r["ai"], r["pool"]) for r in rows}):
        group = [r for r in rows if r["ai"] == ai and r["pool"] == pool]
        for label, predicate in predicates.items():
            result = summarize(group, predicate)
            if result:
                summary["comparisons"].append({"ai": ai, "pool": pool, "group": label, **result})
    (destination / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    if rows:
        with (destination / "pairs.csv").open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    print(json.dumps(evidence))
    for row in summary["comparisons"]:
        lo, hi = row["difference_ci95"]
        print(f"{row['ai']:6} {row['pool']:10} {row['group']:22} n={row['pairs']:2} seeds={row['seed_clusters']:2} "
              f"{row['legacy_rate']:.1%}->{row['saved_rate']:.1%} diff={row['difference']:+.1%} "
              f"CI=[{lo:+.1%},{hi:+.1%}] turns={row['legacy_mean_turns']:.1f}->{row['saved_mean_turns']:.1f}")


if __name__ == "__main__":
    main()

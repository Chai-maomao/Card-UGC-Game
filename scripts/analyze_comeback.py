"""Analyze paired continuation trials; confidence intervals resample seed clusters."""
import argparse
import collections
import csv
import hashlib
import json
import random
from pathlib import Path

LABELS = {
    "equal": "均势 2 对 2", "slight": "轻度落后 2 对 3",
    "medium": "场面落后 1 对 4", "empty": "空场面对 5 单位",
    "combined": "场面、血量、手牌及圣水均落后", "weak_spots": "1 对 4，但对手单位残血",
}


def key(t):
    return (t["pool"], t["ai"], t["scenario"], t["trailer_next"], t["seed"], t["trailer_player"])


def compare(trials, predicate, variant="action", repetitions=4000):
    indexed = {rule: {} for rule in ("legacy", variant)}
    for t in trials:
        if predicate(t) and t["variant"] in indexed:
            indexed[t["variant"]][key(t)] = t
    shared = sorted(set(indexed["legacy"]) & set(indexed[variant]))
    if not shared:
        return None
    pairs = [(indexed["legacy"][k], indexed[variant][k]) for k in shared]
    clusters = collections.defaultdict(list)
    for a, b in pairs:
        clusters[a["seed"]].append((int(a["outcome"] == "comeback"), int(b["outcome"] == "comeback")))
    seed_values = [tuple(sum(x[i] for x in xs) / len(xs) for i in (0, 1)) for xs in clusters.values()]
    rng = random.Random(191731)
    boot = []
    for _ in range(repetitions):
        sampled = rng.choices(seed_values, k=len(seed_values))
        boot.append(sum(b - a for a, b in sampled) / len(sampled))
    boot.sort()
    rates = [sum(t[i]["outcome"] == "comeback" for t in pairs) / len(pairs) for i in (0, 1)]
    means = [sum(t[i]["turns"] for t in pairs) / len(pairs) for i in (0, 1)]
    result = {
        "variant": variant, "pairs": len(pairs), "seed_clusters": len(clusters),
        "legacy_rate": rates[0], "action_rate": rates[1], "difference": rates[1] - rates[0],
        "difference_ci95": [boot[int(.025 * (repetitions - 1))], boot[int(.975 * (repetitions - 1))]],
        "legacy_mean_turns": means[0], "action_mean_turns": means[1],
        "legacy_draws": sum(a["outcome"] == "draw" for a, b in pairs),
        "action_draws": sum(b["outcome"] == "draw" for a, b in pairs),
        "flipped_to_win": sum(a["outcome"] != "comeback" and b["outcome"] == "comeback" for a, b in pairs),
        "flipped_to_loss": sum(a["outcome"] == "comeback" and b["outcome"] != "comeback" for a, b in pairs),
    }
    for side, i in [("legacy", 0), ("action", 1)]:
        for role in ("leader", "trailer"):
            metric = [p[i][role] for p in pairs]
            turns = sum(m["turns"] for m in metric)
            result[f"{side}_{role}_actions_per_turn"] = sum(m["unit_actions"] + m["auto_actions"] for m in metric) / max(1, turns)
            result[f"{side}_{role}_blocked_turn_rate"] = sum(m["blocked_turns"] for m in metric) / max(1, turns)
            result[f"{side}_{role}_ap_elixir_per_turn"] = sum(m["ap_elixir"] for m in metric) / max(1, turns)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+")
    parser.add_argument("--output", default="artifacts/comeback-analysis")
    args = parser.parse_args()
    destination = Path(args.output)
    destination.mkdir(parents=True, exist_ok=True)
    trials, reports = [], []
    for filename in args.reports:
        report = json.loads(Path(filename).read_text(encoding="utf-8"))
        reports.append(report)
        for t in report["trials"]:
            if not t["stable"]:
                raise ValueError(f"Invalid trial in {filename}: {t}")
            t["ai"] = report["ai"]
            trials.append(t)
    summary = {"games": len(trials), "unstable": 0, "draws": sum(t["outcome"] == "draw" for t in trials), "standard": [], "local": [], "initiative": [], "sensitivity": []}
    for scenario in LABELS:
        row = compare(trials, lambda t: t["pool"] != "local" and t["scenario"] == scenario)
        if row: summary["standard"].append({"scenario": scenario, **row})
        row = compare(trials, lambda t: t["pool"] == "local" and t["scenario"] == scenario)
        if row: summary["local"].append({"scenario": scenario, **row})
    for pool in sorted({t["pool"] for t in trials}):
        for scenario in LABELS:
            for next_actor in (True, False):
                row = compare(trials, lambda t: t["pool"] == pool and t["scenario"] == scenario and t["trailer_next"] == next_actor, repetitions=1000)
                if row: summary["initiative"].append({"pool": pool, "scenario": scenario, "trailer_next": next_actor, **row})
    variants = sorted({t["variant"] for t in trials} - {"legacy"})
    sensitivity_seeds = {t["seed"] for t in trials if t["variant"] not in ("legacy", "action")}
    for variant in variants:
        for scenario in ("medium", "empty", "combined"):
            row = compare(trials, lambda t: t["pool"] != "local" and t["scenario"] == scenario and (not sensitivity_seeds or t["seed"] in sensitivity_seeds), variant)
            if row: summary["sensitivity"].append({"scenario": scenario, **row})
    source_files = ["ComebackBenchmark.gd", "GameState.gd", "BattleAiPlanner.gd", "BattleSearch.gd", "SkillEngine.gd", "CardData.gd", "CardDatabase.gd"]
    summary["source_sha256"] = {name: hashlib.sha256(Path(name).read_bytes()).hexdigest() for name in source_files}
    (destination / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    for section in ("standard", "local", "initiative", "sensitivity"):
        rows = summary[section]
        if rows:
            with (destination / f"{section}.csv").open("w", encoding="utf-8-sig", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
    _plot(summary, destination)
    for section in ("standard", "local", "sensitivity"):
        print(section)
        for row in summary[section]:
            lo, hi = row["difference_ci95"]
            print(f"  {row['scenario']:12} {row['variant']:10} {row['legacy_rate']:.1%} -> {row['action_rate']:.1%} diff={row['difference']:+.1%} CI=[{lo:+.1%},{hi:+.1%}] turns={row['legacy_mean_turns']:.1f}->{row['action_mean_turns']:.1f}")
    print(f"games={summary['games']} unstable={summary['unstable']} draws={summary['draws']}")


def _plot(summary, destination):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.font_manager import FontProperties
    font = FontProperties(fname="C:/Windows/Fonts/msyh.ttc")
    rows = summary["standard"]
    fig, ax = plt.subplots(figsize=(10, 5.5))
    y = list(range(len(rows)))
    ax.barh([i + .17 for i in y], [100 * r["legacy_rate"] for r in rows], height=.3, label="原行动规则", color="#8492a6")
    ax.barh([i - .17 for i in y], [100 * r["action_rate"] for r in rows], height=.3, label="当前行动力", color="#4aa59b")
    for i, r in enumerate(rows):
        ax.text(r["legacy_rate"] * 100 + .5, i + .17, f"{r['legacy_rate']:.1%}", va="center", fontsize=10)
        ax.text(r["action_rate"] * 100 + .5, i - .17, f"{r['action_rate']:.1%}", va="center", fontsize=10)
    ax.set_yticks(y, [LABELS[r["scenario"]] for r in rows], fontproperties=font)
    ax.invert_yaxis()
    ax.set_xlim(0, 65)
    ax.set_xlabel("指定劣势方最终获胜比例（%）；均势行为参考组", fontproperties=font)
    ax.set_title("中盘续局：行动力对翻盘率的影响", fontproperties=font, fontsize=16, pad=16)
    ax.legend(prop=font, frameon=False, loc="lower right")
    ax.spines[["top", "right"]].set_visible(False)
    ax.xaxis.grid(True, alpha=.15)
    ax.set_axisbelow(True)
    fig.text(.5, .02, "标准牌池；每条规则、每个局面 512 局。非真人胜率，非自然形成劣势的总体估计。", ha="center", fontproperties=font, fontsize=9, color="#556070")
    fig.tight_layout(rect=(0, .06, 1, 1))
    fig.savefig(destination / "comeback-rates.png", dpi=180)
    fig.savefig(destination / "comeback-rates.svg")
    plt.close(fig)


if __name__ == "__main__":
    main()

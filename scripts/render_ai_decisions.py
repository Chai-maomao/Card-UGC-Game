"""Render a Godot-verified decision trace as an offline, interactive report."""
import argparse
import html
import json
from pathlib import Path


PAGE = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cardex · 行动诊断</title>
<style>
:root{color-scheme:dark;--bg:#0e1116;--panel:#1b1f28;--soft:#21252e;--gold:#e6bd66;--text:#f2f0e3;--muted:#aeb8c7;--line:#3c3a34;--blue:#5c85b8}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 "Segoe UI","Microsoft YaHei",sans-serif}.app{height:100dvh;padding:20px;display:flex;flex-direction:column;gap:12px}header{display:flex;align-items:center;justify-content:space-between;gap:16px}h1{font-size:23px;margin:0;letter-spacing:.04em}h1 span{color:var(--gold)}a{color:var(--gold)}.muted{color:var(--muted)}.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.stat{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:10px 15px}.stat strong{font-size:22px;color:var(--gold);display:block}.stat span{color:var(--muted);font-size:12px}.tools{display:flex;gap:10px;align-items:center;flex-wrap:wrap}input,select,button{font:inherit;border:1px solid var(--line);background:var(--panel);color:var(--text);border-radius:8px;padding:8px 10px}input[type=search]{flex:1;min-width:180px}label{cursor:pointer}input[type=checkbox]{accent-color:var(--gold)}.note{font-size:12px;color:var(--muted);margin:0}.workspace{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(0,1fr);gap:12px;flex:1;min-height:0}.panel{background:var(--panel);border:1px solid var(--line);border-radius:12px;overflow:auto}.list-head{padding:10px 14px;background:var(--soft);position:sticky;top:0;z-index:2;font-weight:600}table{border-collapse:collapse;width:100%;font-size:13px}th{background:var(--soft);position:sticky;top:40px;color:var(--muted);text-align:left;font-size:12px}th,td{padding:10px 12px;border-bottom:1px solid #323641;vertical-align:top}tr{cursor:pointer}tr:hover,tr.selected{background:#3b3221}tr:focus-visible{outline:2px solid var(--gold);outline-offset:-2px}.source{color:var(--text);overflow-wrap:anywhere}.tag{font-size:11px;color:var(--gold);white-space:nowrap}.detail{padding:16px}.detail h2{margin:0 0 8px;font-size:18px}.detail h3{font-size:13px;color:var(--gold);margin:18px 0 7px}.detail p{margin:5px 0;overflow-wrap:anywhere}.detail pre{font:12px/1.6 Consolas,monospace;background:var(--bg);padding:10px;border-radius:8px;white-space:pre-wrap;overflow-wrap:anywhere}.resource{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.resource div{background:var(--bg);padding:10px;border-radius:8px;font-size:12px}.empty{padding:24px;color:var(--muted)}details summary{cursor:pointer;color:var(--muted)}.hash{font:11px/1.5 Consolas,monospace;word-break:break-all}.foot{font-size:11px;color:var(--muted)}@media(max-width:760px){.app{height:auto;min-height:100dvh;padding:12px}.workspace{grid-template-columns:1fr}.panel{max-height:65vh}.stats{grid-template-columns:repeat(2,minmax(0,1fr))}header{align-items:flex-start}.tools{font-size:12px}}
</style>
<main class="app"><header><div><h1><span>CARDEX</span> · 行动诊断</h1><div class="muted" id="subtitle"></div></div><a href="__JSON_LINK__" download>下载原始报告</a></header>
<section class="stats" aria-label="回放概况"><div class="stat"><strong id="decisions"></strong><span>决策 / 合并清理步骤</span></div><div class="stat"><strong id="turns"></strong><span>玩家回合</span></div><div class="stat"><strong id="flags"></strong><span>主动未观测效果</span></div><div class="stat"><strong>已核对</strong><span id="steps"></span></div></section>
<section class="tools" aria-label="筛选"><input id="search" type="search" placeholder="搜索卡名、行动或理由" aria-label="搜索卡名、行动或理由"><select id="player" aria-label="玩家"><option value="">所有玩家</option><option value="1">玩家 1</option><option value="2">玩家 2</option></select><select id="action" aria-label="行动类型"><option value="">所有行动</option><option value="activate">主动技能</option><option value="attack">普攻</option><option value="summon">部署</option><option value="cast">法术</option><option value="attach">寄生</option><option value="end_turn">结束回合</option></select><label><input id="flagged" type="checkbox"> 仅看未观测效果</label><button id="reset">重置</button></section>
<p class="note">原决策理由与当前启发评分分开显示。未观测效果只表示这次结算没有卡牌、血量或资源变化；不能等同于没有战略价值。<span id="version-note"></span></p>
<section class="workspace"><div class="panel"><div class="list-head" id="count"></div><table><thead><tr><th>回合</th><th>行动与来源</th><th>原评分</th></tr></thead><tbody id="rows"></tbody></table><div id="empty" class="empty" hidden>没有符合筛选条件的行动。</div></div><aside class="panel detail" id="detail" aria-label="行动详情"></aside></section><div class="foot">本报告由 Godot 对录制指令逐步重放核对后生成；页面只展示结果，不运行 AI、不推断翻盘率。</div></main>
<script type="application/json" id="trace">__TRACE__</script><script>
const data=JSON.parse(document.getElementById('trace').textContent), $=id=>document.getElementById(id);
const names={activate:'主动技能',attack:'普攻',summon:'部署',cast:'法术',attach:'寄生',end_turn:'结束回合',discard:'退场',draw:'抽牌'};
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=String(text);if(cls)e.className=cls;return e};
const fmt=n=>n===null||n===undefined?'未录制':Number(n).toFixed(1);
let selected=data.rows[0]?.index;
$('decisions').textContent=data.summary.decisions;$('turns').textContent=data.summary.player_turns;$('flags').textContent=data.summary.activations_without_observed_payload;$('steps').textContent=data.summary.recorded_steps+' 个指令哈希';
$('subtitle').textContent=`${data.metadata.pool||'自定义局面'} · ${data.metadata.ai||'录制对局'} · 种子 ${data.metadata.seed??'未记录'}`;
const same=data.recorded_source_sha256['BattleAiPlanner.gd']===data.current_source_sha256['BattleAiPlanner.gd'];$('version-note').textContent=same?' 本次评分使用同一 AI 源码。':' 本次评分的 AI 源码与录制时不同。';
function section(root,title,value){root.append(el('h3',title));root.append(el('pre',typeof value==='string'?value:JSON.stringify(value,null,2)));}
function show(row){const root=$('detail');root.replaceChildren();if(!row){root.append(el('p','请选择一个行动。','muted'));return;}root.append(el('h2',`${row.index} · ${names[row.action.type]||row.action.type}`));root.append(el('p',`回合 ${row.turn} · 玩家 ${row.player} · ${row.source.name||'回合结算'}`));root.append(el('p',row.activation_without_observed_payload?'本次主动未观测到卡牌或资源效果':'已记录结算变化','tag'));root.append(el('p',`原评分 ${fmt(row.recorded_score)} · 当前启发评分 ${fmt(row.current_assessment.score)}`));
const resources=el('div',undefined,'resource');for(const p of ['1','2']){const a=row.before.resources[p],b=row.after.resources[p];resources.append(el('div',`玩家 ${p}\n圣水 ${a.mana}+${a.temporary_mana}临时 → ${b.mana}+${b.temporary_mana}临时\n行动力 ${a.ap} → ${b.ap}\n已行动 ${a.actions_taken} → ${b.actions_taken}`));resources.lastChild.style.whiteSpace='pre-line';}root.append(resources);
section(root,'原决策理由',row.recorded_factors.length?row.recorded_factors.join('\n'):'没有录制理由，可能是手动指令。');section(root,'当前启发评分理由',row.current_assessment.factors?.join('\n')||'此指令不参与 AI 评分');
const payment=row.events.filter(e=>e.kind==='payment');section(root,'实际费用',payment.length?payment.map(e=>`玩家${e.source_player} ${e.action}：${e.points}行动力 / ${e.mana}圣水（临时${e.temporary_mana}）`).join('\n'):'没有付款事件');section(root,'实际事件贡献（包含双方连锁）',row.metrics_delta);
section(root,'当前前五候选（启发评分，不是两步搜索结果）',row.alternatives.map(a=>`${names[a.action.type]||a.action.type} ${JSON.stringify(a.action)}：${fmt(a.score)}`).join('\n'));
const details=el('details');details.append(el('summary','查看指令、前后战场与哈希'));section(details,'录制指令',row.action);section(details,'战场：执行前',row.before.board);section(details,'战场：执行后',row.after.board);details.append(el('p',`指令 ${row.step_start}–${row.step_end} · ${row.hash}`,'hash'));root.append(details);}
function render(){const q=$('search').value.trim().toLowerCase(),p=$('player').value,a=$('action').value,f=$('flagged').checked;const rows=data.rows.filter(r=>(!p||String(r.player)===p)&&(!a||r.action.type===a)&&(!f||r.activation_without_observed_payload)&&(!q||JSON.stringify([r.source.name,r.action.type,names[r.action.type],r.recorded_factors,r.turn]).toLowerCase().includes(q)));if(!rows.some(r=>r.index===selected))selected=rows[0]?.index;$('rows').replaceChildren();$('count').textContent=`${rows.length} / ${data.rows.length} 个决策`;$('empty').hidden=rows.length!==0;for(const row of rows){const tr=el('tr');tr.tabIndex=0;if(row.index===selected)tr.className='selected';tr.append(el('td',`${row.turn} · P${row.player}`));const source=el('td');source.append(el('div',names[row.action.type]||row.action.type));source.append(el('div',row.source.name||'回合结算','source'));if(row.activation_without_observed_payload)source.append(el('span','未观测效果','tag'));tr.append(source);tr.append(el('td',fmt(row.recorded_score)));const select=()=>{selected=row.index;render();};tr.addEventListener('click',select);tr.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select();}});$('rows').append(tr);}show(rows.find(r=>r.index===selected));}
for(const id of ['search','player','action','flagged'])$(id).addEventListener('input',render);$('reset').addEventListener('click',()=>{$('search').value='';$('player').value='';$('action').value='';$('flagged').checked=false;render();});render();
</script></html>'''


def render(source: Path, destination: Path) -> None:
    if source.resolve() == destination.resolve():
        raise ValueError("HTML output must not overwrite the trace JSON")
    data = json.loads(source.read_text(encoding="utf-8"))
    if data.get("version") != 1 or data.get("kind") != "cardex_ai_decisions":
        raise ValueError("Unsupported trace report")
    rows, summary = data["rows"], data["summary"]
    if len(rows) != summary["decisions"]:
        raise ValueError("Decision count differs from report")
    if sum(bool(r["activation_without_observed_payload"]) for r in rows) != summary["activations_without_observed_payload"]:
        raise ValueError("Observed-effect count differs from report")
    if rows and rows[-1]["hash"] != data["final_hash"]:
        raise ValueError("Final trace row hash differs from report")
    encoded = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    # UGC names/reasons are data, including literal closing-script text.
    encoded = encoded.replace("&", r"\u0026").replace("<", r"\u003c").replace(">", r"\u003e")
    from os.path import relpath
    from urllib.parse import quote
    link = quote(Path(relpath(source.resolve(), destination.parent.resolve())).as_posix(), safe="/")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Substitute only template slots; UGC text and filenames may contain them too.
    head, tail = PAGE.split("__TRACE__", 1)
    page = head.replace("__JSON_LINK__", html.escape(link, quote=True), 1) + encoded + tail
    destination.write_text(page, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/ai-decisions/index.html"))
    args = parser.parse_args()
    render(args.trace, args.output)
    print(f"AI_DECISION_REPORT_DONE {args.output}")


if __name__ == "__main__":
    main()

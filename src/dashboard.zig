// ZigLens dashboard HTML — Spec Sec.22-24, dark-first developer aesthetic.
// Served by `ziglens serve` on 127.0.0.1 only. Static + fetches /api/v1/*.
// Features: hash deep-links (#/security), theme toggle, localStorage
// bookmarks/saved views, '?' shortcut overlay, treemap + cluster tables.

const dashboard_html =
    \\<!DOCTYPE html>
    \\<html lang="en" data-theme="dark">
    \\<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    \\<title>ZigLens — Codebase Intelligence</title>
    \\<style>
    \\:root{--bg:#0d1117;--panel:#161b22;--border:#21262d;--fg:#e6edf3;--muted:#8b949e;--acc:#58a6ff;--ok:#3fb950;--warn:#d29922;--bad:#f85149}
    \\html[data-theme="light"]{--bg:#ffffff;--panel:#f6f8fa;--border:#d0d7de;--fg:#1f2328;--muted:#59636e;--acc:#0969da;--ok:#1a7f37;--warn:#9a6700;--bad:#d1242c}
    \\*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:13px/1.5 -apple-system,Segoe UI,Roboto,monospace}
    \\header{display:flex;gap:10px;align-items:center;padding:10px 16px;border-bottom:1px solid var(--border);position:sticky;top:0;background:var(--bg);z-index:5}
    \\.logo{font-weight:700;letter-spacing:.5px}.logo span{color:var(--acc)}
    \\#q{flex:1;max-width:520px;background:var(--panel);border:1px solid var(--border);color:var(--fg);padding:6px 10px;border-radius:6px}
    \\button.hbtn{background:var(--panel);border:1px solid var(--border);color:var(--fg);border-radius:6px;padding:5px 10px;cursor:pointer}
    \\main{display:grid;grid-template-columns:220px 1fr;min-height:calc(100vh - 49px)}
    \\nav{border-right:1px solid var(--border);padding:12px}nav a{display:block;padding:6px 10px;border-radius:6px;color:var(--muted);text-decoration:none;cursor:pointer}nav a.on,nav a:hover{background:var(--panel);color:var(--fg)}
    \\nav h4{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin:14px 4px 6px}
    \\section{padding:16px;max-width:1100px}
    \\.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px;margin:12px 0}
    \\.card{background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:10px 12px}.card b{font-size:20px;display:block}.card span{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.4px}
    \\table{width:100%;border-collapse:collapse;margin-top:10px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--border);font-size:12px}th{color:var(--muted);text-transform:uppercase;font-size:11px}
    \\.pill{display:inline-block;padding:1px 8px;border-radius:99px;border:1px solid var(--border);font-size:11px}.pill.high,.pill.CRITICAL,.pill.HIGH{color:var(--bad);border-color:var(--bad)}.pill.MEDIUM{color:var(--warn);border-color:var(--warn)}.pill.LOW,.pill.INFO{color:var(--muted)}
    \\.tm{display:flex;flex-wrap:wrap;gap:4px;margin-top:10px}.tm div{border:1px solid var(--border);border-radius:4px;padding:4px 6px;font-size:11px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    \\#help{position:fixed;inset:0;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.55);z-index:20}#help.on{display:flex}#help div{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:18px 22px;max-width:420px}
    \\footer{color:var(--muted);padding:12px 16px;border-top:1px solid var(--border);font-size:11px}
    \\@media(max-width:800px){main{grid-template-columns:1fr}nav{display:flex;overflow:auto}}
    \\</style></head>
    \\<body>
    \\<header><div class="logo">ZIG<span>LENS</span></div><input id="q" placeholder="Ctrl+K — search files, symbols, findings…"><button class="hbtn" id="star" title="Bookmark this view">*</button><button class="hbtn" id="theme" title="Toggle theme">theme</button><button class="hbtn" id="helpbtn" title="Shortcuts (?)">?</button><div id="health" class="pill">loading…</div></header>
    \\<main><nav id="nav">
    \\<a data-p="overview" class="on">Overview</a><a data-p="architecture">Architecture</a><a data-p="dependencies">Dependencies</a><a data-p="treemap">Treemap</a><a data-p="symbols">Symbols</a><a data-p="deadcode">Dead Code</a><a data-p="complexity">Complexity</a><a data-p="security">Security</a><a data-p="git">Git</a><a data-p="impact">Impact</a><a data-p="reports">Reports</a><a data-p="privacy">Privacy</a>
    \\<h4>Bookmarks</h4><div id="bm"></div>
    \\</nav><section><h2 id="title">Overview</h2><div id="body"><div class="cards" id="cards"></div><div id="extra"></div></div></section></main>
    \\<div id="help"><div><h3>Shortcuts</h3><table><tr><td>Ctrl/⌘ + K</td><td>Global search</td></tr><tr><td>Esc</td><td>Close / blur</td></tr><tr><td>R</td><td>Refresh view</td></tr><tr><td>T</td><td>Toggle theme</td></tr><tr><td>?</td><td>This panel</td></tr></table><p style="color:var(--muted)">Deep links: #/security, #/dependencies … — shareable locally.</p><button class="hbtn" id="helpx">Close</button></div></div>
    \\<footer>Local-first · offline · read-only · <span id="meta"></span> · <a href="/api/v1/project" style="color:var(--acc)">JSON API</a></footer>
    \\<script>
    \\const $=s=>document.querySelector(s);
    \\let P={};
    \\const PAGES=['overview','architecture','dependencies','treemap','symbols','deadcode','complexity','security','git','impact','reports','privacy'];
    \\async function j(u){const r=await fetch(u);return r.json();}
    \\function themeApply(){const t=localStorage.getItem('zl_theme')||'dark';document.documentElement.setAttribute('data-theme',t);}
    \\async function load(){themeApply();try{P=await j('/api/v1/project');}catch(e){$('#body').innerHTML='<p>Run <code>ziglens scan</code> first, then <code>ziglens serve</code> in project root.</p>';return;}
    \\$('#meta').textContent=(P.project||'')+' · '+((P.files||[]).length)+' files';
    \\$('#health').textContent='health '+(P.health?P.health.overall:'?');
    \\renderBm();const h=(location.hash||'').replace('#/','');render(PAGES.indexOf(h)>=0?h:'overview');}
    \\function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
    \\function go(p){if(('#/'+p)===location.hash){render(p);}else{location.hash='#/'+p;}}
    \\window.onhashchange=function(){const h=(location.hash||'').replace('#/','');if(PAGES.indexOf(h)>=0)render(h);};
    \\async function render(p){$('#title').textContent=p.charAt(0).toUpperCase()+p.slice(1);
    \\document.querySelectorAll('#nav a').forEach(function(a){a.classList.toggle('on',a.dataset.p===p);});
    \\if(p==='overview'){const c=$('#cards');c.innerHTML='';
    \\const cards=[['Files',(P.files||[]).length],['Symbols',P.symbols||0],['Dependencies',(P.dependencies||[]).length],['Cycles',(P.cycles||[]).length],['Arch score',P.health?P.health.architecture:'?'],['Security',P.security_count||0],['Dead code',P.deadcode_count||0]];
    \\for(let i=0;i<cards.length;i++){const d=document.createElement('div');d.className='card';d.innerHTML='<b>'+esc(cards[i][1])+'</b><span>'+esc(cards[i][0])+'</span>';c.appendChild(d);}
    \\$('#extra').innerHTML='<h3>Top complexity</h3>'+tbl((P.top_complexity||[]).map(function(x){return [x.path,x.complexity,x.loc];}));}
    \\else if(p==='dependencies'){const d=await j('/api/v1/graph').catch(function(){return null;});$('#cards').innerHTML='';if(!d){$('#extra').innerHTML='no data';}else{let h='<h3>Directory clusters</h3><table><tr><th>group</th><th>files</th></tr>'+((d.groups||[]).map(function(g){return '<tr><td>'+esc(g.name)+'</td><td>'+esc(g.files)+'</td></tr>';}).join(''))+'</table><h3>Group edges</h3><table><tr><th>from</th><th>to</th></tr>'+((d.group_edges||[]).map(function(e){return '<tr><td>'+esc(e.from)+'</td><td>'+esc(e.to)+'</td></tr>';}).join(''))+'</table>';if(d.truncated)h+='<p style="color:var(--muted)">Truncated to 500 nodes / 1000 edges — filter via search.</p>';h+='<h3>Nodes (table alternative)</h3><table><tr><th>id</th><th>path</th><th>group</th></tr>'+((d.nodes||[]).slice(0,100).map(function(n){return '<tr><td>'+esc(n.id)+'</td><td>'+esc(n.path)+'</td><td>'+esc(n.group)+'</td></tr>';}).join(''))+'</table>';$('#extra').innerHTML=h;}}
    \\else if(p==='treemap'){const d=await j('/api/v1/treemap').catch(function(){return null;});$('#cards').innerHTML='';if(!d){$('#extra').innerHTML='no data';}else{let mx=1;(d.files||[]).forEach(function(f){if(f.loc>mx)mx=f.loc;});let h='<h3>Codebase treemap (size = LOC, heat = complexity)</h3><div class="tm">'+((d.files||[]).slice(0,200).map(function(f){const w=Math.max(4,Math.round(f.loc*100/mx));const a=Math.min(0.9,f.cx/30);return '<div title="'+esc(f.path)+' cx '+esc(f.cx)+'" style="width:'+w+'%;background:rgba(210,153,34,'+a.toFixed(2)+')">'+esc(f.path)+'</div>';}).join(''))+'</div><h3>Groups</h3><table><tr><th>group</th><th>files</th><th>loc</th><th>cx</th></tr>'+((d.groups||[]).map(function(g){return '<tr><td>'+esc(g.name)+'</td><td>'+esc(g.files)+'</td><td>'+esc(g.loc)+'</td><td>'+esc(g.cx)+'</td></tr>';}).join(''))+'</table>';$('#extra').innerHTML=h;}}
    \\else{const d=await j('/api/v1/'+p).catch(function(){return null;});$('#cards').innerHTML='';$('#extra').innerHTML='<pre>'+esc(JSON.stringify(d,null,2))+'</pre>';}}
    \\function tbl(rows){return '<table><tr><th>path</th><th>complexity</th><th>loc</th></tr>'+rows.map(function(r){return '<tr><td>'+esc(r[0])+'</td><td>'+esc(r[1])+'</td><td>'+esc(r[2])+'</td></tr>';}).join('')+'</table>';}
    \\function renderBm(){let b=[];try{b=JSON.parse(localStorage.getItem('zl_bm')||'[]');}catch(e){b=[];}$('#bm').innerHTML=b.map(function(x,i){return '<a data-i="'+i+'">'+esc(x.p)+' '+esc(x.q||'')+'</a>';}).join('')||'<span style="color:var(--muted)">none yet — press *</span>';document.querySelectorAll('#bm a').forEach(function(a){a.onclick=function(){const x=b[+a.dataset.i];if(x.q)$('#q').value=x.q;go(x.p);};});}
    \\document.querySelectorAll('#nav a').forEach(function(a){a.onclick=function(){go(a.dataset.p);};});
    \\$('#theme').onclick=function(){localStorage.setItem('zl_theme',document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark');themeApply();};
    \\$('#helpbtn').onclick=function(){$('#help').classList.add('on');};
    \\$('#helpx').onclick=function(){$('#help').classList.remove('on');};
    \\$('#star').onclick=function(){let b=[];try{b=JSON.parse(localStorage.getItem('zl_bm')||'[]');}catch(e){b=[];}const t=$('#title').textContent.toLowerCase();b.push({p:t,q:$('#q').value});localStorage.setItem('zl_bm',JSON.stringify(b.slice(-20)));renderBm();};
    \\document.addEventListener('keydown',function(e){const inQ=document.activeElement===$('#q');if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'){e.preventDefault();$('#q').focus();return;}if(e.key==='Escape'){$('#help').classList.remove('on');if(inQ)$('#q').blur();return;}if(inQ)return;if(e.key==='?'){$('#help').classList.toggle('on');}else if(e.key==='r'||e.key==='R'){const h=(location.hash||'').replace('#/','');render(PAGES.indexOf(h)>=0?h:'overview');}else if(e.key==='t'||e.key==='T'){$('#theme').click();}});
    \\$('#q').addEventListener('input',async function(e){const q=e.target.value;if(q.length<2)return;const r=await j('/api/v1/search?q='+encodeURIComponent(q)).catch(function(){return null;});if(r)$('#extra').innerHTML='<pre>'+esc(JSON.stringify(r,null,2))+'</pre>';});
    \\load();
    \\</script></body></html>
;

pub fn html() []const u8 {
    return dashboard_html;
}

// ZigLens dashboard — Spec Sec.22-24, 54-55, 165.
// Dark-first developer console: dense tables, SVG dependency graph with
// pan/zoom, treemap, hash deep-links, EN/ID, themes, density, bookmarks.
// No external assets (offline single binary), no gradients, no emoji.

const dashboard_html =
    \\<!DOCTYPE html>
    \\<html lang="en" data-theme="dark">
    \\<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    \\<title>ZigLens — Codebase Intelligence</title>
    \\<style>
    \\:root{--bg:#0c0e12;--panel:#13161c;--panel2:#181c23;--border:#242a33;--fg:#dbe2ec;--muted:#8a94a3;--faint:#5b6472;--acc:#4c9aff;--ok:#3fb950;--warn:#d29922;--bad:#f85149;--fs:13px;--pad:16px}
    \\html[data-theme="light"]{--bg:#f4f6f8;--panel:#ffffff;--panel2:#eef1f4;--border:#d7dde4;--fg:#1c2330;--muted:#5d6b7d;--faint:#93a0b1;--acc:#0b62d6;--ok:#1a7f37;--warn:#9a6700;--bad:#cf222e}
    \\body.comfy{--fs:14px;--pad:22px}
    \\*{box-sizing:border-box}html,body{margin:0;padding:0}
    \\body{background:var(--bg);color:var(--fg);font:var(--fs)/1.55 "Cascadia Code","JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;-webkit-font-smoothing:antialiased}
    \\:focus-visible{outline:2px solid var(--acc);outline-offset:1px}
    \\header.top{display:flex;gap:8px;align-items:center;padding:8px var(--pad);border-bottom:1px solid var(--border);position:sticky;top:0;background:var(--bg);z-index:10}
    \\.mark{width:14px;height:14px;background:var(--acc);flex:none}
    \\.logo{font-weight:700;letter-spacing:1px;font-size:12px;white-space:nowrap}.logo small{color:var(--faint);font-weight:400;letter-spacing:0}
    \\#q{flex:1;max-width:560px;background:var(--panel);border:1px solid var(--border);color:var(--fg);padding:6px 10px;border-radius:4px;font:inherit}
    \\#q::placeholder{color:var(--faint)}
    \\button.hbtn{background:var(--panel);border:1px solid var(--border);color:var(--fg);border-radius:4px;padding:5px 10px;cursor:pointer;font:inherit;font-size:12px;white-space:nowrap}
    \\button.hbtn:hover{border-color:var(--acc)}
    \\main{display:grid;grid-template-columns:216px minmax(0,1fr);min-height:calc(100vh - 45px)}
    \\nav{border-right:1px solid var(--border);padding:10px;display:flex;flex-direction:column;gap:1px}
    \\nav a{display:flex;justify-content:space-between;padding:5px 10px;border-radius:4px;color:var(--muted);text-decoration:none;cursor:pointer;font-size:12px;border-left:2px solid transparent}
    \\nav a:hover{color:var(--fg);background:var(--panel)}
    \\nav a.on{color:var(--fg);background:var(--panel2);border-left-color:var(--acc)}
    \\nav a .n{color:var(--faint);font-size:11px}
    \\nav h4{color:var(--faint);font-size:10px;text-transform:uppercase;letter-spacing:1px;margin:14px 10px 4px;font-weight:400}
    \\nav .foot{margin-top:auto;padding:10px;font-size:11px;color:var(--faint)}
    \\section{padding:var(--pad);max-width:1200px;min-width:0}
    \\.crumbs{font-size:11px;color:var(--faint);margin-bottom:4px}
    \\h2{font-size:16px;margin:0 0 2px;font-weight:600}h3{font-size:12px;margin:18px 0 6px;text-transform:uppercase;letter-spacing:.6px;color:var(--muted);font-weight:600}.sub{color:var(--muted);font-size:12px;margin:0 0 8px}
    \\.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px;margin:12px 0}
    \\.card{background:var(--panel);border:1px solid var(--border);border-radius:6px;padding:10px 12px}.card b{font-size:20px;display:block;font-weight:600;font-variant-numeric:tabular-nums}.card span{color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.6px}
    \\.hbar{height:5px;background:var(--panel2);border-radius:3px;margin-top:8px;overflow:hidden}.hbar i{display:block;height:100%;border-radius:3px}
    \\table{width:100%;border-collapse:collapse;margin-top:8px;font-size:12px}th,td{text-align:left;padding:6px 10px;border-bottom:1px solid var(--border);vertical-align:top}th{color:var(--faint);text-transform:uppercase;font-size:10px;letter-spacing:.6px;font-weight:600}tbody tr:hover{background:var(--panel)}td.num,th.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
    \\.pill{display:inline-block;padding:1px 9px;border-radius:99px;border:1px solid var(--border);font-size:11px;white-space:nowrap}
    \\.sev{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:7px;vertical-align:1px}
    \\.s-crit{background:var(--bad)}.s-high{background:var(--bad)}.s-med{background:var(--warn)}.s-low{background:var(--muted)}.s-info{background:var(--faint)}
    \\.pill.CRITICAL,.pill.HIGH{color:var(--bad);border-color:var(--bad)}.pill.MEDIUM{color:var(--warn);border-color:var(--warn)}.pill.LOW,.pill.INFO{color:var(--muted)}
    \\.toolbar{display:flex;gap:8px;align-items:center;margin:10px 0;flex-wrap:wrap}
    \\.toolbar input,.toolbar select{background:var(--panel);border:1px solid var(--border);color:var(--fg);padding:5px 9px;border-radius:4px;font:inherit;font-size:12px}
    \\.gwrap{border:1px solid var(--border);border-radius:6px;background:var(--panel);overflow:hidden}
    \\.gwrap:fullscreen{background:var(--bg);padding:12px}
    \\svg.graph{display:block;width:100%;height:480px;cursor:grab;touch-action:none}
    \\svg.graph text{fill:var(--fg);font-size:11px;font-family:inherit}
    \\svg.graph .gsub{fill:var(--muted);font-size:10px}
    \\svg.graph rect.node{fill:var(--panel2);stroke:var(--border);rx:4}
    \\svg.graph g.node:hover rect.node{stroke:var(--acc)}
    \\svg.graph g.node.sel rect.node{stroke:var(--acc);stroke-width:2}
    \\svg.graph line.edge{stroke:var(--faint);stroke-width:1}
    \\svg.graph line.edge.hot{stroke:var(--acc)}
    \\#gdetail{border-top:1px solid var(--border);padding:10px 14px;font-size:12px;display:none}
    \\#gdetail.on{display:block}
    \\#gdetail ul{margin:4px 0;padding-left:18px;color:var(--muted)}
    \\.tm{display:flex;flex-wrap:wrap;gap:4px;margin-top:10px}.tm div{border:1px solid var(--border);border-radius:4px;padding:4px 6px;font-size:11px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;background:var(--panel)}
    \\.tm .gh{width:100%;border:none;background:none;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.6px;padding:8px 0 0}
    \\.empty{border:1px dashed var(--border);border-radius:6px;padding:22px;color:var(--muted);margin-top:10px;font-size:12px}
    \\.empty b{color:var(--fg)}
    \\ol.rec{margin:8px 0;padding-left:22px;font-size:12px}ol.rec li{margin:5px 0}
    \\#help{position:fixed;inset:0;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.6);z-index:20}#help.on{display:flex}#help div{background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:18px 22px;max-width:440px}
    \\footer{color:var(--faint);padding:10px var(--pad);border-top:1px solid var(--border);font-size:11px;display:flex;gap:14px}
    \\footer a{color:var(--muted)}
    \\@media(max-width:820px){main{grid-template-columns:1fr}nav{flex-direction:row;overflow:auto;border-right:none;border-bottom:1px solid var(--border)}nav h4,nav .foot{display:none}}
    \\</style></head>
    \\<body>
    \\<header class="top"><span class="mark"></span><span class="logo">ZIGLENS <small>local code x-ray</small></span><input id="q" autocomplete="off" spellcheck="false"><button class="hbtn" id="star" title="Bookmark this view">*</button><button class="hbtn" id="lang" title="English / Indonesia">ID</button><button class="hbtn" id="dens" title="Toggle density">Aa</button><button class="hbtn" id="theme" title="Toggle theme">theme</button><button class="hbtn" id="helpbtn" title="Shortcuts (?)">?</button><span id="health" class="pill">…</span></header>
    \\<main><nav id="nav" aria-label="Sections">
    \\<a data-p="overview">Overview</a><a data-p="architecture">Architecture</a><a data-p="dependencies">Dependencies</a><a data-p="treemap">Treemap</a><a data-p="symbols">Symbols</a><a data-p="deadcode">Dead Code</a><a data-p="complexity">Complexity</a><a data-p="security">Security</a><a data-p="git">Git</a><a data-p="impact">Impact</a><a data-p="reports">Reports</a><a data-p="privacy">Privacy</a>
    \\<h4 id="bmh">Bookmarks</h4><div id="bm"></div>
    \\<div class="foot">read-only · offline<br>127.0.0.1 only</div>
    \\</nav><section id="sec"><div class="crumbs" id="crumbs"></div><h2 id="title">Overview</h2><p class="sub" id="subtitle"></p><div id="body"><div class="cards" id="cards"></div><div id="extra"></div></div></section></main>
    \\<div id="help" role="dialog" aria-label="Shortcuts"><div><h3 id="helph">Shortcuts</h3><table id="helpt"></table><p style="color:var(--muted);font-size:12px" id="helpnote"></p><button class="hbtn" id="helpx">Close</button></div></div>
    \\<footer><span id="meta"></span><a href="/api/v1/project">JSON API</a><a href="/api/v1/graph">graph</a><a href="/api/v1/treemap">treemap</a></footer>
    \\<script>
    \\'use strict';
    \\const $=s=>document.querySelector(s);
    \\let P={};let CUR='overview';
    \\const PAGES=['overview','architecture','dependencies','treemap','symbols','deadcode','complexity','security','git','impact','reports','privacy'];
    \\const STR={
    \\en:{overview:'Overview',architecture:'Architecture',dependencies:'Dependencies',treemap:'Treemap',symbols:'Symbols',deadcode:'Dead Code',complexity:'Complexity',security:'Security',git:'Git',impact:'Impact',reports:'Reports',privacy:'Privacy',bookmarks:'Bookmarks',search:'Ctrl+K — search files, symbols, findings…',files:'Files',symbols_:'Symbols',deps:'Dependencies',cycles:'Cycles',archscore:'Arch score',sec_:'Security',dead_:'Dead code',topcx:'Top complexity',dircl:'Directory clusters',group:'group',from:'from',to:'to',nodes:'Nodes (table alternative)',tmap:'Codebase treemap (size = LOC, heat = complexity)',groups:'Groups',loc:'loc',cx:'cx',path:'path',complexity:'complexity',none:'none yet — press *',help_h:'Shortcuts',close:'Close',note:'Deep links: #/security … shareable locally.',trunc:'Truncated — filter via search.',sub_overview:'Project health at a glance. Every score drills down.',sub_deps:'Clustered view. Click a node for detail; drag to pan, wheel to zoom.',sub_treemap:'Area = lines of code, warmth = complexity.',sub_impact:'Pick a file, see the blast radius.',graph:'Dependency graph',depends_on:'Depends on',needed_by:'Needed by',reset:'Reset',fit_full:'Full',filtered:'matching filter',no_data:'No data for this view yet.',recs:'Top recommendations',help:[['Ctrl/⌘ + K','Global search'],['Esc','Close / blur'],['R','Refresh view'],['T','Toggle theme'],['?','This panel']]},
    \\id:{overview:'Ringkasan',architecture:'Arsitektur',dependencies:'Dependensi',treemap:'Treemap',symbols:'Simbol',deadcode:'Kode Mati',complexity:'Kompleksitas',security:'Keamanan',git:'Git',impact:'Dampak',reports:'Laporan',privacy:'Privasi',bookmarks:'Markah',search:'Ctrl+K — cari file, simbol, temuan…',files:'File',symbols_:'Simbol',deps:'Dependensi',cycles:'Siklus',archscore:'Skor arsitektur',sec_:'Keamanan',dead_:'Kode mati',topcx:'Kompleksitas tertinggi',dircl:'Klaster direktori',group:'grup',from:'dari',to:'ke',nodes:'Node (alternatif tabel)',tmap:'Treemap codebase (ukuran = LOC, panas = kompleksitas)',groups:'Grup',loc:'loc',cx:'cx',path:'jalur',complexity:'kompleksitas',none:'belum ada — tekan *',help_h:'Pintasan',close:'Tutup',note:'Deep link: #/security … bisa dibagikan lokal.',trunc:'Dipotong — filter lewat pencarian.',sub_overview:'Kesehatan project sekilas. Tiap skor bisa ditelusuri.',sub_deps:'Tampilan klaster. Klik node untuk detail; geser untuk pan, wheel untuk zoom.',sub_treemap:'Luas = baris kode, panas = kompleksitas.',sub_impact:'Pilih file, lihat radius dampak.',graph:'Graf dependensi',depends_on:'Bergantung pada',needed_by:'Dibutuhkan oleh',reset:'Atur ulang',fit_full:'Penuh',filtered:'cocok filter',no_data:'Belum ada data untuk tampilan ini.',recs:'Rekomendasi utama',help:[['Ctrl/⌘ + K','Pencarian global'],['Esc','Tutup / lepas fokus'],['R','Muat ulang tampilan'],['T','Ganti tema'],['?','Panel ini']]}};
    \\let LANG=localStorage.getItem('zl_lang')||'en';
    \\function T(k){return (STR[LANG]&&STR[LANG][k])||STR.en[k]||k;}
    \\async function j(u){const r=await fetch(u);if(!r.ok)throw new Error(r.status);return r.json();}
    \\function themeApply(){const t=localStorage.getItem('zl_theme')||'dark';document.documentElement.setAttribute('data-theme',t);}
    \\function densApply(){document.body.classList.toggle('comfy',localStorage.getItem('zl_dens')==='comfy');}
    \\async function load(){themeApply();densApply();applyLang();try{P=await j('/api/v1/project');}catch(e){$('#body').innerHTML='<div class="empty"><b>Nothing to show.</b><br>Run <code>ziglens scan</code> in a project, then <code>ziglens serve</code> there.</div>';return;}
    \\const nf=(P.files||[]).length;$('#meta').textContent=(P.project||'')+' · '+nf+' files';
    \\const ov=P.health?P.health.overall:'?';const hp=$('#health');hp.textContent='health '+ov;hp.className='pill '+(ov>=80?'LOW':ov>=60?'MEDIUM':'HIGH');
    \\renderBm();const h=(location.hash||'').replace('#/','');render(PAGES.indexOf(h)>=0?h:'overview');}
    \\function applyLang(){$('#lang').textContent=LANG==='en'?'ID':'EN';document.querySelectorAll('#nav a[data-p]').forEach(function(a){a.textContent=T(a.dataset.p);});$('#q').placeholder=T('search');$('#bmh').textContent=T('bookmarks');$('#helph').textContent=T('help_h');$('#helpx').textContent=T('close');$('#helpnote').textContent=T('note');$('#helpt').innerHTML=T('help').map(function(r){return '<tr><td><code>'+esc(r[0])+'</code></td><td>'+esc(r[1])+'</td></tr>';}).join('');render(CUR);}
    \\function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
    \\function sevDot(sev){const c=(sev==='CRITICAL'||sev==='HIGH')?'s-crit':sev==='MEDIUM'?'s-med':(sev==='LOW'||sev==='INFO')?'s-low':'s-info';return '<span class="sev '+c+'"></span>';}
    \\function go(p){if(('#/'+p)===location.hash){render(p);}else{location.hash='#/'+p;}}
    \\window.onhashchange=function(){const h=(location.hash||'').replace('#/','');if(PAGES.indexOf(h)>=0)render(h);};
    \\function subFor(p){return T('sub_'+p)||'';}
    \\async function render(p){CUR=p;$('#title').textContent=T(p);$('#crumbs').textContent='ziglens / '+T(p);
    \\$('#subtitle').textContent=subFor(p);
    \\document.querySelectorAll('#nav a').forEach(function(a){a.classList.toggle('on',a.dataset.p===p);});
    \\if(p==='overview')return renderOverview();
    \\if(p==='dependencies')return renderDeps();
    \\if(p==='treemap')return renderTreemap();
    \\if(p==='symbols')return renderSymbols();
    \\if(p==='deadcode')return renderDeadcode();
    \\if(p==='complexity')return renderComplexity();
    \\if(p==='security')return renderSecurity();
    \\if(p==='git')return renderGit();
    \\if(p==='impact')return renderImpactForm();
    \\if(p==='reports')return renderReports();
    \\if(p==='privacy')return renderPrivacy();
    \\return renderJSON('/api/v1/'+p);}
    \\async function renderJSON(u){$('#cards').innerHTML='';try{const d=await j(u);$('#extra').innerHTML='<pre>'+esc(JSON.stringify(d,null,2))+'</pre>';}catch(e){$('#extra').innerHTML='<div class="empty"><b>'+esc(T('no_data'))+'</b></div>';}}
    \\function healthBars(){const h=P.health||{};const rows=[['Architecture',h.architecture],['Maintainability',h.maintainability],['Security',h.security]];return rows.map(function(r){const v=(r[1]==null?'?':r[1]);const w=(typeof v==='number'?Math.max(0,Math.min(100,v)):0);const cls=v>=80?'var(--ok)':v>=60?'var(--warn)':'var(--bad)';return '<div class="card"><b>'+esc(v)+'</b><span>'+esc(r[0])+'</span><div class="hbar"><i style="width:'+w+'%;background:'+cls+'"></i></div></div>';}).join('');}
    \\async function renderOverview(){const c=$('#cards');c.innerHTML='';
    \\const cards=[[T('files'),(P.files||[]).length],[T('symbols_'),P.symbols||0],[T('deps'),(P.dependencies||[]).length],[T('cycles'),(P.cycles||[]).length],[T('archscore'),P.health?P.health.architecture:'?'],[T('sec_'),P.security_count||0],[T('dead_'),P.deadcode_count||0]];
    \\for(let i=0;i<cards.length;i++){const d=document.createElement('div');d.className='card';d.innerHTML='<b>'+esc(cards[i][1])+'</b><span>'+esc(cards[i][0])+'</span>';c.appendChild(d);}
    \\$('#extra').innerHTML=healthBars()+'<div class="cards" style="grid-template-columns:1fr"></div><h3>'+esc(T('recs'))+'</h3>'+recList()+'<h3>'+esc(T('topcx'))+'</h3>'+tbl(['path','complexity','loc'],(P.top_complexity||[]).map(function(x){return [x.path,x.complexity,x.loc];}));}
    \\function recList(){const r=P.recommendations||[];if(!r.length)return '<div class="empty">'+esc(T('no_data'))+'</div>';return '<ol class="rec">'+r.map(function(x){return '<li>'+esc(x)+'</li>';}).join('')+'</ol>';}
    \\function tbl(head,rows){return '<table><thead><tr>'+head.map(function(h){return '<th>'+esc(h)+'</th>';}).join('')+'</thead><tbody>'+rows.map(function(r){return '<tr>'+r.map(function(c){return '<td>'+esc(c)+'</td>';}).join('')+'</tr>';}).join('')+'</tbody></table>';}
    \\function emptyBox(){return '<div class="empty"><b>'+esc(T('no_data'))+'</b></div>';}
    \\async function renderDeps(){let d=null;try{d=await j('/api/v1/graph');}catch(e){}$('#cards').innerHTML='';if(!d||!(d.nodes||[]).length){$('#extra').innerHTML=emptyBox();return;}
    \\const groups=(d.groups||[]).map(function(g){return g.name;}).sort();
    \\$('#extra').innerHTML='<div class="toolbar"><input id="gq" placeholder="filter…"><select id="gg"><option value="">all groups</option>'+groups.map(function(g){return '<option>'+esc(g)+'</option>';}).join('')+'</select><button class="hbtn" id="gzp">+</button><button class="hbtn" id="gzm">−</button><button class="hbtn" id="gzr">'+esc(T('reset'))+'</button><button class="hbtn" id="gfs">'+esc(T('fit_full'))+'</button><span id="gcount" style="color:var(--muted);font-size:11px"></span></div><div class="gwrap" id="gw"><svg class="graph" id="gsvg" role="img" aria-label="'+esc(T('graph'))+'"></svg><div id="gdetail"></div></div><h3>'+esc(T('dircl'))+'</h3><table><thead><tr><th>'+esc(T('group'))+'</th><th class="num">'+esc(T('files'))+'</th></tr></thead><tbody>'+((d.groups||[]).map(function(g){return '<tr><td>'+esc(g.name)+'</td><td class="num">'+esc(g.files)+'</td></tr>';}).join(''))+'</tbody></table>';
    \\graphDraw(d);
    \\$('#gq').addEventListener('input',function(){graphDraw(d);});
    \\$('#gg').addEventListener('change',function(){graphDraw(d);});
    \\$('#gzp').onclick=function(){gZoom(0.8);};$('#gzm').onclick=function(){gZoom(1.25);};$('#gzr').onclick=function(){gReset();};
    \\$('#gfs').onclick=function(){const w=$('#gw');if(document.fullscreenElement)document.exitFullscreen();else if(w.requestFullscreen)w.requestFullscreen();};}
    \\let GV=null;
    \\function gZoom(f){if(!GV)return;GV.vb.w=Math.max(60,Math.min(GV.full.w*4,GV.vb.w*f));GV.vb.h=GV.vb.w*(GV.full.h/GV.full.w);gApplyVB();}
    \\function gReset(){if(!GV)return;GV.vb={x:0,y:0,w:GV.full.w,h:GV.full.h};gApplyVB();}
    \\function gApplyVB(){const s=$('#gsvg');if(s&&GV)s.setAttribute('viewBox',GV.vb.x+' '+GV.vb.y+' '+GV.vb.w+' '+GV.vb.h);}
    \\function graphDraw(d){
    \\const q=(($('#gq')||{value:''}).value||'').toLowerCase();const gf=($('#gg')||{value:''}).value||'';
    \\let nodes=(d.nodes||[]).slice();
    \\if(gf)nodes=nodes.filter(function(n){return n.group===gf;});
    \\if(q)nodes=nodes.filter(function(n){return (n.path||'').toLowerCase().indexOf(q)>=0;});
    \\const keep={};nodes.forEach(function(n){keep[n.id]=1;});
    \\const edges=(d.edges||[]).filter(function(e){return keep[e.from]&&keep[e.to];});
    \\// degree-rank cap so huge graphs stay interactive
    \\if(nodes.length>120){const deg={};nodes.forEach(function(n){deg[n.id]=0;});edges.forEach(function(e){deg[e.from]++;deg[e.to]++;});nodes.sort(function(a,b){return deg[b.id]-deg[a.id];});nodes=nodes.slice(0,120);const k2={};nodes.forEach(function(n){k2[n.id]=1;});for(let i=edges.length-1;i>=0;i--){if(!k2[edges[i].from]||!k2[edges[i].to])edges.splice(i,1);}}
    \\const byId={};nodes.forEach(function(n){byId[n.id]=n;});
    \\const indeg={};nodes.forEach(function(n){indeg[n.id]=0;});
    \\edges.forEach(function(e){indeg[e.to]++;});
    \\const depth={};nodes.forEach(function(n){depth[n.id]=0;});
    \\for(let g=0;g<500;g++){let ch=false;edges.forEach(function(e){const nd=depth[e.from]+1;if(nd>depth[e.to]){depth[e.to]=nd;ch=true;}});if(!ch)break;}
    \\const layers={};let maxD=0,maxL=0;nodes.forEach(function(n){const dd=depth[n.id];if(dd>maxD)maxD=dd;(layers[dd]=layers[dd]||[]).push(n);});
    \\Object.keys(layers).forEach(function(k){if(layers[k].length>maxL)maxL=layers[k].length;});
    \\const X=250,Y=54;const W=(maxD+1)*X+60,H=Math.max(2,maxL)*Y+30;
    \\Object.keys(layers).forEach(function(k){layers[k].forEach(function(n,i){n._x=(+k)*X+20;n._y=i*Y+16;});});
    \\const NS='http://www.w3.org/2000/svg';
    \\const svg=$('#gsvg');while(svg.firstChild)svg.removeChild(svg.firstChild);
    \\const defs=document.createElementNS(NS,'defs');
    \\defs.innerHTML='<marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 1 L 9 5 L 0 9" fill="none" stroke="currentColor" stroke-width="1.5"></path></marker>';
    \\svg.appendChild(defs);
    \\edges.forEach(function(e){const a=byId[e.from],b=byId[e.to];if(!a||!b)return;const l=document.createElementNS(NS,'line');l.setAttribute('x1',a._x+196);l.setAttribute('y1',a._y+15);l.setAttribute('x2',b._x);l.setAttribute('y2',b._y+15);l.setAttribute('class','edge');l.setAttribute('marker-end','url(#arr)');l.dataset.from=e.from;l.dataset.to=e.to;svg.appendChild(l);});
    \\nodes.forEach(function(n){const g=document.createElementNS(NS,'g');g.setAttribute('class','node');g.dataset.id=n.id;
    \\const r=document.createElementNS(NS,'rect');r.setAttribute('x',n._x);r.setAttribute('y',n._y);r.setAttribute('width',196);r.setAttribute('height',30);r.setAttribute('class','node');g.appendChild(r);
    \\const base=(n.path||'').split('/').pop();const t1=document.createElementNS(NS,'text');t1.setAttribute('x',n._x+8);t1.setAttribute('y',n._y+13);t1.textContent=base.length>26?base.slice(0,25)+'…':base;g.appendChild(t1);
    \\const t2=document.createElementNS(NS,'text');t2.setAttribute('x',n._x+8);t2.setAttribute('y',n._y+25);t2.setAttribute('class','gsub');t2.textContent=n.group||'';g.appendChild(t2);
    \\g.addEventListener('click',function(ev){ev.stopPropagation();gDetail(n,edges,byId);});svg.appendChild(g);});
    \\GV={vb:{x:0,y:0,w:W,h:H},full:{w:W,h:H}};
    \\gApplyVB();gPan(svg);
    \\const gc=$('#gcount');if(gc)gc.textContent=nodes.length+' / '+(d.nodes||[]).length+' nodes'+(d.truncated?' · '+esc(T('trunc')):'');}
    \\function gDetail(n,edges,byId){document.querySelectorAll('#gsvg g.node').forEach(function(g){g.classList.toggle('sel',+g.dataset.id===n.id);});
    \\const outs=[],ins=[];edges.forEach(function(e){if(e.from===n.id&&byId[e.to])outs.push(byId[e.to].path);if(e.to===n.id&&byId[e.from])ins.push(byId[e.from].path);});
    \\const box=$('#gdetail');box.classList.add('on');
    \\box.innerHTML='<b>'+esc(n.path)+'</b><br><span style="color:var(--muted)">'+esc(T('depends_on'))+' ('+outs.length+')</span><ul>'+outs.slice(0,20).map(function(p){return '<li>'+esc(p)+'</li>';}).join('')+'</ul><span style="color:var(--muted)">'+esc(T('needed_by'))+' ('+ins.length+')</span><ul>'+ins.slice(0,20).map(function(p){return '<li>'+esc(p)+'</li>';}).join('')+'</ul>';}
    \\function gPan(svg){let drag=null;svg.addEventListener('pointerdown',function(e){drag={x:e.clientX,y:e.clientY,vx:GV.vb.x,vy:GV.vb.y};svg.setPointerCapture(e.pointerId);svg.style.cursor='grabbing';});svg.addEventListener('pointermove',function(e){if(!drag||!GV)return;const r=svg.getBoundingClientRect();const sx=GV.vb.w/r.width,sy=GV.vb.h/r.height;GV.vb.x=drag.vx-(e.clientX-drag.x)*sx;GV.vb.y=drag.vy-(e.clientY-drag.y)*sy;gApplyVB();});const up=function(){drag=null;svg.style.cursor='grab';};svg.addEventListener('pointerup',up);svg.addEventListener('pointercancel',up);svg.addEventListener('wheel',function(e){e.preventDefault();gZoom(e.deltaY>0?1.2:0.84);},{passive:false});}
    \\async function renderTreemap(){let d=null;try{d=await j('/api/v1/treemap');}catch(e){}$('#cards').innerHTML='';if(!d){$('#extra').innerHTML=emptyBox();return;}
    \\let mx=1;(d.files||[]).forEach(function(f){if(f.loc>mx)mx=f.loc;});
    \\let h='<h3>'+esc(T('tmap'))+'</h3><div class="tm">';
    \\const byG={};(d.files||[]).slice(0,240).forEach(function(f){(byG[f.group||'.']=byG[f.group||'.']||[]).push(f);});
    \\Object.keys(byG).sort().forEach(function(g){h+='<div class="gh">'+esc(g)+'</div>';byG[g].forEach(function(f){const w=Math.max(3,Math.round(f.loc*100/mx));const a=Math.min(0.9,f.cx/30);h+='<div title="'+esc(f.path)+' · cx '+esc(f.cx)+'" style="width:'+w+'%;background:rgba(210,153,34,'+a.toFixed(2)+')">'+esc(f.path)+'</div>';});});
    \\h+='</div><h3>'+esc(T('groups'))+'</h3><table><thead><tr><th>'+esc(T('group'))+'</th><th class="num">'+esc(T('files'))+'</th><th class="num">'+esc(T('loc'))+'</th><th class="num">'+esc(T('cx'))+'</th></tr></thead><tbody>'+((d.groups||[]).map(function(g){return '<tr><td>'+esc(g.name)+'</td><td class="num">'+esc(g.files)+'</td><td class="num">'+esc(g.loc)+'</td><td class="num">'+esc(g.cx)+'</td></tr>';}).join(''))+'</tbody></table>';$('#extra').innerHTML=h;}
    \\async function renderSymbols(){let d=null;try{d=await j('/api/v1/symbols');}catch(e){}$('#cards').innerHTML='';if(!d){$('#extra').innerHTML=emptyBox();return;}
    \\window._sym=d.symbols||[];$('#extra').innerHTML='<div class="toolbar"><input id="symf" placeholder="filter…" style="flex:1"></div><div id="symt"></div>';
    \\const draw=function(){const q=($('#symf').value||'').toLowerCase();const rows=window._sym.filter(function(s){return !q||s.name.toLowerCase().indexOf(q)>=0||s.file.toLowerCase().indexOf(q)>=0;}).slice(0,120);$('#symt').innerHTML='<p class="sub">'+window._sym.length+' symbols ('+esc(T('filtered'))+': '+rows.length+')</p>'+tbl(['name','kind','file','line'],rows.map(function(s){return [s.name,s.kind,s.file,s.line];}));};
    \\$('#symf').addEventListener('input',draw);draw();}
    \\async function renderDeadcode(){let d=null;try{d=await j('/api/v1/deadcode');}catch(e){}$('#cards').innerHTML='';if(!d){$('#extra').innerHTML=emptyBox();return;}
    \\const rows=(d.deadcode||[]);$('#extra').innerHTML=rows.length?tbl(['confidence','file','name','reason'],rows.map(function(x){return [x.confidence,x.file,x.name,x.reason];})):emptyBox();}
    \\async function renderComplexity(){let d=null;try{d=await j('/api/v1/complexity');}catch(e){}$('#cards').innerHTML='';if(!d){$('#extra').innerHTML=emptyBox();return;}
    \\$('#extra').innerHTML=tbl(['path','complexity','loc','nesting'],(d.ranking||[]).map(function(x){return [x.path,x.complexity,x.loc,x.nesting];}));}
    \\async function renderSecurity(){let d=null;try{d=await j('/api/v1/security');}catch(e){}$('#cards').innerHTML='';if(!d){$('#extra').innerHTML=emptyBox();return;}
    \\const rows=(d.findings||[]);$('#extra').innerHTML='<p class="sub">Evidence is masked; values never leave your machine.</p>'+(rows.length?tbl(['severity','file','line','evidence'],rows.slice(0,200).map(function(x){return [x.severity,x.file,x.line,x.evidence];})):emptyBox());}
    \\async function renderGit(){let d=null;try{d=await j('/api/v1/git');}catch(e){}$('#cards').innerHTML='';if(!d){$('#extra').innerHTML=emptyBox();return;}
    \\$('#extra').innerHTML='<p>Branch: <b>'+esc(d.branch)+'</b> · Commits: <b>'+esc(d.commits)+'</b></p><h3>Hotspots</h3>'+tbl(['path','dependents'],(d.hotspots||[]).map(function(x){return [x.path,x.dependents];}));}
    \\async function renderImpactForm(){$('#cards').innerHTML='';$('#extra').innerHTML='<div class="toolbar"><input id="impf" placeholder="src/database.ts" style="flex:1"><button class="hbtn" onclick="doImpact()">Go</button></div><div id="impr"></div>';
    \\window.doImpact=async function(){const f=$('#impf').value;if(!f)return;let d=null;try{d=await j('/api/v1/impact?file='+encodeURIComponent(f));}catch(e){}$('#impr');if(!d||d.error)$('#impr').innerHTML=emptyBox();else $('#impr').innerHTML='<h3>Risk '+esc(d.risk)+'</h3><p class="sub">Direct '+esc(d.direct)+' · Indirect '+esc(d.indirect)+' · Tests '+esc(d.tests)+'</p><ul>'+((d.reasons||[]).map(function(r){return '<li>'+esc(r)+'</li>';}).join(''))+'</ul>';};}
    \\async function renderReports(){$('#cards').innerHTML='';$('#extra').innerHTML='<ul><li><a href="/api/v1/report?format=md">Markdown report</a></li><li><a href="/api/v1/report?format=html">HTML report</a></li><li><a href="/api/v1/report?format=csv">CSV export</a></li><li><a href="/api/v1/project">Full JSON snapshot</a></li></ul>';}
    \\async function renderPrivacy(){$('#cards').innerHTML='';$('#extra').innerHTML='<h3>Privacy</h3><p>Source code is processed locally. No cloud upload, no required API, no mandatory telemetry. The index stays on disk; delete <code>.ziglens/</code> any time. The server binds <code>127.0.0.1</code> only.</p><h3>Privasi</h3><p>Kode diproses lokal. Tanpa upload cloud, tanpa API wajib, tanpa telemetri wajib. Hapus <code>.ziglens/</code> kapan saja. Server hanya di <code>127.0.0.1</code>.</p>';}
    \\function renderBm(){let b=[];try{b=JSON.parse(localStorage.getItem('zl_bm')||'[]');}catch(e){b=[];}$('#bm').innerHTML=b.map(function(x,i){return '<a data-i="'+i+'">'+esc(x.p)+' '+esc(x.q||'')+'</a>';}).join('')||'<span style="color:var(--faint)">'+esc(T('none'))+'</span>';document.querySelectorAll('#bm a').forEach(function(a){a.onclick=function(){const x=b[+a.dataset.i];if(x.q)$('#q').value=x.q;go(x.p);};});}
    \\document.querySelectorAll('#nav a').forEach(function(a){a.onclick=function(){go(a.dataset.p);};});
    \\$('#theme').onclick=function(){localStorage.setItem('zl_theme',document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark');themeApply();};
    \\$('#dens').onclick=function(){localStorage.setItem('zl_dens',localStorage.getItem('zl_dens')==='comfy'?'compact':'comfy');densApply();};
    \\$('#lang').onclick=function(){LANG=LANG==='en'?'id':'en';localStorage.setItem('zl_lang',LANG);applyLang();};
    \\$('#helpbtn').onclick=function(){$('#help').classList.add('on');};
    \\$('#helpx').onclick=function(){$('#help').classList.remove('on');};
    \\$('#star').onclick=function(){let b=[];try{b=JSON.parse(localStorage.getItem('zl_bm')||'[]');}catch(e){b=[];}const t=$('#title').textContent.toLowerCase();b.push({p:t,q:$('#q').value});localStorage.setItem('zl_bm',JSON.stringify(b.slice(-20)));renderBm();};
    \\document.addEventListener('keydown',function(e){const inQ=document.activeElement===$('#q')||document.activeElement===$('#symf')||document.activeElement===$('#impf')||document.activeElement===$('#gq');if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'){e.preventDefault();$('#q').focus();return;}if(e.key==='Escape'){$('#help').classList.remove('on');if(inQ)document.activeElement.blur();return;}if(inQ)return;if(e.key==='?'){$('#help').classList.toggle('on');}else if(e.key==='r'||e.key==='R'){const h=(location.hash||'').replace('#/','');render(PAGES.indexOf(h)>=0?h:'overview');}else if(e.key==='t'||e.key==='T'){$('#theme').click();}});
    \\$('#q').addEventListener('input',async function(e){const q=e.target.value;if(q.length<2)return;const r=await j('/api/v1/search?q='+encodeURIComponent(q)).catch(function(){return null;});if(r)$('#extra').innerHTML='<pre>'+esc(JSON.stringify(r,null,2))+'</pre>';});
    \\load();
    \\</script></body></html>
;

pub fn html() []const u8 {
    return dashboard_html;
}

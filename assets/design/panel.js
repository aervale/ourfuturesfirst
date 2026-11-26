/* Design panel: a small corner widget for trying color palettes and fonts on the live page.
   Loaded only on your own machine (localhost) or with ?design in the address. Visitors never see it.
   Changes stay in this browser until you press Reset; "Copy CSS" gives the lines to paste into index.html. */
(function(){
"use strict";
if(window.__ofpDesign)return;window.__ofpDesign=1;

/* ---------- presets ---------- */
var BASE_PRESETS=[
  ["Current site","0C0C0E-111113-ECEAE0-A22C29-ECEAE0",1],
  ["Navy","152F69-1B3A7C-EEF1F7-D9422F-FFFFFF",1],
  ["Deep navy","0E1A36-152447-E9ECF2-D9422F-FFFFFF",1],
  ["Paper","FBFAF6-F2F0E8-17171A-A22C29-FFFFFF",1],
  ["White","FFFFFF-F4F4F2-141416-A22C29-FFFFFF",1],
  ["Dark teal","0B3839-0F4445-ECEAE0-E05A3C-FFFFFF",1],
  ["Forest","10231A-163023-ECEAE0-C8432F-FFFFFF",1],
  ["Plum","1C1220-25182B-EEE8EE-E0604A-FFFFFF",1]
];
var FIELDS=[["bg","Background"],["card","Card"],["ink","Text"],["accent","Accent"],["onAccent","On accent"]];

var HEAD_FONTS=["EB Garamond","Cormorant Garamond","Newsreader","Source Serif 4","Fraunces","Playfair Display","Libre Baskerville","Lora","Crimson Pro","Spectral","Merriweather","Bodoni Moda","IBM Plex Serif","Instrument Serif","DM Serif Display","Libre Caslon Text","Literata","Noto Serif","Inter","Space Grotesk","Archivo","Sora","Syne","Bricolage Grotesque"];
var BODY_FONTS=["Noto Sans","Inter","Source Sans 3","IBM Plex Sans","Public Sans","Work Sans","DM Sans","Instrument Sans","Manrope","Figtree","Lato","Open Sans","Nunito Sans","Atkinson Hyperlegible","Outfit","Plus Jakarta Sans","Rubik","Karla","Libre Franklin","Space Grotesk"];
var LABEL_FONTS=["(same as body)","IBM Plex Mono","JetBrains Mono","DM Mono","Space Mono","Roboto Mono","Fira Code","Inter","Archivo","Space Grotesk"];
var SITE={head:"EB Garamond",body:"Nunito Sans",label:"(same as body)",hw:500};

/* ---------- color helpers ---------- */
function clamp(x,a,b){return Math.max(a,Math.min(b,x))}
function rgb(h){return [1,3,5].map(function(i){return parseInt(h.slice(i,i+2),16)})}
function toHex(c){return "#"+c.map(function(v){return Math.round(clamp(v,0,255)).toString(16).padStart(2,"0")}).join("").toUpperCase()}
function rgba(h,a){var c=rgb(h);return "rgba("+c[0]+","+c[1]+","+c[2]+","+a+")"}
function lum(h){var c=rgb(h).map(function(v){v/=255;return v<=.03928?v/12.92:Math.pow((v+.055)/1.055,2.4)});return .2126*c[0]+.7152*c[1]+.0722*c[2]}
function contrast(a,b){var x=lum(a),y=lum(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05)}
function mix(a,b,t){var x=rgb(a),y=rgb(b);return toHex(x.map(function(v,i){return v+(y[i]-v)*t}))}
function hsl(h,s,l){s/=100;l/=100;var k=function(n){return (n+h/30)%12},a=s*Math.min(l,1-l),f=function(n){return l-a*Math.max(-1,Math.min(k(n)-3,Math.min(9-k(n),1)))};return toHex([f(0),f(8),f(4)].map(function(x){return x*255}))}
function toHsl(hx){var c=rgb(hx).map(function(v){return v/255}),mx=Math.max.apply(0,c),mn=Math.min.apply(0,c),d=mx-mn,h=0,l=(mx+mn)/2,s=d?d/(1-Math.abs(2*l-1)):0;
  if(d){if(mx===c[0])h=((c[1]-c[2])/d)%6;else if(mx===c[1])h=(c[2]-c[0])/d+2;else h=(c[0]-c[1])/d+4;h*=60;if(h<0)h+=360}return [h,s*100,l*100]}
function chroma(hx){var c=rgb(hx);return Math.max.apply(0,c)-Math.min.apply(0,c)}
function hexes(str){return (String(str).match(/[0-9a-f]{6}/gi)||[]).map(function(x){return "#"+x.toUpperCase()})}
function rnd(a,b){return a+Math.random()*(b-a)}

/* Turn any list of colors (a Coolors palette) into the site's five base colors. */
function fromColors(list,mode){
  var cs=list.slice().sort(function(a,b){return lum(a)-lum(b)}),dark=cs[0],light=cs[cs.length-1];
  if(mode==="auto")mode=lum(dark)<.09?"dark":"light";
  var bg,ink;
  if(mode==="dark"){bg=lum(dark)<.05?dark:mix(dark,"#000000",.55);ink=lum(light)>.6?light:mix(light,"#FFFFFF",.75)}
  else{bg=lum(light)>.75?light:mix(light,"#FFFFFF",.8);ink=lum(dark)<.03?dark:mix(dark,"#000000",.7)}
  if(contrast(ink,bg)<7)ink=mode==="dark"?"#F2F1EC":"#141416";
  var rest=cs.filter(function(c){return c!==dark&&c!==light});if(!rest.length)rest=cs;
  var ok=rest.filter(function(c){return contrast(c,bg)>=3});
  var accent=(ok.length?ok:rest).slice().sort(function(a,b){return chroma(b)-chroma(a)})[0];
  if(contrast(accent,bg)<3){var h=toHsl(accent);accent=hsl(h[0],Math.max(h[1],55),mode==="dark"?62:42)}
  var card=mix(bg,ink,mode==="dark"?.035:.04);
  var on=contrast("#FFFFFF",accent)>=contrast("#141416",accent)?"#FFFFFF":"#141416";
  return {bg:bg,card:card,ink:ink,accent:accent,onAccent:on};
}
/* A brand-new palette, Coolors-generator style: random hue, random harmony, dark or light. */
function generate(mode){
  var h=rnd(0,360),light=mode==="light"||(mode==="auto"&&Math.random()<.4);
  var harm=[0,30,150,180,210,240][Math.floor(Math.random()*6)],ah=(h+harm)%360;
  var bg=light?hsl(h,rnd(10,35),rnd(94,98)):hsl(h,rnd(20,55),rnd(5,14));
  var ink=light?hsl(h,rnd(10,30),rnd(8,14)):hsl(h,rnd(8,25),rnd(88,95));
  var accent=hsl(ah,rnd(55,85),light?rnd(36,46):rnd(52,64));
  var p={bg:bg,card:mix(bg,ink,light?.04:.04),ink:ink,accent:accent};
  p.onAccent=contrast("#FFFFFF",accent)>=contrast("#141416",accent)?"#FFFFFF":"#141416";
  return p;
}

/* ---------- state ---------- */
var KEY="ofp-design-v3";
/* The default look while working locally: navy with a gold accent in dark mode, paper with the same gold in light mode.
   The switch in the bottom left flips between them; Reset in the panel goes back to whichever one is on. */
var THEMES={
  dark:{bg:"#0C0C0E",card:"#111113",ink:"#ECEAE0",accent:"#A22C29",onAccent:"#ECEAE0"},
  light:{bg:"#FFFFFF",card:"#F4F4F2",ink:"#141416",accent:"#A22C29",onAccent:"#FFFFFF"}
};
var THEME_NAMES={dark:"Navy and gold (dark)",light:"Paper and gold (light)"};
var DEF_BODY=SITE.body;
var state={colors:null,theme:"dark",fonts:{head:SITE.head,body:DEF_BODY,label:SITE.label,hw:SITE.hw},mode:"auto",open:false,tab:"colors",source:""};
try{var saved=JSON.parse(localStorage.getItem(KEY)||"null");if(saved)state=Object.assign(state,saved,{fonts:Object.assign({},state.fonts,saved.fonts||{})})}catch(e){}
function save(){try{localStorage.setItem(KEY,JSON.stringify(state))}catch(e){}}
function current(){return state.colors||THEMES[document.documentElement.getAttribute("data-theme")==="light"?"light":"dark"]}

/* ---------- applying to the page ---------- */
function tokens(p){
  var light=lum(p.bg)>.4;
  return {"--bg":p.bg,"--card":p.card,"--ink":p.ink,"--accent":p.accent,"--on-accent":p.onAccent,
    "--inset":rgba(p.ink,light?.05:.035),"--mute":rgba(p.ink,.62),"--faint":rgba(p.ink,.36),
    "--line":rgba(p.ink,.08),"--line2":rgba(p.ink,.16),"--hover":rgba(p.ink,light?.06:.07),
    "--tint":rgba(p.accent,light?.14:.24),"color-scheme":light?"light":"dark","--icon-filter":light?"none":"invert(1)"};
}
/* Nine colors for the poll results and pies. A Coolors palette lends its own colors; otherwise they are
   shades of the accent and the text color, the way the site's original chart colors were built. */
function chartColors(p,src){
  var cs=[];
  if(src&&src.length>=3){
    var pool=src.filter(function(c){return contrast(c,p.bg)>=1.5});
    pool.sort(function(a,b){return (b===p.accent)-(a===p.accent)});
    if(pool.indexOf(p.accent)<0)pool.unshift(p.accent);
    cs=pool.slice(0,9);
    var k=0;while(cs.length<9){var c=pool[k%pool.length];cs.push(mix(c,k%2?p.ink:p.bg,.45));k++}
  }else{
    cs=[mix(p.ink,p.bg,.04),p.accent,mix(p.ink,p.bg,.48),mix(p.accent,p.bg,.45),mix(p.ink,p.bg,.24),mix(p.accent,p.ink,.3),mix(p.ink,p.bg,.62),mix(p.accent,p.ink,.62),mix(p.ink,p.bg,.8)];
  }
  var t={};cs.forEach(function(c,i){t["--c"+(i+1)]=c;if(i<4)t["--con"+(i+1)]=contrast("#FFFFFF",c)>=contrast("#141416",c)?"#FFFFFF":"#141416"});
  t["--c-other"]=mix(p.ink,p.bg,.86);
  return t;
}
var FIXED=[ /* parts of the page that use fixed dark colors; tie them to the palette while testing */
  ".top{background:color-mix(in srgb,var(--bg) 86%,transparent)!important}body{background:var(--bg)!important}",
  "input[type=text],input[type=email],input[type=tel],input[type=search],textarea{background:color-mix(in srgb,var(--ink) 6%,var(--bg))!important}",
  "input:focus,textarea:focus,.sel:focus,.sel[aria-expanded=true]{background-color:color-mix(in srgb,var(--ink) 10%,var(--bg))!important}",
  ".sel{background-color:color-mix(in srgb,var(--ink) 6%,var(--bg))!important}",
  ".menu,.list .lead::after,.bars .plus::after{background:var(--card)!important}",
  "#mapLand .land{fill:var(--inset)!important;stroke:color-mix(in srgb,var(--ink) 22%,transparent)!important}",
  "#mapLand .edge{stroke:var(--line)!important}"
].join("");
function fontStack(name,fallback){return '"'+name+'",'+fallback}
var loaded={};
function loadFont(name){
  if(!name||name.charAt(0)==="("||loaded[name])return;loaded[name]=1;
  var fam=name.replace(/ /g,"+"),l=document.createElement("link");l.rel="stylesheet";
  l.href="https://fonts.googleapis.com/css2?family="+fam+":wght@300;400;500;600;700&display=swap";
  l.onerror=function(){var m=document.createElement("link");m.rel="stylesheet";m.href="https://fonts.googleapis.com/css2?family="+fam+"&display=swap";document.head.appendChild(m)};
  document.head.appendChild(l);
}
function apply(){
  var root=document.documentElement,changed=!!state.colors;
  var t=Object.assign(tokens(current()),chartColors(current(),state.chart));
  Object.keys(t).forEach(function(k){changed?root.style.setProperty(k,t[k]):root.style.removeProperty(k)});
  var f=state.fonts;
  [f.head,f.body,f.label].forEach(loadFont);
  var fontOn=f.head!==SITE.head||f.body!==SITE.body||f.label!==SITE.label||+f.hw!==SITE.hw;
  if(fontOn){
    root.style.setProperty("--head",fontStack(f.head,"Georgia,serif"));
    root.style.setProperty("--sans",fontStack(f.body,"system-ui,sans-serif"));
    root.style.setProperty("--mono",f.label.charAt(0)==="("?fontStack(f.body,"system-ui,sans-serif"):fontStack(f.label,"ui-monospace,monospace"));
    root.style.setProperty("--hw",String(f.hw));
  }else ["--head","--sans","--mono","--hw"].forEach(function(k){root.style.removeProperty(k)});
  var s=document.getElementById("ofp-design-fixed");
  if(changed){if(!s){s=document.createElement("style");s.id="ofp-design-fixed";document.head.appendChild(s)}s.textContent=FIXED}else if(s)s.remove();
  save();
}

/* ---------- the widget ---------- */
var host=document.createElement("div");host.id="ofp-design";
host.style.cssText="position:fixed;right:16px;bottom:16px;z-index:2147483000";
var sh=host.attachShadow({mode:"open"});
sh.innerHTML='<style>'+
':host{all:initial}*{box-sizing:border-box}'+
'.fab{all:unset;cursor:pointer;width:42px;height:42px;border-radius:50%;display:grid;place-items:center;background:#18181b;border:1px solid #3a3a40;box-shadow:0 6px 20px rgba(0,0,0,.35);transition:transform .15s}'+
'.fab:hover{transform:scale(1.06)}.fab svg{width:22px;height:22px}'+
'.panel{position:absolute;right:0;bottom:52px;width:330px;max-height:min(78vh,680px);display:flex;flex-direction:column;background:#141416;color:#e8e6dd;border:1px solid #2e2e33;border-radius:12px;box-shadow:0 18px 50px rgba(0,0,0,.45);font:12.5px/1.4 system-ui,-apple-system,"Segoe UI",sans-serif;overflow:hidden}'+
'.panel[hidden]{display:none}'+
'header{display:flex;align-items:center;gap:6px;padding:10px 10px 0}header b{font-size:13px;flex:1}'+
'.tabs{display:flex;gap:4px;padding:8px 10px;border-bottom:1px solid #2a2a2e}'+
'.tabs button,.btn{all:unset;cursor:pointer;padding:5px 9px;border-radius:6px;border:1px solid #2e2e33;background:#1c1c20;color:#e8e6dd;font-size:12px}'+
'.tabs button.on{background:#e8e6dd;color:#141416;border-color:#e8e6dd}.btn:hover,.tabs button:hover{border-color:#55555c}'+
'.btn.primary{background:#e8e6dd;color:#141416;border-color:#e8e6dd;font-weight:600}'+
'.x{all:unset;cursor:pointer;color:#9a988f;font-size:16px;padding:0 4px}'+
'.body{overflow:auto;padding:10px 10px 14px}.body::-webkit-scrollbar{width:6px}.body::-webkit-scrollbar-thumb{background:#333;border-radius:3px}'+
'h4{margin:12px 0 6px;font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;color:#9a988f;font-weight:600}h4:first-child{margin-top:0}'+
'.row{display:flex;gap:6px;flex-wrap:wrap;align-items:center}'+
'.seg{display:inline-flex;border:1px solid #2e2e33;border-radius:6px;overflow:hidden}.seg button{all:unset;cursor:pointer;padding:4px 8px;font-size:11.5px;color:#9a988f}.seg button.on{background:#2a2a30;color:#e8e6dd}'+
'.cur{display:flex;height:28px;border-radius:7px;overflow:hidden;border:1px solid #2e2e33;margin-bottom:6px}.cur i{flex:1}'+
'.src{color:#9a988f;font-size:11.5px;min-height:16px}'+
'input.search,input.txt,select{all:unset;box-sizing:border-box;width:100%;padding:6px 8px;border:1px solid #2e2e33;border-radius:6px;background:#1c1c20;color:#e8e6dd;font-size:12px}'+
'select{cursor:pointer}'+
'.list{display:grid;grid-template-columns:1fr 1fr;gap:5px;margin-top:6px;max-height:250px;overflow:auto;padding-right:2px}'+
'.p{all:unset;cursor:pointer;border:1px solid #2a2a2e;border-radius:7px;padding:4px;background:#1a1a1d}.p:hover{border-color:#55555c}.p.on{border-color:#e8e6dd}'+
'.p .sw{display:flex;height:16px;border-radius:4px;overflow:hidden}.p .sw i{flex:1}.p span{display:block;font-size:10.5px;color:#b8b6ad;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}'+
'.f{display:grid;grid-template-columns:26px 1fr 74px;gap:6px;align-items:center;margin-bottom:5px}'+
'.f input[type=color]{all:unset;cursor:pointer;width:26px;height:26px;border-radius:6px;border:1px solid #2e2e33}.f input[type=color]::-webkit-color-swatch-wrapper{padding:2px}.f input[type=color]::-webkit-color-swatch{border:0;border-radius:4px}'+
'.f input.txt{font:11.5px ui-monospace,monospace;padding:5px 6px}'+
'.chk{display:flex;justify-content:space-between;padding:3px 0;border-bottom:1px solid #222226;font-size:11.5px}.ok{color:#7fcf8f}.warn{color:#e0b85a}.bad{color:#ef7b6b}'+
'.hint{color:#8a887f;font-size:11px;margin-top:6px}'+
'label.l{display:block;margin:8px 0 4px;color:#b8b6ad;font-size:11.5px}'+
'.sample{margin-top:10px;padding:10px;border:1px solid #2a2a2e;border-radius:8px;background:#1a1a1d}'+
'input[type=range]{width:100%}'+
'</style>'+
'<div class="panel" hidden>'+
' <header><b>Design</b><button class="x" data-act="close" title="Close">×</button></header>'+
' <div class="tabs"><button data-tab="colors">Colors</button><button data-tab="fonts">Fonts</button><button data-tab="export">Copy</button></div>'+
' <div class="body">'+
'  <section data-pane="colors">'+
'   <div class="cur" id="cur"></div><div class="src" id="src"></div>'+
'   <div class="row" style="margin-top:6px"><button class="btn primary" data-act="gen" title="Space bar also works">Generate</button><button class="btn" data-act="rand">Random Coolors</button><button class="btn" data-act="flip">Flip accent</button><button class="btn" data-act="reset">Reset</button></div>'+
'   <h4>Light or dark</h4><div class="seg" id="mode"><button data-m="auto">Auto</button><button data-m="dark">Dark</button><button data-m="light">Light</button></div>'+
'   <h4>Presets <span id="count" style="text-transform:none;letter-spacing:0;font-weight:400"></span></h4>'+
'   <input class="search" id="q" placeholder="Search: blue, sunset, pastel…">'+
'   <div class="list" id="list"></div>'+
'   <h4>Paste a Coolors link or hex codes</h4><input class="txt" id="imp" placeholder="coolors.co/264653-2a9d8f-…">'+
'   <h4>Fine-tune</h4><div id="fields"></div>'+
'   <h4>Readability</h4><div id="checks"></div>'+
'  </section>'+
'  <section data-pane="fonts" hidden>'+
'   <label class="l">Headings</label><select id="fh"></select>'+
'   <label class="l">Heading weight <span id="hwv"></span></label><input type="range" id="fw" min="300" max="700" step="100">'+
'   <label class="l">Body text and numbers</label><select id="fb"></select>'+
'   <label class="l">Labels, tabs and buttons</label><select id="fl"></select>'+
'   <div class="row" style="margin-top:10px"><button class="btn" data-act="fontrand">Random pairing</button><button class="btn" data-act="fontreset">Reset fonts</button></div>'+
'   <p class="hint">Fonts load from Google Fonts as you pick them.</p>'+
'  </section>'+
'  <section data-pane="export" hidden>'+
'   <p class="hint" style="margin-top:0">Paste this into the :root block at the top of index.html to make the current look permanent.</p>'+
'   <textarea id="css" readonly style="all:unset;box-sizing:border-box;display:block;width:100%;height:220px;padding:8px;border:1px solid #2e2e33;border-radius:6px;background:#1c1c20;color:#e8e6dd;font:11px/1.5 ui-monospace,monospace;white-space:pre;overflow:auto"></textarea>'+
'   <div class="row" style="margin-top:8px"><button class="btn primary" data-act="copy">Copy CSS</button><a class="btn" id="coolink" target="_blank" rel="noopener" style="text-decoration:none">Open in Coolors</a></div>'+
'  </section>'+
' </div>'+
'</div>'+
'<button class="fab" title="Design panel" aria-label="Design panel"><svg viewBox="0 0 24 24" fill="none"><path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.6-.9 1.2-1.8-.4-.9 0-1.9 1-1.9H16a5 5 0 0 0 5-5C21 6.6 17 3 12 3Z" stroke="#e8e6dd" stroke-width="1.6"/><circle cx="7.5" cy="11" r="1.4" fill="#E05A3C"/><circle cx="10" cy="7" r="1.4" fill="#F2C14E"/><circle cx="14.5" cy="7" r="1.4" fill="#4FB0A6"/><circle cx="17" cy="11" r="1.4" fill="#5B7FD6"/></svg></button>';
var $=function(s){return sh.querySelector(s)};
var panel=$(".panel");

var ALL=BASE_PRESETS.map(function(p){return {name:p[0],colors:hexes(p[1]),site:1}}).concat((window.OFF_COOLORS||[]).map(function(p){return {name:p[0],colors:hexes(p[1])}}));
$("#count").textContent="("+ALL.length+")";

function setColors(c,src,chart){state.colors=c;state.source=src||"";if(chart!==undefined)state.chart=chart;apply();render()}
function pick(p){setColors(p.site?{bg:p.colors[0],card:p.colors[1],ink:p.colors[2],accent:p.colors[3],onAccent:p.colors[4]}:fromColors(p.colors,state.mode),(p.site?"":"Coolors: ")+p.name,p.site?null:p.colors)}

function renderList(){
  var q=$("#q").value.trim().toLowerCase(),box=$("#list"),cur=current(),frag=document.createDocumentFragment();
  var words={red:0,orange:30,yellow:55,green:120,teal:175,blue:215,purple:275,pink:330};
  ALL.forEach(function(p){
    var hit=!q||p.name.toLowerCase().indexOf(q)>=0;
    if(!hit&&words[q]!==undefined)hit=p.colors.some(function(c){var h=toHsl(c);var d=Math.abs(((h[0]-words[q])+540)%360-180);return h[1]>35&&h[2]>18&&h[2]<85&&d<22});
    if(!hit)return;
    var b=document.createElement("button");b.className="p";b.title=p.name;
    b.innerHTML='<div class="sw">'+p.colors.map(function(c){return '<i style="background:'+c+'"></i>'}).join("")+'</div><span>'+p.name+'</span>';
    b.onclick=function(){pick(p)};frag.appendChild(b);
  });
  box.innerHTML="";box.appendChild(frag);
}
function render(){
  var c=current();
  sh.querySelectorAll("[data-tab]").forEach(function(b){b.classList.toggle("on",b.dataset.tab===state.tab)});
  sh.querySelectorAll("[data-pane]").forEach(function(s){s.hidden=s.dataset.pane!==state.tab});
  sh.querySelectorAll("#mode button").forEach(function(b){b.classList.toggle("on",b.dataset.m===state.mode)});
  $("#cur").innerHTML=FIELDS.map(function(f){return '<i style="background:'+c[f[0]]+'" title="'+f[1]+' '+c[f[0]]+'"></i>'}).join("");
  $("#src").textContent=state.colors?(state.source||"Custom"):"Current site colors";
  FIELDS.forEach(function(f){var ci=$("#c_"+f[0]),ti=$("#t_"+f[0]);if(ci&&ci.value.toUpperCase()!==c[f[0]])ci.value=c[f[0]];if(ti&&sh.activeElement!==ti)ti.value=c[f[0]]});
  var rows=[["Text on background",c.ink,c.bg,4.5],["Accent on background",c.accent,c.bg,3],["Button text on accent",c.onAccent,c.accent,4.5],["Text on card",c.ink,c.card,4.5]];
  $("#checks").innerHTML=rows.map(function(r){var v=contrast(r[1],r[2]),cls=v>=r[3]?"ok":v>=r[3]*.75?"warn":"bad";return '<div class="chk"><span>'+r[0]+'</span><b class="'+cls+'">'+v.toFixed(1)+':1</b></div>'}).join("");
  var f=state.fonts;$("#fh").value=f.head;$("#fb").value=f.body;$("#fl").value=f.label;$("#fw").value=f.hw;$("#hwv").textContent=f.hw;
  var t=Object.assign(tokens(c),chartColors(c,state.chart)),css=":root{\n"+Object.keys(t).map(function(k){return "  "+k+":"+t[k]+";"}).join("\n")+
    '\n  --head:"'+f.head+'",Georgia,serif; --hw:'+f.hw+';\n  --sans:"'+f.body+'",system-ui,sans-serif;\n  --mono:"'+(f.label.charAt(0)==="("?f.body:f.label)+'",system-ui,sans-serif;\n}';
  $("#css").value=css;
  $("#coolink").href="https://coolors.co/"+FIELDS.map(function(x){return c[x[0]].slice(1).toLowerCase()}).join("-");
  panel.hidden=!state.open;
}
/* fine-tune rows */
$("#fields").innerHTML=FIELDS.map(function(f){return '<div class="f"><input type="color" id="c_'+f[0]+'"><span>'+f[1]+'</span><input class="txt" id="t_'+f[0]+'" maxlength="7" spellcheck="false"></div>'}).join("");
FIELDS.forEach(function(f){
  var ci=$("#c_"+f[0]),ti=$("#t_"+f[0]);
  ci.addEventListener("input",function(){var c=Object.assign({},current());c[f[0]]=ci.value.toUpperCase();setColors(c,"Custom")});
  ti.addEventListener("input",function(){var v=ti.value.trim();if(v[0]!=="#")v="#"+v;if(/^#[0-9a-f]{6}$/i.test(v)){var c=Object.assign({},current());c[f[0]]=v.toUpperCase();setColors(c,"Custom")}});
});
/* fonts */
function opts(sel,list){sel.innerHTML=list.map(function(n){return '<option>'+n+'</option>'}).join("")}
opts($("#fh"),HEAD_FONTS);opts($("#fb"),BODY_FONTS);opts($("#fl"),LABEL_FONTS);
$("#fh").onchange=function(){state.fonts.head=this.value;apply();render()};
$("#fb").onchange=function(){state.fonts.body=this.value;apply();render()};
$("#fl").onchange=function(){state.fonts.label=this.value;apply();render()};
$("#fw").oninput=function(){state.fonts.hw=+this.value;apply();render()};
/* other controls */
$("#q").addEventListener("input",renderList);
$("#imp").addEventListener("input",function(){var h=hexes(this.value);if(h.length>=3)setColors(fromColors(h,state.mode),"Pasted palette",h)});
sh.querySelectorAll("#mode button").forEach(function(b){b.onclick=function(){state.mode=b.dataset.m;save();render()}});
sh.querySelectorAll("[data-tab]").forEach(function(b){b.onclick=function(){state.tab=b.dataset.tab;save();render()}});
var acts={
  close:function(){state.open=false;save();render()},
  gen:function(){setColors(generate(state.mode),"Generated",null)},
  rand:function(){var src=window.OFF_COOLORS||[];if(!src.length)return;var p=src[Math.floor(Math.random()*src.length)];pick({name:p[0],colors:hexes(p[1])})},
  flip:function(){var c=Object.assign({},current()),h=toHsl(c.accent);c.accent=hsl((h[0]+180)%360,h[1],h[2]);c.onAccent=contrast("#FFFFFF",c.accent)>=contrast("#141416",c.accent)?"#FFFFFF":"#141416";setColors(c,"Flipped accent")},
  reset:function(){state.colors=null;state.chart=null;state.source="";apply();render()},
  fontrand:function(){state.fonts.head=HEAD_FONTS[Math.floor(Math.random()*HEAD_FONTS.length)];state.fonts.body=BODY_FONTS[Math.floor(Math.random()*BODY_FONTS.length)];apply();render()},
  fontreset:function(){state.fonts={head:SITE.head,body:DEF_BODY,label:SITE.label,hw:SITE.hw};apply();render()},
  copy:function(){var t=$("#css");t.select();(navigator.clipboard?navigator.clipboard.writeText(t.value):Promise.reject()).catch(function(){document.execCommand("copy")});var b=sh.querySelector('[data-act=copy]');b.textContent="Copied";setTimeout(function(){b.textContent="Copy CSS"},1200)}
};
sh.addEventListener("click",function(e){var a=e.target.closest("[data-act]");if(a&&acts[a.dataset.act]){e.preventDefault();acts[a.dataset.act]()}});
$(".fab").onclick=function(){state.open=!state.open;save();render()};
/* space bar generates a new palette while the panel is open, like on Coolors */
document.addEventListener("keydown",function(e){
  if(!state.open||e.code!=="Space"||e.metaKey||e.ctrlKey||e.altKey)return;
  var t=e.composedPath()[0];if(t&&(/^(INPUT|TEXTAREA|SELECT|BUTTON)$/.test(t.tagName)||t.isContentEditable))return;
  e.preventDefault();acts.gen();
});

/* the page's light/dark switch wins: pressing it drops any palette picked here */
document.addEventListener("click",function(e){if(e.target.closest&&e.target.closest("#themeBtn")&&state.colors){state.colors=null;state.chart=null;state.source="";apply();render()}},true);
function mount(){document.body.appendChild(host);apply();renderList();render()}
if(document.body)mount();else document.addEventListener("DOMContentLoaded",mount);
})();

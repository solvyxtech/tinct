#!/usr/bin/env python3
"""Build docs/index.html: every bundled theme, drawn in its own colors.

A list of theme names tells you nothing about what a theme looks like, and a
screenshot goes stale the moment a palette is retuned. So the gallery is
generated from the theme files themselves — each preview is a small terminal
whose colors are read straight out of `themes/<name>.theme`, which means the
page can only be wrong if the theme is.

Run it after adding or editing a theme:

    python3 tools/gallery.py

CI regenerates it and fails if the result differs from what is committed.
"""
import html
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "themes")
OUT = os.path.join(ROOT, "docs", "index.html")

REPO = "https://github.com/solvyxtech/tinct"


def parse(path):
    d = {}
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k.strip()] = v.strip()
    return d


def lum(hexs):
    def ch(pair):
        v = int(pair, 16) / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    h = hexs.lstrip("#")
    return 0.2126 * ch(h[0:2]) + 0.7152 * ch(h[2:4]) + 0.0722 * ch(h[4:6])


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def card(name, d):
    """One theme as the terminal it actually produces.

    Themes may ship window colors only, with no palette; those get a preview
    with no syntax coloring, which is exactly what they do in a terminal.
    """
    full = all(f"ANSI{i}" in d for i in range(16))
    variables = {k: v for k, v in d.items()
                 if k.startswith(("ANSI", "BG", "FG", "SEL", "CURSOR"))}
    style = ";".join(f"--{k.lower()}:{v}" for k, v in variables.items())
    e = html.escape
    tone = "light" if lum(d["BG"]) > 0.5 else "dark"

    if full:
        swatches = ('<div class="swatches" aria-hidden="true">'
                    + "".join(f'<i style="background:{d[f"ANSI{i}"]}"></i>' for i in range(16))
                    + "</div>")
        accent_bright, accent_blue = d["ANSI14"], d["ANSI12"]
    else:
        swatches = ('<p class="no-palette">Window colors only — your own palette'
                    ' is left alone.</p>')
        accent_bright = accent_blue = d["CURSOR"]

    return f"""
<article class="card" data-tone="{tone}" style="{style}">
  <header class="card-head">
    <h3>{e(d['LABEL'])}</h3>
    <code class="slug">{e(name)}</code>
  </header>
  <p class="desc">{e(d['DESC'])}</p>
  <div class="term" role="img" aria-label="Terminal preview of the {e(d['LABEL'])} theme">
    <div class="line"><span class="c4">~/src/tinct</span> <span class="c5">main</span> <span class="c8">±</span></div>
    <div class="line"><span class="c2">$</span> tinct set {e(name)}<span class="cur"> </span></div>
    <div class="line"><span class="c2">+ accent</span> = <span class="c6">"{accent_bright}"</span></div>
    <div class="line"><span class="c1">- accent</span> = <span class="c6">"{accent_blue}"</span></div>
    <div class="line"><span class="sel">selected text</span> <span class="c8">dim comment</span></div>
    <div class="line"><span class="c10">✓ 24 passed</span> <span class="c11">! 2 warn</span> <span class="c9">✗ 1 failed</span></div>
  </div>
  {swatches}
  <dl class="facts">
    <div><dt>bg</dt><dd>{d['BG']}</dd></div>
    <div><dt>fg</dt><dd>{d['FG']}</dd></div>
    <div><dt>contrast</dt><dd>{contrast(d['FG'], d['BG']):.1f}:1</dd></div>
  </dl>
</article>"""


def section(title, note, items):
    cards = "".join(card(n, d) for n, d in items)
    return f"""
<section class="group">
  <div class="group-head">
    <h2>{title}</h2>
    <p>{note}</p>
  </div>
  <div class="grid">{cards}</div>
</section>"""


def build():
    names = sorted(f[:-6] for f in os.listdir(THEMES) if f.endswith(".theme"))
    themes = [(n, parse(os.path.join(THEMES, n + ".theme"))) for n in names]
    dark = [t for t in themes if lum(t[1]["BG"]) <= 0.5]
    light = [t for t in themes if lum(t[1]["BG"]) > 0.5]

    style = """
  :root {
    --page: #EFF1F4;
    --surface: #FFFFFF;
    --ink: #13171D;
    --muted: #5C6472;
    --line: #D9DDE4;
    --accent: #2E5B8A;
    --shadow: 0 1px 2px rgba(19, 23, 29, .06), 0 8px 24px rgba(19, 23, 29, .05);
    --display: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
    --body: system-ui, -apple-system, "Segoe UI", sans-serif;
    --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
    color-scheme: light dark;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --page: #0E1116;
      --surface: #161A20;
      --ink: #E5E9EF;
      --muted: #949CAA;
      --line: #262C35;
      --accent: #86ACD8;
      --shadow: 0 1px 2px rgba(0, 0, 0, .4), 0 10px 28px rgba(0, 0, 0, .35);
    }
  }
  :root[data-theme="dark"] {
    --page: #0E1116;
    --surface: #161A20;
    --ink: #E5E9EF;
    --muted: #949CAA;
    --line: #262C35;
    --accent: #86ACD8;
    --shadow: 0 1px 2px rgba(0, 0, 0, .4), 0 10px 28px rgba(0, 0, 0, .35);
  }

  * { box-sizing: border-box; }
  body {
    background: var(--page);
    color: var(--ink);
    font-family: var(--body);
    line-height: 1.5;
    margin: 0;
    padding: clamp(28px, 5vw, 64px) clamp(16px, 4vw, 48px) 80px;
  }
  .wrap { max-width: 1240px; margin: 0 auto; display: flex; flex-direction: column; gap: 44px; }

  .masthead { display: flex; flex-direction: column; gap: 14px; }
  .eyebrow {
    font-family: var(--mono); font-size: 12px; letter-spacing: .14em;
    text-transform: uppercase; color: var(--muted); margin: 0;
  }
  h1 {
    font-family: var(--display); font-weight: 400; font-size: clamp(34px, 5vw, 52px);
    line-height: 1.08; margin: 0; text-wrap: balance; letter-spacing: -.01em;
  }
  .lede { margin: 0; max-width: 64ch; color: var(--muted); font-size: 17px; }
  .lede code, footer code { font-family: var(--mono); font-size: .9em; color: var(--ink); }
  a { color: var(--accent); }

  .toolbar {
    display: flex; flex-wrap: wrap; gap: 10px; align-items: center;
    padding: 12px 14px; border: 1px solid var(--line); border-radius: 10px;
    background: var(--surface); box-shadow: var(--shadow);
    position: sticky; top: 12px; z-index: 5;
  }
  .toolbar label {
    font-family: var(--mono); font-size: 11px; letter-spacing: .12em;
    text-transform: uppercase; color: var(--muted);
  }
  .filters { display: flex; gap: 6px; }
  button {
    font: inherit; font-size: 14px; color: var(--ink); background: transparent;
    border: 1px solid var(--line); border-radius: 999px; padding: 5px 14px; cursor: pointer;
  }
  button[aria-pressed="true"] { background: var(--accent); border-color: var(--accent); color: var(--surface); }
  button:focus-visible, input:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  input[type="search"] {
    font: inherit; font-size: 14px; flex: 1 1 180px; min-width: 140px;
    padding: 6px 12px; border: 1px solid var(--line); border-radius: 999px;
    background: var(--page); color: var(--ink);
  }
  .count { font-family: var(--mono); font-size: 13px; color: var(--muted); margin-left: auto; }

  .group { display: flex; flex-direction: column; gap: 18px; }
  .group[hidden] { display: none; }
  .group-head {
    display: flex; align-items: baseline; gap: 14px; flex-wrap: wrap;
    border-bottom: 1px solid var(--line); padding-bottom: 10px;
  }
  .group-head h2 { font-family: var(--display); font-weight: 400; font-size: 26px; margin: 0; }
  .group-head p { margin: 0; color: var(--muted); font-size: 14px; font-family: var(--mono); }

  .grid { display: grid; gap: 18px; grid-template-columns: repeat(auto-fill, minmax(310px, 1fr)); }

  .card {
    display: flex; flex-direction: column; gap: 10px;
    background: var(--surface); border: 1px solid var(--line);
    border-radius: 12px; padding: 16px; box-shadow: var(--shadow);
  }
  .card[hidden] { display: none; }
  .card-head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
  .card h3 { font-family: var(--display); font-weight: 400; font-size: 19px; margin: 0; }
  .slug { font-family: var(--mono); font-size: 11.5px; color: var(--muted); }
  .desc { margin: 0; font-size: 13.5px; color: var(--muted); min-height: 2.7em; }

  /* Everything below draws in the theme's own values, so a preview is wrong
     only if the theme is. */
  .term {
    background: var(--bg); color: var(--fg); border-radius: 8px;
    padding: 12px 13px; font-family: var(--mono); font-size: 12.5px; line-height: 1.65;
    overflow-x: auto; border: 1px solid rgba(128, 128, 128, .22);
  }
  .line { white-space: pre; }
  .c1 { color: var(--ansi1, var(--fg)); }
  .c2 { color: var(--ansi2, var(--fg)); }
  .c4 { color: var(--ansi4, var(--fg)); }
  .c5 { color: var(--ansi5, var(--fg)); }
  .c6 { color: var(--ansi6, var(--fg)); }
  .c8 { color: var(--ansi8, var(--fg)); }
  .c9 { color: var(--ansi9, var(--fg)); }
  .c10 { color: var(--ansi10, var(--fg)); }
  .c11 { color: var(--ansi11, var(--fg)); }
  .sel { background: var(--sel_bg); color: var(--sel_fg); }
  .cur { background: var(--cursor); }

  .swatches { display: grid; grid-template-columns: repeat(16, 1fr); gap: 2px; }
  .swatches i { height: 14px; border-radius: 2px; }
  .no-palette { margin: 0; font-size: 12px; color: var(--muted); font-style: italic; }

  .facts { display: flex; gap: 16px; margin: 0; font-family: var(--mono); font-size: 11.5px; }
  .facts div { display: flex; gap: 5px; }
  .facts dt { color: var(--muted); }
  .facts dd { margin: 0; font-variant-numeric: tabular-nums; }

  footer { color: var(--muted); font-size: 15px; border-top: 1px solid var(--line); padding-top: 18px; }
"""

    script = """
  const cards = Array.from(document.querySelectorAll(".card"));
  const buttons = Array.from(document.querySelectorAll(".filters button"));
  const search = document.getElementById("q");
  const count = document.getElementById("count");
  let tone = "all";

  function apply() {
    const q = search.value.trim().toLowerCase();
    let shown = 0;
    for (const card of cards) {
      const okTone = tone === "all" || card.dataset.tone === tone;
      const okText = !q || card.textContent.toLowerCase().includes(q);
      const visible = okTone && okText;
      card.hidden = !visible;
      if (visible) shown++;
    }
    count.textContent = shown + " of " + cards.length + " shown";
    for (const group of document.querySelectorAll(".group"))
      group.hidden = !group.querySelector(".card:not([hidden])");
  }

  for (const button of buttons) {
    button.addEventListener("click", () => {
      tone = button.dataset.tone;
      for (const other of buttons) other.setAttribute("aria-pressed", String(other === button));
      apply();
    });
  }
  search.addEventListener("input", apply);
  apply();
"""

    body = f"""<div class="wrap">
  <header class="masthead">
    <p class="eyebrow">tinct · terminal color themes</p>
    <h1>A Hundred Terminals</h1>
    <p class="lede">Every theme that ships with
    <a href="{REPO}">tinct</a>, drawn with its own values — the same background,
    foreground, cursor, selection and sixteen palette entries your terminal receives.
    Each one clears the quality gate: body text at WCAG AA, dim text and every palette
    color separated from the background, a readable selection, a findable cursor, and no
    two colors close enough to confuse. Pick one with <code>tinct</code>, or set it
    directly with <code>tinct set &lt;name&gt;</code>.</p>
  </header>

  <div class="toolbar">
    <label for="q">Filter</label>
    <input type="search" id="q" placeholder="name or description" autocomplete="off">
    <div class="filters" role="group" aria-label="Tone">
      <button type="button" data-tone="all" aria-pressed="true">All</button>
      <button type="button" data-tone="dark" aria-pressed="false">Dark</button>
      <button type="button" data-tone="light" aria-pressed="false">Light</button>
    </div>
    <span class="count" id="count"></span>
  </div>
{section("Dark", f"{len(dark)} themes", dark)}
{section("Light", f"{len(light)} themes", light)}
  <footer>
    <p>{len(themes)} themes, generated from the theme files in
    <a href="{REPO}">solvyxtech/tinct</a>. Each terminal gets its own —
    <code>tinct set &lt;name&gt;</code> here, <code>--default</code> for new windows,
    <code>--all</code> for every terminal at once.</p>
  </footer>
</div>"""

    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>tinct — a hundred terminals</title>
<meta name="description" content="Every terminal color theme bundled with tinct, previewed in its own colors.">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><rect width='16' height='16' rx='3' fill='%23161A20'/><rect x='3' y='4' width='4' height='8' fill='%2386ACD8'/><rect x='9' y='4' width='4' height='8' fill='%23E2703B'/></svg>">
<style>{style}</style>
</head>
<body>
{body}
<script>{script}</script>
</body>
</html>
"""

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        fh.write(page)
    print(f"gallery: {len(themes)} themes ({len(dark)} dark, {len(light)} light) -> "
          f"{os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    build()

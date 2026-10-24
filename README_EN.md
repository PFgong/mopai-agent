# Mopai · LaTeX Studio

Turn Word, PDF, images or a TeX project into downloadable LaTeX. Formulas, figures and
citations are preserved as far as possible, compilation really runs, and the report tells
you plainly what still needs a human check.

It is not lossless one-click conversion — a passing build does not mean the content is
correct.

[简体中文](./README.md)

---

## Three steps

### 1. Install three tools

| Tool | Purpose | Where | Verify with |
| --- | --- | --- | --- |
| **Python 3.10+** | runs the local services | <https://www.python.org/downloads/> | `python --version` |
| **Pandoc** | converts Word / Markdown | <https://github.com/jgm/pandoc/releases> | `pandoc --version` |
| **MiKTeX** | compiles .tex into PDF | <https://miktex.org/download> | `xelatex --version` |

On Windows, tick **"Add Python to PATH"** during the Python install. After installing
MiKTeX, open **MiKTeX Console** and run `Tasks → Update` once, and set
`Always install missing packages on the fly` to **Yes**.

To just browse the demo, no install is needed: `cd dist && python -m http.server 8080`,
then open <http://localhost:8080> and click the sample.

### 2. Double-click `start.bat` (Windows)

From the project root, double-click `start.bat`. It does the rest:

```
check toolchain → prepare Python env → check ports → start services → health check
```

If a tool is missing it tells you which one, where to get it and how to fix it, e.g.:

```
  [WARN] Pandoc not found — DOCX / Markdown conversion unavailable
```

Fix what it reports and double-click again. Missing Python packages are installed
automatically.

### 3. Open the browser

On success it opens a result page listing the address:

- **Workbench**: <http://localhost:8080> ← this is the one you use
- API docs: <http://localhost:8000/docs>
- Agent Token: shown on that page (default `local-dev-token`)

In the workbench, open **Settings** and enter Agent URL `http://localhost:8000` plus that
token. Then upload a document.

**Stop everything**: press `Q` in the launcher window, or double-click `stop.bat`.

---

## What the page can do

**Upload** DOCX, PDF, TeX, ZIP, images, Markdown or TXT. Bundle multi-file TeX projects,
figures and bibliographies into a ZIP and give the entry path (e.g. `paper/main.tex`).
Limit is 60 MB.

**Use your own layout template**: upload a `.tex` under "Layout template" (for journal or
university templates, zip the `.cls`, `.sty` and `.bib` files together). The tool reads its
document class, font size, paper, columns, margins, line spacing, fonts and bibliography
style, shows them in the UI, and applies them to the result. Title and author blocks from
the template are stripped so they never overwrite your document.

**Models** (optional):

| Setting | Used for | Needed when |
| --- | --- | --- |
| Text model | restyling, build repair, Q&A | you typed extra layout instructions |
| VL / OCR model | per-page PDF and image transcription | you process PDFs or images |

Both need a Chat Completions compatible endpoint. Word, TeX and ZIP work without any model.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Python not found" | not installed or not on PATH | reinstall and tick "Add Python to PATH" |
| "Pandoc not found" | not on PATH | add `C:\Program Files\Pandoc\` to PATH |
| "xelatex not found" | TeX missing | install MiKTeX and put it on PATH |
| `could not find the script engine 'perl.exe'` | MiKTeX's latexmk needs Perl | **ignore it** — the tool falls back to running xelatex directly |
| `Undefined control sequence \IfDocumentMetadataTF` | outdated MiKTeX | MiKTeX Console → Tasks → Update |
| `File 'xxx.sty' not found` | missing package | enable MiKTeX on-the-fly installation |
| Port 8000/8001/8080 busy | previous run still alive | run `start.bat -Reset`, or `stop.bat` |
| "cannot reach Agent" | services not up | check `agent/logs/` |

Logs are in `agent/logs/`: `agent.log`, `compiler.log`, `web.log`.

---

## Other ways to start

**macOS / Linux** (no bat script — two terminals):

```bash
cd agent
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Terminal 1: compiler service
COMPILER_TOKEN=my-compiler-token python -m uvicorn compiler:app --host 127.0.0.1 --port 8001

# Terminal 2: Agent service
AGENT_TOKEN=my-agent-token ALLOWED_ORIGINS=http://localhost:8080 \
COMPILER_URL=http://127.0.0.1:8001 COMPILER_TOKEN=my-compiler-token \
python -m uvicorn server:app --host 127.0.0.1 --port 8000

# Terminal 3: page
cd ../dist && python -m http.server 8080 --bind 127.0.0.1
```

**Docker** (long-running servers):

```bash
cd agent
cp .env.example .env      # set AGENT_TOKEN and COMPILER_TOKEN
docker compose up --build -d
```

| Variable | Required | Purpose |
| --- | --- | --- |
| `AGENT_TOKEN` | yes | Sent by the page. Empty means every route returns 503 |
| `COMPILER_TOKEN` | yes | Shared secret, identical in both services |
| `ALLOWED_ORIGINS` | yes | Page origin, e.g. `http://localhost:8080` |
| `COMPILER_URL` | no | Compiler address. Empty skips compilation |
| `DATA_DIR` | no | Job storage, default `./jobs` |
| `PANDOC_PATH` | no | Full path to `pandoc` when it is not on PATH |

---

## Limits

- Automatic checks cover **structural counts** and the **build log** only; `content_status` is always `needs_review`
- PDFs always go through a vision model, so cost scales with page count
- Word field codes, EndNote/Zotero citations, scanned formulas and complex figure crops **need human review**
- Single-user by design: no accounts or tenant isolation. Do not share `AGENT_TOKEN`

Architecture, API and Skill details live in [`agent/README.md`](./agent/README.md);
see [`SECURITY.md`](./SECURITY.md) for security topics.

## License

[MIT](./LICENSE)

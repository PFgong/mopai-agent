# Mopai · LaTeX Studio

Turn Word, PDF, images or a TeX project into downloadable LaTeX. Formulas, figures and
citations are preserved as far as possible, compilation really runs, and the report tells
you plainly what still needs a human check.

It is not lossless one-click conversion — a passing build does not mean the content is
correct.

[简体中文](./README.md)

---

## Pick one path

| What you want | What to install | Time |
| --- | --- | --- |
| **[A] Just look at it** | nothing | 1 min |
| **[B] Process your own docs locally (no Docker)** | Python + Pandoc + TeX | 20 min |
| **[C] Run it on a server** | Docker | 10 min |

Not sure? Pick **B**.

---

## A. Just look (zero install)

`dist/` is a static page with a **real compiled sample** inside; everything is downloadable.

```bash
cd dist
python -m http.server 8080 --bind 127.0.0.1
```

Open <http://localhost:8080> and click the sample.

---

## B. Local setup (no Docker)

### B1. Install these

| # | Tool | Purpose | Required? | Where | Verify with |
| --- | --- | --- | --- | --- | --- |
| 1 | **Python 3.9+** | runs the backend | yes | <https://www.python.org/downloads/> | `python --version` |
| 2 | **Pandoc** | converts DOCX / Markdown | only for DOCX, MD, TXT | <https://github.com/jgm/pandoc/releases><br>`brew install pandoc` / `sudo apt install pandoc` | `pandoc --version` |
| 3 | **TeX distribution** | compiles .tex into PDF | only if you want PDF | MiKTeX <https://miktex.org/download> (Windows)<br>`sudo apt install texlive-xetex latexmk` | `xelatex --version` |
| 4 | **Models** | PDF/image transcription, restyling, Q&A | optional | any Chat Completions compatible endpoint | "Test connection" in the UI |

> **Pandoc must be on PATH.** If it is not, set `PANDOC_PATH` to the full path of `pandoc.exe`.

### B2. Install Python deps

```bash
cd agent
python -m venv .venv
source .venv/bin/activate          # Windows: source .venv/Scripts/activate
pip install -r requirements.txt
```

### B3. Start it (two terminals)

**Terminal 1 — compiler service**
```bash
cd agent
export COMPILER_TOKEN=my-compiler-token
.venv/Scripts/python -m uvicorn compiler:app --host 127.0.0.1 --port 8001
```

**Terminal 2 — Agent service**
```bash
cd agent
export AGENT_TOKEN=my-agent-token
export ALLOWED_ORIGINS=http://localhost:8080
export COMPILER_URL=http://127.0.0.1:8001
export COMPILER_TOKEN=my-compiler-token
.venv/Scripts/python -m uvicorn server:app --host 127.0.0.1 --port 8000
```

Optionally serve the page: `cd dist && python -m http.server 8080 --bind 127.0.0.1`

### B4. Use it

Open <http://localhost:8080> → Settings → Agent URL `http://localhost:8000`,
Agent Token `my-agent-token`. Base URLs need the vendor's `/v1` prefix.

Or skip the browser:

```bash
curl http://127.0.0.1:8000/health
ID=$(curl -s -X POST -H "X-Agent-Token: my-agent-token" -F "file=@my.tex" \
  -F 'config={"template":"article","engine":"xelatex"}' \
  http://127.0.0.1:8000/jobs | python -c "import sys,json;print(json.load(sys.stdin)['id'])")
curl -s -H "X-Agent-Token: my-agent-token" http://127.0.0.1:8000/jobs/$ID
```

---

## C. Docker (recommended for servers)

```bash
cd agent
cp .env.example .env      # set AGENT_TOKEN and COMPILER_TOKEN
docker compose up --build -d
```

Generate tokens with `python -c "import secrets;print(secrets.token_urlsafe(32))"`.

| Variable | Required | Purpose |
| --- | --- | --- |
| `AGENT_TOKEN` | yes | Sent by the page. Empty means every route returns 503 |
| `ALLOWED_ORIGINS` | yes | Page origin, e.g. `http://localhost:8080` |
| `COMPILER_TOKEN` | yes | Shared secret, identical in both services |
| `COMPILER_URL` | no | Compiler address. Empty skips compilation |
| `DATA_DIR` | no | Job storage, default `./jobs` |

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "未找到 pandoc" | Pandoc missing or not on PATH | see B1 #2 |
| `could not find the script engine 'perl.exe'` | MiKTeX's latexmk needs Perl | **ignore it** — the tool falls back to running xelatex directly |
| `Undefined control sequence \IfDocumentMetadataTF` | outdated MiKTeX | MiKTeX Console → Tasks → Update |
| `compile_status` is `not_run` | `COMPILER_URL` unset | start the compiler service and set it |
| Compile always fails on a missing package | compiler has no network | for Docker, edit `Dockerfile.compiler` and rebuild |
| "无法连接 Agent" | Agent down or wrong `ALLOWED_ORIGINS` | check terminal 2 |
| Deployment bundle download 404s | `dist/mopai-agent.zip` not generated | run `python scripts/package.py` |

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

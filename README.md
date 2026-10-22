# 墨排 · LaTeX Studio

把 Word、PDF、图片或 TeX 工程转成可下载的 LaTeX。**公式、图片、引用尽量保留，编译真实执行，并明确告诉你哪些内容仍需人工复核。**

它不是"一键无损转换"——编译通过不等于内容正确，报告里会单独列出待复核项。

[English](./README_EN.md)

---

## 先选一条路

| 你想做什么 | 要装什么 | 大致耗时 |
| --- | --- | --- |
| **[A] 只看效果** | 什么都不装 | 1 分钟 |
| **[B] 在本机处理自己的文档（不用 Docker）** | Python + Pandoc + TeX | 20 分钟 |
| **[C] 在服务器上长期跑** | Docker | 10 分钟 |

不确定就选 **B**，它最接近真实使用，也不挑系统。

---

## A. 只想看看效果（零安装）

`dist/` 是纯静态网页，内置一份**真实编译出来的示例**，所有文件都能下载。

```bash
cd dist
python -m http.server 8080 --bind 127.0.0.1
```

打开 <http://localhost:8080> → 点「体验示例」。

示例模式不调用任何模型，也不会碰你上传的文件。要处理自己的文档，往下看 B 或 C。

---

## B. 本机部署（免 Docker）

### B1. 装这四个东西

| # | 工具 | 干什么用的 | 必须要吗 | 下载地址 | 装完怎么验证 |
| --- | --- | --- | --- | --- | --- |
| 1 | **Python 3.9+** | 跑后端 | 必须 | <https://www.python.org/downloads/> | `python --version` |
| 2 | **Pandoc** | 转 DOCX / Markdown | 只处理 DOCX、MD、TXT 时才要 | <https://github.com/jgm/pandoc/releases> 选 `windows-x86_64.msi`（Windows）<br>`brew install pandoc`（macOS）<br>`sudo apt install pandoc`（Linux） | `pandoc --version` |
| 3 | **TeX 发行版** | 把 .tex 编译成 PDF | 想要 PDF 就要 | Windows 推荐 MiKTeX <https://miktex.org/download><br>macOS/Linux：`sudo apt install texlive-xetex latexmk` | `xelatex --version` |
| 4 | **模型**（可选） | 转 PDF/图片、改版式、问答 | 可选 | 任意 Chat Completions 兼容接口 | 网页里「测试连接」 |

> **Pandoc 必须在 PATH 里。** Windows 的 `.msi` 一般会自动加；装完先跑 `pandoc --version` 确认。如果没加上，手动把 `C:\Program Files\Pandoc\` 加进 PATH，或者设置环境变量 `PANDOC_PATH` 指向 `pandoc.exe` 的完整路径。

### B2. 装 Python 依赖

```bash
cd agent
python -m venv .venv

# Windows Git Bash / macOS / Linux：
source .venv/Scripts/activate      # macOS/Linux 用 source .venv/bin/activate
# Windows CMD：
# .venv\Scripts\activate.bat

pip install -r requirements.txt
```

想跑测试再装一项：`pip install -r requirements-dev.txt`

### B3. 启动（开两个终端 + 一个可选）

**终端 1 —— 编译服务**
```bash
cd agent
export COMPILER_TOKEN=my-compiler-token      # Windows CMD 用 set
.venv/Scripts/python -m uvicorn compiler:app --host 127.0.0.1 --port 8001
```

**终端 2 —— Agent 服务**
```bash
cd agent
export AGENT_TOKEN=my-agent-token
export ALLOWED_ORIGINS=http://localhost:8080
export COMPILER_URL=http://127.0.0.1:8001
export COMPILER_TOKEN=my-compiler-token
.venv/Scripts/python -m uvicorn server:app --host 127.0.0.1 --port 8000
```

**终端 3 —— 网页（可选，也可以只开这一个先看效果）**
```bash
cd dist
python -m http.server 8080 --bind 127.0.0.1
```

> 只想验证接口、不想开网页？跳过终端 3，直接用下面的 curl。

### B4. 用起来

打开 <http://localhost:8080> →「模型设置」里填：

- Agent 地址：`http://localhost:8000`
- Agent Token：`my-agent-token`
- 模型（可选）：Base URL 要带厂商要求的 `/v1` 前缀

然后上传文档，选模板，点「开始自动排版」。

**不打开网页也能测：**

```bash
# 看服务状态（pandoc 为空说明没装好）
curl http://127.0.0.1:8000/health

# 传一个 tex 文件
ID=$(curl -s -X POST -H "X-Agent-Token: my-agent-token" \
  -F "file=@my.tex" \
  -F 'config={"template":"article","engine":"xelatex"}' \
  http://127.0.0.1:8000/jobs | python -c "import sys,json;print(json.load(sys.stdin)['id'])")

# 看结果
curl -s -H "X-Agent-Token: my-agent-token" http://127.0.0.1:8000/jobs/$ID
```

---

## C. Docker 部署（服务器推荐）

需要 Docker 和 Docker Compose。

```bash
cd agent
cp .env.example .env          # 编辑 .env：改掉 AGENT_TOKEN 和 COMPILER_TOKEN
docker compose up --build -d
```

生成两个随机令牌：

```bash
python -c "import secrets;print(secrets.token_urlsafe(32))"
```

- Agent 接口：<http://localhost:8000>，API 文档在 `/docs`
- 首次构建要拉 TeX Live 和中文字体，慢一点正常
- 网页部分同 B3 的终端 3

**环境变量一览**（写在 `agent/.env` 里）：

| 变量 | 必须 | 说明 |
| --- | --- | --- |
| `AGENT_TOKEN` | 是 | 网页每次请求都要带。留空则所有接口返回 503 |
| `ALLOWED_ORIGINS` | 是 | 允许访问的网页地址，如 `http://localhost:8080` |
| `COMPILER_TOKEN` | 是 | 两个服务共用的令牌，必须一致 |
| `COMPILER_URL` | 否 | 编译服务地址。留空就跳过编译，只生成源码 |
| `DATA_DIR` | 否 | 任务文件存放位置，默认 `./jobs` |

---

## 出问题先看这里

| 现象 | 原因 | 怎么办 |
| --- | --- | --- |
| 提示「未找到 pandoc」 | Pandoc 没装或不在 PATH | 见 B1 第 2 项 |
| `could not find the script engine 'perl.exe'` | MiKTeX 的 latexmk 需要 Perl | **不用管**——程序会自动改用 xelatex 直接编译。想用 latexmk 就装 Strawberry Perl |
| `Undefined control sequence \IfDocumentMetadataTF` | MiKTeX 太久没更新 | 打开 MiKTeX Console → Tasks → Update |
| 报告里 `compile_status` 是 `not_run` | 没配 `COMPILER_URL` | 按 B3 启动编译服务并配置该变量 |
| 编译一直失败 | 缺宏包 | Docker 部署的编译容器无网络，只能改 `Dockerfile.compiler` 重新构建 |
| 网页提示「无法连接 Agent」 | Agent 没启动，或 `ALLOWED_ORIGINS` 没写当前地址 | 检查终端 2，核对地址端口 |
| 页面上的「下载部署包」404 | `dist/mopai-agent.zip` 没生成 | 跑 `python scripts/package.py` |

---

## 它的边界

- 自动检查只覆盖**结构计数**和**编译日志**，没有视觉/语义比对，`content_status` 永远是 `needs_review`
- PDF 一律走视觉模型转录，页数多时成本取决于你选的模型
- Word 域引用、EndNote/Zotero 引用、扫描公式、复杂图形裁剪**必须人工复核**
- 单用户设计：没有账号体系和租户隔离，别把 `AGENT_TOKEN` 给别人

更详细的架构、API、Skill 说明在 [`agent/README.md`](./agent/README.md)，安全相关问题见 [`SECURITY.md`](./SECURITY.md)。

## 许可证

[MIT](./LICENSE)

# 墨排 · LaTeX Studio

把 Word、PDF、图片或 TeX 工程转成可下载的 LaTeX。公式、图片、引用尽量保留，编译真实执行，并明确告诉你哪些内容仍需人工复核。

不是"一键无损转换"——编译通过不等于内容正确，报告里会单独列出待复核项。

[English](./README_EN.md)

---

## 怎么用：三步

### 1. 装三个工具

| 工具 | 干什么用的 | 下载地址 | 装完验证 |
| --- | --- | --- | --- |
| **Python 3.10+** | 跑本地服务 | <https://www.python.org/downloads/> | `python --version` |
| **Pandoc** | 转 Word / Markdown | <https://github.com/jgm/pandoc/releases> 选 `windows-x86_64.msi` | `pandoc --version` |
| **MiKTeX** | 把 .tex 编译成 PDF | <https://miktex.org/download> | `xelatex --version` |

Windows 装 Python 时**务必勾选 "Add Python to PATH"**。Pandoc 的 `.msi` 一般会自动加入 PATH；如果 `pandoc --version` 提示找不到，把 `C:\Program Files\Pandoc\` 手动加进 PATH 即可。

装完 MiKTeX，打开 **MiKTeX Console** 做两件事：

1. `Tasks → Update`（更新一次，避免宏包版本太旧）
2. 把 `Always install missing packages on the fly` 设为 **Yes**（缺宏包时自动补装）

什么都不装也能看效果：进 `dist/` 目录跑 `python -m http.server 8080`，打开 <http://localhost:8080> 点「体验示例」。

### 2. 双击 `start.bat`

在项目根目录双击 `start.bat`。它会自动完成剩下的事：

```
检查工具链 → 准备 Python 环境 → 检查端口 → 启动服务 → 健康检查
```

缺什么工具，它会直接告诉你缺哪个、去哪下载、怎么装。比如：

```
  [WARN] Pandoc 未找到 —— DOCX / Markdown 将无法转换
```

照着提示补上再双击一次就行。Python 依赖缺失时脚本会自动安装（国内网络会重试清华镜像）。

### 3. 打开浏览器

启动成功后会自动打开一个结果页，上面写着工作台地址：

- **工作台**：<http://localhost:8080> ← 日常用这个
- 接口文档：<http://localhost:8000/docs>
- Agent Token：结果页里显示（默认 `local-dev-token`）

在工作台右上角「模型设置」里填 Agent 地址 `http://localhost:8000` 和上面的 Token，就可以上传文档了。

**停止服务**：在启动窗口按 `Q` 回车，或双击 `stop.bat`。

---

## 在网页里能做什么

**上传文档**：DOCX、PDF、TeX、ZIP、图片、Markdown、TXT。多个 TeX 子文件、图片和文献请打包成 ZIP，并填写工程内主文件相对路径（如 `paper/main.tex`）。限制 60 MB。

**用你自己的模板排版**：右侧「排版模板」处上传一份 `.tex`（期刊/学校模板请把 `.cls`、`.sty`、`.bib` 一起打包成 `.zip`）。系统会读出它的文档类、字号、纸张、分栏、页边距、行距、字体和参考文献样式，显示在界面上，再把这套版式套到转换结果里。模板自带的标题、作者等署名信息会被剔除，不会盖掉你的文档。

**配置模型**（可选）：

| 配置 | 用途 | 什么时候需要 |
| --- | --- | --- |
| 文本模型 | 版式调整、编译修复、问答 | 填了「额外排版要求」才需要 |
| VL / OCR 模型 | PDF 和图片逐页转录 | 处理 PDF / 图片才需要 |

两者都要求 Chat Completions 兼容接口。不配模型也能处理 Word、TeX 和 ZIP。

---

## 出问题先看这里

| 现象 | 原因 | 怎么办 |
| --- | --- | --- |
| 提示「未找到 Python」 | 没装或没勾 Add Python to PATH | 重装 Python 并勾上那个选项 |
| 提示「未找到 pandoc」 | Pandoc 不在 PATH | 把 `C:\Program Files\Pandoc\` 加进 PATH |
| 提示「xelatex 未找到」 | TeX 没装 | 装 MiKTeX 并加入 PATH |
| `could not find the script engine 'perl.exe'` | MiKTeX 的 latexmk 需要 Perl | **不用管**，程序会自动改用 xelatex 直接编译 |
| `Undefined control sequence \IfDocumentMetadataTF` | MiKTeX 太久没更新 | MiKTeX Console → Tasks → Update |
| `File 'xxx.sty' not found` | 缺宏包 | 把 MiKTeX 的自动装包设为 Yes |
| 端口 8000/8001/8080 被占用 | 上次的服务没关 | 用 `start.bat -Reset`，或双击 `stop.bat` |
| 网页提示「无法连接 Agent」 | 服务没起来 | 看 `agent/logs/` 下的日志 |

服务日志在 `agent/logs/`：`agent.log`、`compiler.log`、`web.log`。

---

## 其他启动方式

**macOS / Linux**（没有 bat 脚本，手动开两个终端）：

```bash
cd agent
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 终端 1：编译服务
COMPILER_TOKEN=my-compiler-token python -m uvicorn compiler:app --host 127.0.0.1 --port 8001

# 终端 2：Agent 服务
AGENT_TOKEN=my-agent-token ALLOWED_ORIGINS=http://localhost:8080 \
COMPILER_URL=http://127.0.0.1:8001 COMPILER_TOKEN=my-compiler-token \
python -m uvicorn server:app --host 127.0.0.1 --port 8000

# 终端 3：网页
cd ../dist && python -m http.server 8080 --bind 127.0.0.1
```

**Docker**（服务器上长期跑）：

```bash
cd agent
cp .env.example .env      # 改掉 AGENT_TOKEN 和 COMPILER_TOKEN
docker compose up --build -d
```

环境变量一览：

| 变量 | 必须 | 说明 |
| --- | --- | --- |
| `AGENT_TOKEN` | 是 | 网页每次请求都要带，留空则所有接口返回 503 |
| `COMPILER_TOKEN` | 是 | 两个服务共用，必须一致 |
| `ALLOWED_ORIGINS` | 是 | 允许访问的网页地址 |
| `COMPILER_URL` | 否 | 编译服务地址，留空则跳过编译只生成源码 |
| `DATA_DIR` | 否 | 任务文件存放位置，默认 `./jobs` |
| `PANDOC_PATH` | 否 | Pandoc 不在 PATH 时指向 `pandoc.exe` |

---

## 它的边界

- 自动检查只覆盖**结构计数**和**编译日志**，没有视觉/语义比对，`content_status` 永远是 `needs_review`
- PDF 一律走视觉模型转录，页数多时成本取决于你选的模型
- Word 域引用、EndNote/Zotero 引用、扫描公式、复杂图形裁剪**必须人工复核**
- 单用户设计：没有账号体系和租户隔离，别把 `AGENT_TOKEN` 给别人

更详细的架构、API、Skill 说明见 [`agent/README.md`](./agent/README.md)，安全相关问题见 [`SECURITY.md`](./SECURITY.md)。

## 许可证

[MIT](./LICENSE)

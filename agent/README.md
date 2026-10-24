# 墨排 Agent · 可运行 MVP

> 本文件是后端部署说明。项目总览、快速开始与贡献指南见[根目录 README](../README.md)。

网页为独立的静态工作台；真实文档处理由本服务和隔离 TeX 容器完成。示例模式不调用模型，也不假装转换用户文件。

## 启动

**Windows 一键启动**：在项目根目录双击 `start.bat`（内部调用 `scripts/start.ps1`）。它会检查 Python / Pandoc / TeX / Perl、准备虚拟环境、检查端口，然后启动编译服务（8001）、Agent 服务（8000）和静态工作台（8080），成功后在浏览器打开结果页；缺什么工具会直接给出下载地址与修复办法。停止用 `stop.bat`。细节见[根目录 README](../README.md)。

**Docker**：需要 Docker + Compose。复制 .env.example 为 .env，设置随机 AGENT_TOKEN、**COMPILER_TOKEN** 和允许的网页来源，然后运行：

```sh
docker compose up --build -d
```

启动后接口在 http://localhost:8000，API 文档在 /docs。在网页“模型设置”填写 Agent 地址、Agent Token、文本及 VL 模型地址/名称/API Key。地址为 Chat Completions 兼容 Base URL，含厂商要求的 /v1 前缀。网页只保存非敏感偏好；密钥保留在当前页面内存，刷新需重填。

HTTPS 网页应连接有 HTTPS 反向代理的 Agent。若在本地使用，可将工作台 dist 目录通过 python -m http.server 8080 --bind 127.0.0.1 提供，在 http://localhost:8080 打开。不要把 HTTP 内网服务暴露到公网。生产部署应加 HTTPS、用户认证、租户隔离与配额。

改动本目录后运行 `python scripts/package.py` 重新生成 `dist/mopai-agent.zip`，否则工作台上的「下载部署包」按钮会 404。

## 已实现

- DOCX 经 Pandoc 提取 LaTeX 和媒体；PDF/图片逐页调用用户配置的 VL，以 JSON 返回正文、图形裁剪框和不确定项。
- TeX/ZIP 保留原工程；允许指定 ZIP 主文件，支持附带 bib、图片及自定义 cls/sty。
- 内置模板：中文论文、英文论文、双栏论文。对已有 TeX 默认保留原模板；可填写额外排版指令并配置文本模型修改。
- 自定义排版模板：额外上传 `.tex`（或含 .cls/.sty/.bib 的 `.zip`），`POST /jobs` 的 `template` 字段接收。系统用正则读出文档类、字号、纸张、分栏、页边距、行距、字体与参考文献样式，经 `POST /template/analyze` 返回给界面展示，并用模板导言区替换生成文档的导言区。模板自带的 `\title` / `\author` 等署名会被剔除；ZIP 中的辅助文件并入输出工程。输入为完整 TeX 工程（ZIP）时不套用，仅提示。
- 真实隔离 XeLaTeX/LuaLaTeX/pdfLaTeX + latexmk 编译；最多两次模型修复；结果 PDF、源码、ZIP、日志与报告下载。
- 编译工具兼容：优先用 latexmk；找不到时（例如未装 Perl 的 MiKTeX）自动改用 xelatex/pdflatex 直接编译，并尽力处理参考文献。可用 `LATEXMK_BIN` 指定路径。
- 编译超时可靠：输出写入临时文件而非管道，超时后杀掉整个进程树（Windows 用 `taskkill /T`）。否则被杀的 latexmk 会留下 xelatex 孙进程继续持有管道，`communicate()` 会永久阻塞，表现为任务永远停在“编译中”。
- 环境类报错提示：日志里出现 `Undefined control sequence`、`x.sty not found`、`no output was made` 时，在日志顶部追加“发行版过旧 / 缺宏包”的人话解释与处理方式。
- 结构数量变化、日志、缺字、溢出和未解析引用提示；内容状态始终保留“待复核”。
- LaTeX 问答直接返回解决方案，忽略 reasoning_content 并过滤 think 标签。
- 单个文件 60 MB，ZIP 解压合计 60 MB/500 文件，PDF 30 页，最多两个处理任务。等待和任务记录在单进程内存中；文件存 Docker 数据卷。
- 编译容器以 `COMPILER_TOKEN` 校验调用方，Agent 每次请求携带该令牌；未设置时不校验，仅在容器除 Agent 外不可达时可接受。
- ZIP 解包拒绝绝对路径、`..` 穿越、反斜杠路径与符号链接，并按实际解压字节数计费以防 zip bomb。

## 当前边界

本版不宣称任意复杂论文能无损还原。复杂 Word 域、Zotero/EndNote 引用、扫描公式、多栏阅读顺序和复杂图形裁剪需人工检查。PDF/图片每页使用 VL，尚未实现原生 PDF 优先抽取、自适应 OCR、全量视觉语义比对和引用元数据联网补全。布局修复中的数量检查是防误删的基础约束，不能证明语义一致。

服务重启后内存任务索引丢失，不能继续查询旧任务；需删除数据卷或人工清理旧目录。任务保留至用户删除，生产需加入数据库、到期清理及取消机制。此版本是个人单用户 MVP，不是多租户服务。兼容接口的上下文长度和图像协议依模型而异；不含原生 Anthropic/Gemini 适配器。不要将 Agent Token 交给其他用户。

编译器无公网出口，因此必须预装所需 TeX 包；禁止 shell escape。额外宏包通过更新编译镜像安装，不能自动开放命令执行。对于互不信任的公开用户，建议每任务启动独立沙箱或微虚拟机；目前是串行复用的隔离编译容器。

## Skill

skills/typeset-latex 为配套 Skill，可复制到目标 Agent 的技能目录。该交付不代表已安装进个人技能列表。需给宿主配置 HTTP 工具或本地编译/文档工具。Skill 是策略和流程，Python Agent 是执行实现。

## 自测

```sh
pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
```

官方参考：[Pandoc 用户指南](https://pandoc.org/MANUAL.html)、[latexmk](https://ctan.org/pkg/latexmk)。

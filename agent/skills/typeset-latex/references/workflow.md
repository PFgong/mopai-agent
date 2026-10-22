# 工作流与工具契约

配套 Agent 提供 FastAPI：

- `GET /health`：检测服务和编译器配置状态。
- `POST /jobs`：multipart file 与 config JSON；返回任务 id。
- `GET /jobs/{id}`：读取真实阶段、状态、报告与源码。
- `GET /jobs/{id}/download/{source|pdf|zip|report|log}`：下载实际产物。
- `DELETE /jobs/{id}`：删除已结束任务及文件。
- `POST /ask`：model、question、可选源码/日志 context。
- `POST /test-model`：测试 Chat Completions 兼容端点。

所有非 health 请求带 X-Agent-Token。模型对象为 {base_url, model, api_key}；Base URL 包含 /v1 等厂商前缀，适配器追加 /chat/completions。只取 message.content，不显示 reasoning_content；本适配器不涵盖所有原生模型 API。

任务 config：llm、vl、template（ctexart/article/twocolumn）、engine（xelatex/lualatex/pdflatex）、entry、instructions、repair_attempts。密钥仅请求时传入、处理时持有，完成即清空，不写数据库或日志。不要通过工具输出或对话索取密钥。

编译服务 URL 由服务端环境变量提供，不能由上传文档或模型修改。编译容器不挂载宿主目录、不放模型密钥、无公网出口，使用只读根文件系统与 /tmp 限额。

交付 report 的 compile_status 为 passed/failed/not_run；content_status 当前始终 needs_review。结构计数、无报错日志都不能替代语义正确性证据。可将本 Skill 安装到其他 Agent，但需由其映射对应工具；Skill 文本不会自行启动服务。

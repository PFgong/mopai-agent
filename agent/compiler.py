"""Run only in the isolated compiler container, without model keys or host volumes."""
import base64, os, secrets, shutil, signal, subprocess, tempfile, threading
from pathlib import Path
from fastapi import Depends, FastAPI, Header, UploadFile, File, Form, HTTPException
from common import unpack, MAX_BYTES
app=FastAPI(title='Isolated TeX compiler')
LOCK=threading.Lock()
COMPILER_TOKEN=os.environ.get('COMPILER_TOKEN','')
# Override when latexmk is not on PATH (for example a portable MiKTeX install).
LATEXMK=os.environ.get('LATEXMK_BIN','latexmk')
def kill(proc):
    """Terminate a timed-out build, including everything it spawned.

    On Windows Popen.kill() only ends the direct child — when latexmk is used
    that is perl.exe, and the TeX engine it started keeps running and keeps the
    stdout pipe open. A later communicate() would then block forever instead of
    reporting the timeout, so we also ask Windows to kill the whole tree.
    """
    if hasattr(os,'killpg'):
        try:
            os.killpg(proc.pid,signal.SIGKILL)
            return
        except Exception:
            pass
    try:
        proc.kill()
    except Exception:
        pass
    if os.name=='nt':
        try:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],
                           stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=20)
        except Exception:
            pass
@app.get('/health')
def health():
    return {'ok':True,'latexmk':shutil.which(LATEXMK) or '','latexmk_bin':LATEXMK}
def authorize(x_compiler_token: str=Header(default='')):
    """Reject callers that do not hold the shared token.

    Left unenforced when COMPILER_TOKEN is unset, which is only acceptable when the
    container is unreachable from anything but the Agent (as in compose.yaml).
    """
    if not COMPILER_TOKEN: return
    if not secrets.compare_digest(x_compiler_token,COMPILER_TOKEN): raise HTTPException(401,'Compiler Token 无效')
def run(cmd,cwd,env,timeout=110):
    """Run a TeX tool, returning (returncode, stdout+stderr bytes).

    Output is collected in a temp file instead of a pipe. With a pipe, killing a
    timed-out build can still leave grandchildren holding the write end open, and
    communicate() would then wait forever rather than returning the timeout.
    """
    try:
        with tempfile.TemporaryFile() as sink:
            proc=subprocess.Popen(cmd,cwd=cwd,stdout=sink,stderr=subprocess.STDOUT,start_new_session=True,env=env)
            timed_out=False
            try:
                proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out=True
                kill(proc)
                try:
                    proc.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    pass
            sink.flush(); sink.seek(0)
            output=sink.read()
    except FileNotFoundError:
        return 127, ('未找到可执行文件：'+cmd[0]).encode('utf-8')
    if timed_out:
        return 124, output+('\n[mopai] 编译超过 %d 秒，已终止。\n' % timeout).encode('utf-8')
    return proc.returncode, output


SAFE=['-no-shell-escape','-interaction=nonstopmode','-halt-on-error','-file-line-error']
# Output that means the build toolchain itself is broken, not the document.
TOOLING_MARKERS=('perl','script engine','command not found','no such file or directory','latexmk 未找到')

# Environment problems that surface as a document error. Without a hint the user
# sees only "Undefined control sequence" and has no idea their TeX install is stale.
ENV_HINTS=(
    ('undefined control sequence',
     '看起来是 TeX 发行版与宏包版本不匹配（常见于发行版过旧）。'
     'MiKTeX：打开 MiKTeX Console → Tasks → Update；TeX Live：运行 tlmgr update --all。'),
    ("sty' not found",
     '缺少宏包。MiKTeX 请在控制台把 "Always install missing packages on the fly" 设为 Yes；'
     'TeX Live 请用 tlmgr install <宏包> 安装。'),
    ('no output was made',
     '编译没有产出 PDF，请查看下方日志中第一条报错。'),
)


def env_hints(log):
    """Return a human-readable block explaining failures that are not the document's fault."""
    low=log.lower()
    tips=['[mopai] '+tip for marker,tip in ENV_HINTS if marker in low]
    return ('\n'.join(tips)+'\n\n') if tips else ''


def direct_build(engine, name, stem, cwd, env):
    """Drive the TeX engine without latexmk: two passes plus best-effort bibliography."""
    output, rc = b'', 0
    for _ in range(2):
        rc, out = run([engine, *SAFE, './'+name], cwd, env)
        output += out
        if rc != 0:
            break
    if rc == 0 and any(cwd.rglob('*.bib')):
        for tool in ('biber', 'bibtex'):
            if shutil.which(tool):
                _, out = run([tool, stem], cwd, env, 60); output += out
                rc, out = run([engine, *SAFE, './'+name], cwd, env); output += out
                break
    return rc, output, cwd/(stem+'.pdf')


def compile_bytes(data,entry,engine):
    p=Path(entry)
    if p.anchor or '..' in p.parts or p.suffix!='.tex' or '\\' in entry: raise ValueError('无效的主文件路径')
    if engine not in {'xelatex','lualatex','pdflatex'}: raise ValueError('不支持的编译引擎')
    with LOCK, tempfile.TemporaryDirectory(prefix='tex-') as work:
        root=Path(work); unpack(data,root)
        if not (root/p).is_file(): raise ValueError('主文件不存在')
        cwd=root/p.parent
        env={**os.environ,'openin_any':'p','openout_any':'p','shell_escape':'f','TEXMFOUTPUT':str(root),'HOME':str(root)}
        name=p.name; stem=p.stem
        if not shutil.which(engine):
            return {'ok':False,'mode':'unavailable','log':f'未找到 {engine}；请安装 TeX 发行版并加入 PATH。'}
        if shutil.which(LATEXMK):
            rc,output=run([LATEXMK,'-norc',{'xelatex':'-xelatex','lualatex':'-lualatex','pdflatex':'-pdf'}[engine],*SAFE,'-outdir=build','./'+name],cwd,env)
            pdf=cwd/'build'/p.with_suffix('.pdf').name
            mode='latexmk'
            # MiKTeX ships latexmk as a Perl script: it is present but unusable
            # without Perl. Fall back rather than reporting a bogus document error.
            if rc!=0 and not pdf.exists():
                low=output.decode(errors='replace').lower()
                if any(m in low for m in TOOLING_MARKERS):
                    rc,extra,pdf=direct_build(engine,name,stem,cwd,env)
                    output=output+('\n[mopai] latexmk 不可用，已改用 '+engine+' 直接编译。\n').encode('utf-8')+extra
                    mode=engine+'（latexmk 不可用，已直接调用）'
        else:
            rc,output,pdf=direct_build(engine,name,stem,cwd,env)
            mode=engine+'（未找到 latexmk，已直接调用）'
        result={'ok':rc==0 and pdf.exists(),'mode':mode,'log':output.decode(errors='replace')[-60000:]}
        if not result['ok']:
            result['log']=env_hints(result['log'])+result['log']
        if result['ok']: result['pdf_base64']=base64.b64encode(pdf.read_bytes()).decode()
        return result
@app.post('/compile',dependencies=[Depends(authorize)])
async def compile(file:UploadFile=File(...),entry:str=Form('main.tex'),engine:str=Form('xelatex')):
    import asyncio
    data=await file.read(MAX_BYTES+1)
    if len(data)>MAX_BYTES: raise HTTPException(413,'文件过大')
    try: return await asyncio.to_thread(compile_bytes,data,entry,engine)
    except ValueError as e: raise HTTPException(400,str(e))

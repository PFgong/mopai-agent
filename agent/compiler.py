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
    """Terminate a timed-out build on both POSIX and Windows.

    os.killpg and signal.SIGKILL do not exist on Windows, so a bare call there
    raises AttributeError exactly when we are already in trouble.
    """
    if hasattr(os,'killpg'):
        os.killpg(proc.pid,signal.SIGKILL)
    else:
        proc.kill()
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
    """Run a TeX tool, returning (returncode, stdout+stderr bytes)."""
    try:
        proc=subprocess.Popen(cmd,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True,env=env)
    except FileNotFoundError:
        return 127, ('未找到可执行文件：'+cmd[0]).encode()
    try:
        output,_=proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill(proc); output,_=proc.communicate()
        return 124, output+'\n[mopai] 编译超时，已终止。'.encode('utf-8')
    return proc.returncode, output


def compile_bytes(data,entry,engine):
    p=Path(entry)
    if p.anchor or '..' in p.parts or p.suffix!='.tex' or '\\' in entry: raise ValueError('无效的主文件路径')
    if engine not in {'xelatex','lualatex','pdflatex'}: raise ValueError('不支持的编译引擎')
    with LOCK, tempfile.TemporaryDirectory(prefix='tex-') as work:
        root=Path(work); unpack(data,root)
        if not (root/p).is_file(): raise ValueError('主文件不存在')
        cwd=root/p.parent
        env={**os.environ,'openin_any':'p','openout_any':'p','shell_escape':'f','TEXMFOUTPUT':str(root),'HOME':str(root)}
        safe=['-no-shell-escape','-interaction=nonstopmode','-halt-on-error','-file-line-error']
        if shutil.which(LATEXMK):
            rc,output=run([LATEXMK,'-norc',{'xelatex':'-xelatex','lualatex':'-lualatex','pdflatex':'-pdf'}[engine],*safe,'-outdir=build','./'+p.name],cwd,env)
            pdf=cwd/'build'/p.with_suffix('.pdf').name
            mode='latexmk'
        else:
            # No latexmk (a MiKTeX install without Perl, or a portable TeX tree):
            # drive the engine directly. Bibliography support is best-effort.
            if not shutil.which(engine):
                return {'ok':False,'log':f'未找到 {LATEXMK} 与 {engine}；请安装 TeX 发行版并加入 PATH，或设置 LATEXMK_BIN 指向 latexmk 可执行文件。'}
            output, rc = b'', 0
            for _ in range(2):
                rc,out=run([engine,*safe,'./'+p.name],cwd,env)
                output+=out
                if rc!=0: break
            stem=p.stem
            if rc==0 and any(cwd.rglob('*.bib')):
                for tool in ('biber','bibtex'):
                    if shutil.which(tool):
                        _,out=run([tool,stem],cwd,env,60); output+=out
                        rc,out=run([engine,*safe,'./'+p.name],cwd,env); output+=out
                        break
            pdf=cwd/p.with_suffix('.pdf').name
            mode=engine+'（未找到 latexmk，已直接调用）'
        result={'ok':rc==0 and pdf.exists(),'mode':mode,'log':output.decode(errors='replace')[-60000:]}
        if result['ok']: result['pdf_base64']=base64.b64encode(pdf.read_bytes()).decode()
        return result
@app.post('/compile',dependencies=[Depends(authorize)])
async def compile(file:UploadFile=File(...),entry:str=Form('main.tex'),engine:str=Form('xelatex')):
    import asyncio
    data=await file.read(MAX_BYTES+1)
    if len(data)>MAX_BYTES: raise HTTPException(413,'文件过大')
    try: return await asyncio.to_thread(compile_bytes,data,entry,engine)
    except ValueError as e: raise HTTPException(400,str(e))

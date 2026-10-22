"""Build dist/mopai-agent.zip, the deployment bundle the workbench links to.

Run after any change under agent/, otherwise the "下载 Agent＋Skill 部署包"
buttons in dist/index.html and dist/guide.html will 404.

    python scripts/package.py
"""
import sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'agent'
OUTPUT = ROOT / 'dist' / 'mopai-agent.zip'

# Directories never shipped: caches and any job data left from local runs.
SKIP_DIRS = {'__pycache__', '.pytest_cache', 'jobs', 'data', '.venv', 'venv'}
# Secrets are never bundled. .env.example is the only env file that ships.
SKIP_FILES = {'.env'}
SKIP_SUFFIX = {'.pyc', '.pyo', '.log'}


def main() -> int:
    if not SOURCE.is_dir():
        print(f'找不到源目录：{SOURCE}', file=sys.stderr)
        return 1
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with zipfile.ZipFile(OUTPUT, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(SOURCE.rglob('*')):
            rel = path.relative_to(SOURCE)
            if any(part in SKIP_DIRS or part.startswith('.git') for part in rel.parts):
                continue
            if path.is_dir() or path.is_symlink():
                continue
            if path.name in SKIP_FILES or path.suffix in SKIP_SUFFIX:
                continue
            z.write(path, Path('agent') / rel)
            count += 1
    size = OUTPUT.stat().st_size
    print(f'已生成 {OUTPUT.relative_to(ROOT)}（{count} 个文件，{size / 1024:.1f} KB）')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

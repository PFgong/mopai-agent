import io, os, stat, zipfile
from pathlib import Path

MAX_BYTES = 60 * 1024 * 1024
ALLOWED = {'.tex','.bib','.bst','.cls','.sty','.png','.jpg','.jpeg','.pdf','.eps','.txt','.md','.csv','.json','.log','.bbl','.bbx','.cbx','.def','.cfg','.fd','.clo','.svg'}
CHUNK = 256 * 1024


def unpack(data: bytes, target: Path):
    """Extract a project ZIP with path traversal, symlink and zip-bomb defences.

    The ``file_size`` declared in ZIP metadata is untrusted: entries are read in
    bounded chunks, the real decompressed length is compared against the declared
    size, and the running total counts bytes actually produced. A forged header
    therefore cannot slip an oversized payload through.
    """
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            _extract(z, target)
    except zipfile.BadZipFile:
        raise ValueError('ZIP 文件损坏或不是有效的 ZIP 文件')


def _extract(z, target: Path):
    if len(z.infolist()) > 500:
        raise ValueError('ZIP 文件数量超过 500')
    total = 0
    for item in z.infolist():
        p = Path(item.filename)
        mode = item.external_attr >> 16
        # p.anchor covers drive and root separately. On Windows, Python 3.13
        # is_absolute() is False for root-only paths such as /tmp/x, which would
        # otherwise resolve to C:\tmp\x once joined onto the project directory.
        if p.anchor or '..' in p.parts or '\\' in item.filename or stat.S_ISLNK(mode):
            raise ValueError('ZIP 含不安全的路径或链接')
        if item.is_dir():
            continue
        if p.suffix.lower() not in ALLOWED or p.name.startswith('.'):
            raise ValueError(f'不支持工程文件：{p.name}')
        declared = item.file_size
        if declared > MAX_BYTES:
            raise ValueError(f'{p.name} 声明的大小超过 60 MB')
        chunks, written = [], 0
        with z.open(item) as src:
            while True:
                chunk = src.read(CHUNK)
                if not chunk:
                    break
                written += len(chunk)
                if declared and written > declared:
                    raise ValueError(f'{p.name} 实际解压大小超过声明值，已拒绝')
                if written > MAX_BYTES:
                    raise ValueError(f'{p.name} 解压后超过 60 MB')
                chunks.append(chunk)
        blob = b''.join(chunks)
        total += len(blob)
        if total > MAX_BYTES:
            raise ValueError('ZIP 解压后超过 60 MB')
        dest = target / p
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(blob)


def pack(root: Path, exclude=()):
    b = io.BytesIO()
    with zipfile.ZipFile(b, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in root.rglob('*'):
            if p.is_file() and not p.is_symlink() and p.name not in exclude and p.suffix.lower() in ALLOWED and not any(part in {'build', '__pycache__'} for part in p.relative_to(root).parts):
                z.write(p, p.relative_to(root))
    return b.getvalue()

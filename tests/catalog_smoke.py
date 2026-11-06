#!/usr/bin/env python3
"""Each downloaded cartridge gets its own process, so bad content is isolated."""
import concurrent.futures
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
LIBRARY=Path(os.environ.get('GAMEBENCH_LIBRARY_DIR',ROOT/'Resources'/'Games'))
os.chdir(ROOT)
os.environ['GAMEBENCH_NO_AUDIO']='1'

def single(game):
    c=ctypes.CDLL(str(ROOT/'build/libGameBenchTest.dylib'))
    c.gb_load.argtypes=[ctypes.c_char_p]*5; c.gb_load.restype=ctypes.c_bool
    c.gb_error.restype=ctypes.c_char_p
    c.gb_frame.argtypes=[ctypes.POINTER(ctypes.c_uint),ctypes.POINTER(ctypes.c_uint)]
    c.gb_frame.restype=ctypes.POINTER(ctypes.c_uint32)
    c.gb_set_input.argtypes=[ctypes.c_uint,ctypes.c_uint16]
    core={'nes':'fceumm','gameboy':'gambatte'}[game['system']]
    saves=ROOT/'build/CatalogTestSaves'; saves.mkdir(exist_ok=True)
    args=[ROOT/f'.cache/cores/{core}_libretro.dylib',LIBRARY/game['filename'],saves,saves,game['id']]
    if not c.gb_load(*[str(a).encode() for a in args]):
        print(c.gb_error().decode()); return 1
    for _ in range(180): c.gb_run()
    w=ctypes.c_uint(); h=ctypes.c_uint()
    p=c.gb_frame(ctypes.byref(w),ctypes.byref(h))
    if not p or not w.value or not h.value: return 2
    colors={p[i] for i in range(w.value*h.value)}
    if len(colors)<2:
        # Some cartridges fade in only after several seconds of boot animation.
        for _ in range(420): c.gb_run()
        p=c.gb_frame(ctypes.byref(w),ctypes.byref(h))
        colors={p[i] for i in range(w.value*h.value)}
    if len(colors)<2:
        # A handful of multicarts/translations wait on a blank boot screen until
        # Start/A is pressed. Exercise that path before declaring video failure.
        for block in range(20):
            c.gb_set_input(0,(1<<3)|(1<<8) if block%2==0 else 0)
            for _ in range(60): c.gb_run()
            p=c.gb_frame(ctypes.byref(w),ctypes.byref(h))
            colors={p[i] for i in range(w.value*h.value)}
            if len(colors)>=2: break
        c.gb_set_input(0,0)
    if len(colors)<2: return 3
    c.gb_unload()
    return 0

def test(game):
    try:
        r=subprocess.run([sys.executable,__file__,'--one',json.dumps(game)],capture_output=True,text=True,timeout=12)
        return dict(title=game['title'],id=game['id'],passed=r.returncode==0,code=r.returncode,details=r.stdout[-1500:]+r.stderr[-1500:])
    except subprocess.TimeoutExpired: return dict(title=game['title'],id=game['id'],passed=False,code='timeout')

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--one': sys.exit(single(json.loads(sys.argv[2])))
    games=json.loads((LIBRARY/'catalog.json').read_text())
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: result=list(pool.map(test,games))
    (ROOT/'build/catalog-validation.json').write_text(json.dumps(result,indent=2))
    passed=sum(r['passed'] for r in result)
    print(f'Catalog smoke test: {passed}/{len(games)} loaded and produced video within 600 frames')
    for r in result:
        if not r['passed']: print('FAILED:',r['title'],r['code'],r.get('details',''))
    sys.exit(0 if passed==len(games) else 1)

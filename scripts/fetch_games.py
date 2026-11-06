#!/usr/bin/env python3
"""Install a private, local starter library from published community collections.

Retrobrews permits downloads from its project but not public redistribution of its
collection. Keep these artifacts local. Explicitly licensed GB titles retain their
metadata/source URLs. Games are never represented as Nintendo/Konami originals.
"""
import concurrent.futures
import hashlib
import json
import time
from pathlib import Path
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'Resources'/'Games'
CACHE=ROOT/'.cache'

def download(url, target=None):
    if target and target.exists(): return target.read_bytes()
    error=None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.parse.quote(url,safe=':/%'),timeout=25) as r: data=r.read()
            if target:
                target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
            return data
        except Exception as e: error=e
    raise error

def main():
    DEST.mkdir(parents=True,exist_ok=True)
    tree_path=CACHE/'nes-games-tree.json'
    tree=json.loads(download('https://api.github.com/repos/retrobrews/nes-games/git/trees/master?recursive=1',tree_path))
    commit=tree['sha']
    base='https://raw.githubusercontent.com/retrobrews/nes-games/'+commit+'/'
    xml=ET.fromstring(download(base+'gamelist.xml',CACHE/'nes-gamelist.xml'))
    descriptions={Path(g.findtext('path','')).name:g for g in xml.findall('game')}
    names={x['path'] for x in tree['tree']}
    roms=[x['path'] for x in tree['tree'] if x['path'].endswith('.nes')]
    approved=download(base+'README.md',DEST/'RETROBREWS-README.md')
    assert b'approved for free distribution on this site/project only' in approved
    def nes(path):
        leaf=Path(path); stem=leaf.stem
        target=DEST/'nes'/leaf.name
        data=download(base+path,target)
        if data[:4]!=b'NES\x1a': raise ValueError('Invalid ROM '+path)
        source=descriptions.get(leaf.name)
        title=source.findtext('name',stem) if source is not None else stem
        if title=='Simone Says':
            # This upstream build stays blank with the bundled FCEUmm core.
            return None
        author=source.findtext('developer','') if source is not None else ''
        cover=None
        if stem+'.png' in names:
            download(base+stem+'.png',DEST/'nes'/(stem+'.png')); cover='nes/'+stem+'.png'
        if stem+'.txt' in names: download(base+stem+'.txt',DEST/'nes'/(stem+'.txt'))
        digest=hashlib.sha256(data).hexdigest()
        return dict(id='nes-'+digest,title=title,system='nes',filename='nes/'+leaf.name,favorite=False,addedAt=0,playCount=0,isDemo=False,bundled=True,source='https://github.com/retrobrews/nes-games',author=author,cover=cover,sha256=digest,distribution='Private local download; upstream project distribution only')
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool: catalog=list(pool.map(nes,roms))
    # Remove identical ROMs rather than counting duplicate editions as games.
    catalog=list({x['id']:x for x in catalog if x}.values())
    print('NES community games:',len(catalog),flush=True)
    candidates=[]
    for path in sorted((CACHE/'metadata').glob('*.json')):
        d=json.loads(path.read_text()); license=d.get('gameLicense') or d.get('license')
        title=d.get('title','').lower()
        if d.get('typetag')=='game' and 'demo' not in title and 'character sheet' not in title and license and d.get('repository') and any(f.get('playable') and f['filename'].endswith(('.gb','.gbc')) for f in d.get('files',[])):
            candidates.append(d)
    # Prefer clear standard licenses; these are original community games.
    allowed={'MIT','CC0-1.0','GPL-2.0-only','GPL-2.0-or-later','GPL-3.0-only','GPL-3.0-or-later','GPL-3.0','Zlib','ZLib','BSD-3-Clause','Unlicense','0BSD','CC-BY-SA 4.0','MIT / CC-BY-4.0 (Assets)'}
    candidates=[d for d in candidates if (d.get('gameLicense') or d.get('license')) in allowed]
    for d in candidates:
        if len(catalog)>=100: break
        slug=d['slug']
        f=next((f for f in d['files'] if f.get('default') and f.get('playable') and f['filename'].endswith(('.gb','.gbc'))),None)
        if not f: f=next(f for f in d['files'] if f.get('playable') and f['filename'].endswith(('.gb','.gbc')))
        base='https://raw.githubusercontent.com/gbdev/database/master/entries/'+slug+'/'
        try:
            data=download(base+f['filename'],DEST/'gb'/slug/Path(f['filename']).name)
            digest=hashlib.sha256(data).hexdigest()
            expected=f.get('hash',{}).get('sha256')
            if expected and expected!=digest: raise ValueError('Checksum mismatch')
            if len(data)<0x150: raise ValueError('Truncated GB game')
            cover=None
            if d.get('screenshots'):
                screenshot=d['screenshots'][0]
                download(base+screenshot,DEST/'gb'/slug/Path(screenshot).name)
                cover='gb/'+slug+'/'+Path(screenshot).name
            (DEST/'gb'/slug/'source.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
            catalog.append(dict(id='gameboy-'+digest,title=d['title'],system='gameboy',filename='gb/'+slug+'/'+Path(f['filename']).name,favorite=False,addedAt=0,playCount=0,isDemo=False,bundled=True,source=d['repository'],author=d.get('developer',''),cover=cover,sha256=digest,license=d.get('gameLicense') or d.get('license')))
            print('Added:',d['title'],flush=True)
        except Exception as e: print('Skipped',d['title'],str(e),flush=True)
    (DEST/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    print('Installed',len(catalog),'distinct community games',flush=True)
    assert len(catalog)>=100

if __name__=='__main__': main()

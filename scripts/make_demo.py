#!/usr/bin/env python3
"""Original two-player NROM cartridge; no commercial game data is used."""
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]
code = bytearray()
labels = {}
fixups = []
def emit(*v): code.extend(v)
def label(n): labels[n] = 0x8000 + len(code)
def jump(op, n):
    emit(op,0,0); fixups.append((len(code)-2,n,False))
def branch(op,n):
    emit(op,0); fixups.append((len(code)-1,n,True))
def imm(op,v): emit(op,v)
def absolute(op,v): emit(op,v&255,v>>8)
def address(op,n): jump(op,n)
def lda(v): imm(0xa9,v)
def sta(v): absolute(0x8d,v)
def zp(op,v): emit(op,v)
def text_data(n,b): label(n); code.extend(b)

label('reset')
emit(0x78,0xd8); imm(0xa2,0xff); emit(0x9a,0xe8)
absolute(0x8e,0x2000); absolute(0x8e,0x2001); absolute(0x8e,0x4010)
lda(0x40); sta(0x4017)
label('vblank1'); absolute(0x2c,0x2002); branch(0x10,'vblank1')
lda(0); imm(0xa2,0)
label('clear'); sta(0x0000); sta(0x0100); sta(0x0200); sta(0x0300); sta(0x0400); sta(0x0500); sta(0x0600); sta(0x0700)
# The stores above need X-indexed absolute addressing.
for i in range(len(code)-24,len(code),3): code[i]=0x9d
emit(0xe8); branch(0xd0,'clear')
label('vblank2'); absolute(0x2c,0x2002); branch(0x10,'vblank2')
lda(0x3f); sta(0x2006); lda(0); sta(0x2006); imm(0xa2,0)
label('pal'); address(0xbd,'palette'); sta(0x2007); emit(0xe8); imm(0xe0,32); branch(0xd0,'pal')
lda(0x20); sta(0x2006); lda(0); sta(0x2006); imm(0xa2,0)
for i in range(4):
    label('nt'+str(i)); address(0xbd,'nametable'+str(i)); sta(0x2007); emit(0xe8); branch(0xd0,'nt'+str(i))
lda(0xfe); imm(0xa2,0)
label('hide'); absolute(0x9d,0x0200); emit(0xe8); branch(0xd0,'hide')
for addr,val in [(0,72),(1,128),(2,176),(3,128),(4,120),(5,85),(6,1),(7,0),(8,0),(9,0)]: lda(val); zp(0x85,addr)
lda(0x80); sta(0x2000); lda(0x1e); sta(0x2001)
label('forever'); jump(0x4c,'forever')

label('nmi'); emit(0x48,0x8a,0x48,0x98,0x48)
zp(0xe6,9)
lda(1); sta(0x4016); lda(0); sta(0x4016); imm(0xa2,8)
label('read'); absolute(0xad,0x4016); emit(0x4a); zp(0x26,10); absolute(0xad,0x4017); emit(0x4a); zp(0x26,11); emit(0xca); branch(0xd0,'read')
for p in range(2):
    pos=p*2; btn=10+p
    zp(0xa5,btn); imm(0x29,0x80); branch(0xf0,f'speed{p}')
    lda(3); zp(0x85,12); jump(0x4c,f'move{p}')
    label(f'speed{p}'); lda(1); zp(0x85,12)
    label(f'move{p}')
    for direction,bit,coord,positive,limit in [('up',8,pos+1,False,57),('down',4,pos+1,True,203),('left',2,pos,False,12),('right',1,pos,True,235)]:
        end=f'{direction}{p}'
        zp(0xa5,btn); imm(0x29,bit); branch(0xf0,end)
        zp(0xa5,coord); imm(0xc9,limit)
        branch(0xb0 if positive else 0x90,end)
        emit(0x18 if positive else 0x38); zp(0x65 if positive else 0xe5,12); zp(0x85,coord)
        label(end)
    # Compare each ship to the collectible star, allowing a small hit box.
    for coord,star in [(pos,4),(pos+1,5)]:
        zp(0xa5,coord); emit(0x38); zp(0xe5,star); emit(0x18); imm(0x69,8); imm(0xc9,17); branch(0xb0,f'nohit{p}')
    zp(0xe6,7+p); zp(0xa5,7+p); imm(0xc9,10); branch(0x90,f'scoreok{p}'); lda(0); zp(0x85,7+p)
    label(f'scoreok{p}')
    zp(0xa5,9); imm(0x49,0x95); imm(0x29,0xbf); emit(0x18); imm(0x69,24); zp(0x85,4)
    zp(0xa5,9); emit(0x0a); imm(0x29,0x7f); emit(0x18); imm(0x69,68); zp(0x85,5)
    # A short pulse on collecting a star.
    lda(1); sta(0x4015); lda(0x9f); sta(0x4000); lda(0x55); sta(0x4002); lda(0x08); sta(0x4003)
    label(f'nohit{p}')
for idx,px,py,tile,attr in [(0,0,1,1,0),(1,2,3,1,1),(2,4,5,2,2)]:
    base=0x200+4*idx
    zp(0xa5,py); sta(base); lda(tile); sta(base+1); lda(attr); sta(base+2); zp(0xa5,px); sta(base+3)
lda(0); sta(0x2003); lda(2); sta(0x4014)
# Write both score digits during vertical blank.
for score,lo in [(7,0x8b),(8,0x97)]:
    absolute(0x2c,0x2002); lda(0x20); sta(0x2006); lda(lo); sta(0x2006); zp(0xa5,score); emit(0x18); imm(0x69,48); sta(0x2007)
lda(0); sta(0x2005); sta(0x2005)
emit(0x68,0xa8,0x68,0xaa,0x68,0x40)
label('irq'); emit(0x40)
palette=[0x0f,0x01,0x21,0x30]*4+[0x0f,0x19,0x29,0x39]+[0x0f,0x02,0x22,0x32]+[0x0f,0x18,0x28,0x38]+[0x0f,0x06,0x16,0x26]
text_data('palette',bytes(palette))
nt=bytearray(1024)
rng=random.Random(19)
for _ in range(95):
    x,y=rng.randrange(1,31),rng.randrange(7,27)
    nt[y*32+x]=3
def line(y,x,s): nt[y*32+x:y*32+x+len(s)]=s.encode('ascii')
line(2,9,'S T A R  P I L O T')
line(4,5,'1P    0     2P    0')
line(27,4,'COLLECT STARS TOGETHER!')
line(28,5,'D-PAD MOVE / A BOOST')
for i in range(4): text_data('nametable'+str(i),nt[i*256:(i+1)*256])
for pos,n,relative in fixups:
    target=labels[n]
    if relative:
        delta=target-(0x8000+pos+1)
        assert -128<=delta<=127,(n,delta)
        code[pos]=delta&255
    else: code[pos:pos+2]=bytes([target&255,target>>8])
assert len(code)<0x3ffa
prg=code+bytes(0x3ffa-len(code))
for name in ['nmi','reset','irq']: prg.extend(labels[name].to_bytes(2,'little'))
chr=bytearray(8192)
def tile(index,rows):
    for y,row in enumerate(rows):
        for x,c in enumerate(row):
            value=int(c)
            chr[index*16+y] |= (value&1)<<(7-x)
            chr[index*16+y+8] |= ((value>>1)&1)<<(7-x)
tile(1,['00033000','00333300','00322300','03322330','33322333','33033033','00033000','00300300'])
tile(2,['00030000','00030000','00333000','33333330','00333000','00030000','00030000','00000000'])
tile(3,['00000000','00000000','00010000','00121000','00010000','00000000','00000000','00000000'])
font={
'A':['01110','10001','10001','11111','10001','10001','10001'], 'B':['11110','10001','10001','11110','10001','10001','11110'],
'C':['01111','10000','10000','10000','10000','10000','01111'], 'D':['11110','10001','10001','10001','10001','10001','11110'],
'E':['11111','10000','10000','11110','10000','10000','11111'], 'G':['01111','10000','10000','10111','10001','10001','01111'],
'H':['10001','10001','10001','11111','10001','10001','10001'], 'I':['11111','00100','00100','00100','00100','00100','11111'],
'L':['10000','10000','10000','10000','10000','10000','11111'], 'M':['10001','11011','10101','10101','10001','10001','10001'],
'O':['01110','10001','10001','10001','10001','10001','01110'], 'P':['11110','10001','10001','11110','10000','10000','10000'],
'R':['11110','10001','10001','11110','10100','10010','10001'], 'S':['01111','10000','10000','01110','00001','00001','11110'],
'T':['11111','00100','00100','00100','00100','00100','00100'], 'U':['10001','10001','10001','10001','10001','10001','01110'],
'V':['10001','10001','10001','10001','10001','01010','00100'], 'Y':['10001','10001','01010','00100','00100','00100','00100'],
'0':['01110','10001','10011','10101','11001','10001','01110'], '1':['00100','01100','00100','00100','00100','00100','01110'],
'2':['01110','10001','00001','00010','00100','01000','11111'], '3':['11110','00001','00001','01110','00001','00001','11110'],
'4':['00010','00110','01010','10010','11111','00010','00010'], '5':['11111','10000','10000','11110','00001','00001','11110'],
'6':['01110','10000','10000','11110','10001','10001','01110'], '7':['11111','00001','00010','00100','01000','01000','01000'],
'8':['01110','10001','10001','01110','10001','10001','01110'], '9':['01110','10001','10001','01111','00001','00001','01110'],
'!':['00100','00100','00100','00100','00100','00000','00100'], '-':['00000','00000','00000','11111','00000','00000','00000'],
'/':['00001','00010','00010','00100','01000','01000','10000']}
for ch,rows in font.items(): tile(ord(ch),['0'+r.replace('1','3')+'00' for r in rows]+['00000000'])
target=ROOT/'Resources'/'Demo'/'StarPilot.nes'
target.parent.mkdir(parents=True,exist_ok=True)
target.write_bytes(b'NES\x1a'+bytes([1,1,0,0])+bytes(8)+prg+chr)
print('Built original 2-player Star Pilot cartridge:',target.stat().st_size,'bytes')

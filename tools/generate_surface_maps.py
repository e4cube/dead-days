"""Original, deterministic structural surface maps. No downloaded/image-generated art.

Outputs neutral modulation, tangent normal and roughness-detail maps; factors remain
in material_library_v1.json. These are surface studies, not scanned materials.
"""
from pathlib import Path
import hashlib,json
import argparse
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'godot/assets/materials_v1'
SIZE=512

def generate():
    OUT.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(421)
    y,x=np.mgrid[0:SIZE,0:SIZE]/SIZE
    records=[]
    for kind in ['wood','road','masonry','metal','fabric','ground']:
        fine=rng.random((SIZE,SIZE))-.5
        height=fine*.015
        wear=np.zeros_like(x)
        if kind=='wood':
            # Long grain bent around two knots, and board end checks.
            distance=np.sqrt(((x-.37)*2.2)**2+((y-.43)*.45)**2)
            grain=x*43+np.sin(y*6)*.5+np.exp(-distance*9)*np.sin(y*17)*1.8
            height+=np.sin(grain*np.pi*2)*.055+np.sin(grain*np.pi*7)*.012
            wear=np.maximum(0,.02-np.abs(np.sin(x*np.pi*4)))*8
        elif kind=='road':
            # Actual aggregate-shaped flecks; macro cracks belong to street geometry.
            stones=Image.new('L',(SIZE,SIZE),128);draw=ImageDraw.Draw(stones)
            for i in range(1800):
                px,py=rng.integers(0,SIZE,size=2);r=int(rng.integers(1,4))
                draw.ellipse((int(px-r),int(py-r),int(px+r),int(py+r)),fill=int(rng.integers(70,185)))
            height+=(np.asarray(stones,dtype=float)/255-.5)*.12
        elif kind=='masonry':
            height+=np.sin(x*137)*np.sin(y*89)*.012
            # Occasional vertical runoff; no baked directional lighting.
            wear=(np.maximum(0,np.cos(x*19))**20)*(.5+.5*np.cos(y*6))*.035
        elif kind=='metal':
            height+=np.sin(y*1800)*.009
            wear=np.maximum(0,np.sin(x*29+y*9)*np.cos(y*23)-.60)*.12
        elif kind=='fabric':
            height+=np.sin(x*np.pi*128)*np.sin(y*np.pi*128)*.025
        else:
            height+=np.sin(x*44+np.sin(y*23))*np.sin(y*36)*.025
        height-=wear
        color=np.clip(.94+height*.7-wear*.5,.5,1)
        base=np.repeat((color*255).astype('uint8')[:,:,None],3,axis=2)
        dy,dx=np.gradient(height)
        normal=np.stack([-dx*12,-dy*12,np.ones_like(x)],axis=2)
        normal/=np.linalg.norm(normal,axis=2)[:,:,None]
        normal=((normal*.5+.5)*255).astype('uint8')
        rough=(np.clip(.5+fine*.08+wear*.5,0,1)*255).astype('uint8')
        for suffix,pixels in [('base',base),('normal',normal),('roughness',rough)]:
            filename=f'{kind}_{suffix}.png' if suffix=='normal' else f'study_{kind}_{suffix}.png'
            path=OUT/filename
            Image.fromarray(pixels).save(path)
            records.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'family':kind,'channel':suffix})
    library=json.loads((ROOT/'godot/data/material_library_v1.json').read_text(encoding='utf-8'))
    families=library['textures']['families']
    for id,recipe in library['materials'].items():
        family=families.get(recipe['category'])
        if not family:continue
        modulation=np.asarray(Image.open(OUT/f'study_{family}_base.png'),dtype=float)/255
        rgb=np.array([int(recipe['color'][i:i+2],16) for i in (0,2,4)])
        base=np.clip(modulation*rgb,0,255).astype('uint8')
        detail=np.asarray(Image.open(OUT/f'study_{family}_roughness.png'),dtype=float)/255-.5
        rough=(np.clip(recipe['roughness']+detail,0,1)*255).astype('uint8')
        for suffix,pixels in [('base',base),('roughness',rough)]:
            path=OUT/f'{id}_{suffix}.png';Image.fromarray(pixels).save(path)
            records.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'material':id,'channel':suffix})
    (OUT/'manifest.json').write_text(json.dumps({'version':1,'seed':421,'size':SIZE,'source':'Original structural map generator tools/generate_surface_maps.py','license':'Original project artwork; project owner determines release terms; no third-party images','ao':'Not baked; no geometry AO claimed','maps':records},indent=2)+'\n',encoding='utf-8',newline='\n')
    print('SURFACE_MAPS_OK',len(records))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output-root',default='');args=parser.parse_args()
    if args.output_root:
        base=(ROOT/args.output_root).resolve()
        assert base.is_relative_to(ROOT),'Generated files must stay in repository'
        OUT=base/'godot/assets/materials_v1'
    generate()

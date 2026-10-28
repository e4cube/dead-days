"""Preserve user references and create the initial shared, original PBR recipe registry."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
IDS = ['8fd92611-b630-41e3-8d12-637930a1dfa4','2e47de85-8e15-4c38-ac3e-7223e8a9bcfa','b78cc1ea-f908-4c40-ae68-786b7c54d702','d60f17aa-062a-4c7b-8b2b-e224072ecc1f','5cf1d3dc-3485-4d6d-b0be-f78988f14042','4409b5da-afca-4bd0-8cdd-39c5b8c2885a','185bc17d-44a6-4373-b900-eaa012fa9538','72b759c3-d8bb-4252-b79e-8adfa11dca23','59dceef6-b9bc-4061-bc4d-ce0ab2d66648','81467901-4ac1-4697-b2cd-0fa3ffb7199d']

def references():
    target=ROOT/'art/references'
    target.mkdir(parents=True,exist_ok=True)
    records=[]
    for number,id in enumerate(IDS,1):
        source=Path('C:/Users/11/AppData/Local/Temp')/f'codex-clipboard-{id}.png'
        dest=target/f'user-{number:02}.png'
        if not dest.exists() and source.exists(): shutil.copyfile(source,dest)
        records.append({'id':number,'file':dest.name,'available':dest.exists(),
                        'sha256':hashlib.sha256(dest.read_bytes()).hexdigest() if dest.exists() else None,
                        'source':'User supplied social-media screenshot; third-party artwork',
                        'license':'Reference-only; no redistribution or runtime-asset license established',
                        'runtime_use':False})
    sheet=target/'user-character-sheet.png'
    if sheet.exists():
        records.append({'id':'character-sheet','file':sheet.name,'available':True,'sha256':hashlib.sha256(sheet.read_bytes()).hexdigest(),'source':'User supplied AI-generated appearance reference','license':'Reference-only; not integrated as a game asset','runtime_use':False})
    (target/'manifest.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('REFERENCE_FILES',sum(r['available'] for r in records),'of',len(records))

if __name__=='__main__': references()

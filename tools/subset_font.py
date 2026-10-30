from pathlib import Path
import re,urllib.parse,urllib.request
root=Path('godot');text=''.join(p.read_text(encoding='utf-8',errors='ignore') for folder in ['scripts','data'] for p in (root/folder).rglob('*') if p.suffix in ['.gd','.json'])
chars=''.join(sorted(set(c for c in text if ord(c)>127)|set(chr(i) for i in range(32,127))))
url='https://fonts.googleapis.com/css2?'+urllib.parse.urlencode({'family':'Noto Sans SC:wght@400','text':chars})
print('CHARS',len(chars),flush=True)
css=urllib.request.urlopen(url,timeout=40).read().decode()
print(css[:500],flush=True)
fonturl=re.search(r'url\(([^)]+)\)',css).group(1)
data=urllib.request.urlopen(fonturl,timeout=90).read()
out=root/'fonts';out.mkdir(exist_ok=True)
(out/'NotoSansSC-subset.ttf').write_bytes(data)
print('FONT_BYTES',len(data),data[:4],flush=True)
p=root/'project.godot';s=p.read_text();
if '[gui]' not in s:s+='\n[gui]\ntheme/custom_font="res://fonts/NotoSansSC-subset.ttf"\n'
p.write_text(s)

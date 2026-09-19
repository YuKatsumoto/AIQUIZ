"""Apply builder's buffer packing to an already-exported asset, no geometry rebuild."""
import ast
from pathlib import Path
source=Path(__file__).resolve().parent
tree=ast.parse((source/'build_santorini_town.py').read_text(encoding='utf-8'))
fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='pack_color_buffers')
module=ast.Module(body=[fn],type_ignores=[])
import struct,json,numpy as np
exec(compile(module,'pack_color_buffers','exec'))
pack_color_buffers(source.parent/'aiquiz_santorini_town.glb')
print('PACKED_GLB_BYTES', (source.parent/'aiquiz_santorini_town.glb').stat().st_size)

#!/usr/bin/env python3
"""Optional offline differential check against a separately obtained, pinned tool.
Never downloads, installs, plays audio, opens a serial port or touches GPIO.
The reference source is NOT vendored; its licensing must be reviewed separately.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

COMMIT="d14199c538c61bf09c366184c8af91a8aec9f39e"
parser=argparse.ArgumentParser()
parser.add_argument("--source-dir",type=Path,required=True)
parser.add_argument("--zig",default="zig")
parser.add_argument("--artifacts",type=Path,default=Path("zig-out/pc8001/loader"))
parser.add_argument("--report",type=Path,default=Path(".zig-cache/pc8001/bootstrap-reference.json"))
args=parser.parse_args()
source=args.source_dir.resolve()
sha=subprocess.check_output(["git","-C",str(source),"rev-parse","HEAD"],text=True).strip()
if sha!=COMMIT or subprocess.check_output(["git","-C",str(source),"status","--porcelain"],text=True).strip():
    raise SystemExit("Reference must be a clean checkout of "+COMMIT)
report={"reference":"yamori813/ihex2monl","commit":sha,"scope":"CMT bytes only; no hardware playback","images":{}}
with tempfile.TemporaryDirectory(prefix="zig80-reference-") as work:
    tool=Path(work)/"ihex2monl"
    subprocess.run([args.zig,"cc","-std=c99","-O2",*[str(source/name) for name in ("main.c","readihex.c","intel_hex.c")],"-lm","-o",str(tool)],check=True)
    for prefix in ("mini-stage0","relay-stage1"):
        cmt=Path(work)/(prefix+".cmt")
        subprocess.run([str(tool),"-i","-C","-f","bin",str((args.artifacts/(prefix+".hex")).resolve()),str(cmt)],check=True)
        expected=cmt.read_bytes()
        actual=(args.artifacts/(prefix+".cmt")).read_bytes()
        if actual!=expected:
            raise SystemExit(prefix+": CMT differs from pinned reference")
        report["images"][prefix]={"bytes":len(actual),"sha256":hashlib.sha256(actual).hexdigest(),"exact_match":True}
        print(prefix+": reference CMT bytes match ("+str(len(actual))+" bytes)")
args.report.parent.mkdir(parents=True,exist_ok=True)
args.report.write_text(json.dumps(report,indent=2)+"\n")

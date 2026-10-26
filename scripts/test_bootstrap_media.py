#!/usr/bin/env python3
"""Independent CMT record / PCM-frequency decoder and exact input-count checks.
No audio playback, ROM, physical port, numpy or other third-party dependency.
"""
import array
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import unittest
import wave

BINARY = str(Path(sys.argv.pop(1) if len(sys.argv)>1 else "zig-out/bin/zig80").resolve())
OUT = Path(".zig-cache/pc8001/bootstrap-media").resolve()


def decode_cmt(blob):
    if len(blob)<7 or blob[0]!=0x3a or sum(blob[1:4])%256:
        raise ValueError("address header")
    address=int.from_bytes(blob[1:3],"big")
    offset=4
    data=bytearray()
    while True:
        if offset+3>len(blob) or blob[offset]!=0x3a:
            raise ValueError("block marker")
        count=blob[offset+1]
        if offset+3+count>len(blob) or sum(blob[offset+1:offset+3+count])%256:
            raise ValueError("block checksum")
        if count==0:
            if offset+3!=len(blob):
                raise ValueError("unexpected trailer / autostart")
            return address,bytes(data)
        data.extend(blob[offset+2:offset+2+count])
        offset+=3+count


def decode_wav(path,count):
    with wave.open(str(path),"rb") as file:
        assert (file.getnchannels(),file.getsampwidth(),file.getframerate())==(1,2,48000)
        raw=file.readframes(file.getnframes())
    samples=array.array("h",raw)
    if sys.byteorder!="little":
        samples.byteswap()
    assert len(samples)==295200+count*12*80
    assert all(x==0 for x in samples[:96000])
    assert all(x==0 for x in samples[-28800:])
    assert max(abs(x) for x in samples)<=8192
    # Correlate each 80-sample cell independently against 1200/2400 Hz.
    # Unlike the encoder's sine lookup, this classifies frequency and decodes
    # framing, so wrong carrier, polarity-independent phase and bit order fail.
    tables=[]
    for frequency in (1200,2400):
        tables.append([(math.cos(2*math.pi*frequency*i/48000),math.sin(2*math.pi*frequency*i/48000)) for i in range(80)])
    def bit(offset):
        cell=samples[offset:offset+80]
        powers=[]
        for table in tables:
            real=sum(x*c for x,(c,_) in zip(cell,table))
            imag=sum(x*s for x,(_,s) in zip(cell,table))
            powers.append(real*real+imag*imag)
        return int(powers[1]>powers[0])
    assert bit(96000)==1
    cursor=264000 # 2 s silence + 3.5 s mark leader
    output=bytearray()
    for _ in range(count):
        bits=[bit(cursor+80*j) for j in range(12)]
        assert bits[0]==0 and bits[9:]==[1,1,1],bits
        output.append(sum(bits[1+i]<<i for i in range(8)))
        cursor+=12*80
    return bytes(output)


class MediaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True,exist_ok=True)
        result=subprocess.run([BINARY,"deploy","bootstrap","--target","pc8001","--format","monitor","--out-dir",str(OUT)],capture_output=True,timeout=15)
        assert result.returncode==0,result.stderr
        assert b"SE300<RETURN>" in result.stdout

    def test_cmt_checksums_blocks_address_and_no_autostart(self):
        for prefix,address in (("mini-stage0",0xe300),("relay-stage1",0xe400)):
            cmt=(OUT/f"{prefix}.cmt").read_bytes()
            self.assertEqual(decode_cmt(cmt),(address,(OUT/f"{prefix}.bin").read_bytes()))
            for index in (3,7,len(cmt)-1):
                broken=bytearray(cmt)
                broken[index]^=1
                with self.assertRaises(ValueError):
                    decode_cmt(broken)
        self.assertEqual(hashlib.sha256((OUT/"relay-stage1.bin").read_bytes()).hexdigest(),"914b95198822e10778dbc96a3af25ee9dd5f3c606140f58da79c7db071285258")

    def test_wave_fsk_decodes_to_exact_cmt_and_machine_bytes(self):
        for prefix in ("mini-stage0","relay-stage1"):
            cmt=(OUT/f"{prefix}.cmt").read_bytes()
            decoded=decode_wav(OUT/f"{prefix}.wav",len(cmt))
            self.assertEqual(decoded,cmt)
            self.assertEqual(decode_cmt(decoded)[1],(OUT/f"{prefix}.bin").read_bytes())

    def test_basic_monitor_and_total_input_counts_are_measured(self):
        metrics=json.loads((OUT/"input-counts.json").read_text())
        for key,prefix,address in (("mini","mini-stage0",0xe300),("relay","relay-stage1",0xe400)):
            image=(OUT/f"{prefix}.bin").read_bytes()
            basic=(OUT/f"{prefix}.bas").read_bytes()
            lines=basic.decode().splitlines()
            data=[x.split(" DATA ")[1].strip('"') for x in lines if " DATA " in x]
            self.assertEqual(bytes.fromhex("".join(data)),image)
            self.assertEqual(metrics[key]["basic_total"],len(basic)-basic.count(b"\r\n")+len(b"NEW\rRUN\rR=USR0(0)\r"))
            monitor=(OUT/f"{prefix}-monitor.txt").read_text()
            groups=re.findall(r"S([0-9A-F]{4})<RETURN>\n([0-9A-F]+)<RETURN>",monitor)
            self.assertEqual(bytes.fromhex("".join(code for _,code in groups)),image)
            prelude="CLEAR 300,&HCFFF\rWIDTH 80,25\rMON\r"
            tail=f"D{address:04X},{address+len(image)-1:04X}\r\x02DEFUSR0=&H{address:04X}\rR=USR0(0)\r"
            keys=prelude+"".join(f"S{addr}\r{data}\r" for addr,data in groups)+tail
            self.assertEqual(metrics[key]["monitor_total"],len(keys))
            self.assertEqual(metrics[key]["cassette_total"],len(prelude+"L\r"+tail))
        self.assertEqual(metrics["mini"]["machine_bytes"],100)
        self.assertEqual(metrics["mini"]["data_lines"],7)
        self.assertLess(metrics["mini"]["monitor_total"],metrics["relay"]["basic_total"])


if __name__=="__main__":
    unittest.main()

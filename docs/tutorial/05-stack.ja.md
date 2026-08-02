# 05 SubroutineとStack: 戻る場所を保存する

[← 前: 分岐](04-branch.ja.md) | [目次](README.ja.md) | [English](05-stack.md) | [次: Display →](06-display.ja.md)

## この章で見る画面

- **Source**: `CALL`、`RET`、`PUSH`、`POP`
- **CPU**: PCとSP
- **Memory**: SP付近に保存される戻りAddress
- **Bus**: StackへのMemory Write/Read

## この章のゴール

- CALLでPCとSPが同時に変わる理由を説明する
- StackがLIFOで低Address方向へ伸びることを確認する
- Register Pairを安全に一時保存する

## SubroutineをStepする

```asm
org 0x0000
start:
    ld sp,0xBFFF
    ld a,1
    call twice
    halt

twice:
    add a,a
    ret
```

### Stepの流れ

```text
LD SP,BFFF
  CPU       SP FFFF → BFFF

LD A,1
  CPU       A 00 → 01

CALL twice
  PC        call先Addressへ
  SP        BFFF → BFFD
  Bus       return AddressをStackへ2 byte Write
  Memory    BFFD/BFFEにLittle Endianで保存

ADD A,A
  A         01 → 02

RET
  Bus       Stackから2 byte Read
  SP        BFFD → BFFF
  PC        HALTのAddressへ復帰
```

CALLは「Jumpして後で戻る」ために、次の命令AddressをStackへPushします。RETはそれをPCへPopします。

## SPを初期化する

Z80 Stackは低いAddress方向へ伸びます。Reset直後のSPは`FFFF`ですが、Zig_80では`C404-FFFF`がReserved領域です。Subroutineを使うProgramはGeneral RAM末尾の`BFFF`へ明示的に設定すると、Device領域との衝突を避けやすくなります。

```asm
ld sp,0xBFFF
```

## PUSHとPOP

```asm
push af
push hl
; AFとHLを自由に使う
pop hl
pop af
```

StackはLast In, First Outです。後にPushしたPairから逆順にPopします。現在対応するPairはAF、BC、DE、HLです。順番や個数が崩れるとRegister値だけでなくRETの戻りAddressまで壊れる可能性があります。

## IDE Tips

- Memory Paneで`g` → `BFF0`: Stack周辺を見る。
- `Ctrl+T`: CALLとRETを必ず別々にStep。
- Bus FilterをMemory WriteにするとCALLの保存が見やすくなります。
- BreakpointをSubroutine先頭へ置くとCall前後を比較できます。
- CPU CardのSPとPCを同時に見ます。

## Challenge: Registerを保存する

`twice`内でAFを`PUSH`し、Aを別の値へ変更してから`POP AF`してください。Aが元へ戻ること、SPが一度減って元へ戻ることをStepで確認します。

[← 前](04-branch.ja.md) | [目次](README.ja.md) | [次: Display →](06-display.ja.md)


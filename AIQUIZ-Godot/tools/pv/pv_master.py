"""PV の通し（絵コンテ v1.3 の S01〜S23、11 カット・182 拍 = 128 BPM で 85.3 秒）を組んで書き出す（レーン 6）。

    python tools/pv/pv_master.py                 # 全部：plan → audio → s03 → ae → render → mux → check
    python tools/pv/pv_master.py plan            # 計画だけ（どのカットが撮影済み／仮かの表も出す）
    python tools/pv/pv_master.py audio ae        # 一部だけ（書いた順ではなく、上の順に流す）

  plan    絵コンテの SHOTS（tools/pv/storyboard_shots.mjs）と各テイクの連番・report.json・cues.json から、
          カットの並び・レイヤー・テロップ・効果音の置き場所を決めて docs/pv/previz/v6/master_plan.json に書く。
          届いていないカット（連番・report.json・cues.json がそろっていない）は絵コンテの画像で仮に置き、「仮」の札を出す。
  audio   効果音（ゲームと同じファイル・音量）と曲（手を加えずに S03 の頭から一定の音量）を足し、全体に一定の倍率だけ掛けて
          true peak を TARGET_TP にそろえる（リミッター・コンプ・ラウドネスの自動調整は使わない）→ PV_full_audio.wav
  s03     After Effects で docs/pv/previz/ae/build_s03_t_long.jsx → S03 のタイトル（12 拍）を TESTOPIA_PV_S03_long.aep に組む
  ae      After Effects で docs/pv/previz/ae/build_master.jsx（計画を読む）→ TESTOPIA_PV_master.aep。終わると AE は前の状態に戻る
  render  aerender → PV_full_video.mp4（映像だけ。5119 フレームで 10 分ほど）
  mux     音をつけて PV_full.mp4 と PV_full_720p.mp4
  check   長さ・音のピーク・黒いコマを確かめ、要所のコマの一覧 docs/pv/previz/check/pv_full_contact.jpg を作る

ほかのレーンの連番が届いたら、もう一度 `python tools/pv/pv_master.py` を流すだけでよい（届いたカットは自動で撮影に替わる）。
"""
from __future__ import annotations

import glob
import json
import math
import re
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mix_audio import FFMPEG, ROOT, SFX, cue_table  # noqa: E402

CAP = ROOT / "artifacts" / "pv_capture"
OUT = ROOT / "docs" / "pv" / "previz" / "v6"
PLAN_PATH = OUT / "master_plan.json"
AUDIO_PATH = OUT / "PV_full_audio.wav"
AUDIO_INFO = OUT / "PV_full_audio.json"
VIDEO_PATH = OUT / "PV_full_video.mp4"
FULL_PATH = OUT / "PV_full.mp4"
FULL_720 = OUT / "PV_full_720p.mp4"
CONTACT = ROOT / "docs" / "pv" / "previz" / "check" / "pv_full_contact.jpg"
AE_DIR = ROOT / "docs" / "pv" / "previz" / "ae"
AEP = AE_DIR / "TESTOPIA_PV_master.aep"
COMP = "TESTOPIA_PV_master"
AE_RUN = ROOT / "tools" / "title_logo_ae" / "ae_run.mjs"
AERENDER = Path(r"G:\adobe\Adobe After Effects 2026\Support Files\aerender.exe")
RS_TEMPLATE = "最良設定"
OM_TEMPLATE = "H.264 - レンダリング設定を一致 - 40 Mbps"
MUSIC = ROOT / "docs" / "pv" / "music" / "testopia_pv_bgm_game_show_70s.mp3"
FFPROBE = str(Path(FFMPEG).with_name("ffprobe.exe")) if Path(FFMPEG).with_name("ffprobe.exe").exists() else "ffprobe"

FPS = 60
BEAT_F = 60 / 128 * FPS          # 1 拍 = 28.125 フレーム（カットの長さの目安。曲とは合わせない）
SR = 48000
W, H = 1920, 1080

# S01〜S05 は撮影済みのコンポ（AIQUIZ_PV_S01_S07.aep の PV_S01_S07、v5）の切れ目のまま。S06 から先は 128 BPM の拍の
# いちばん近いフレーム（四捨五入）で切る。
FIXED_STARTS = {"S01": 0, "S02": 338, "S03": 956}   # S04〜S06 は S03 の長さから決める（make_plan）
# S03（タイトル）：10/20 夜に 20 拍へ伸ばし、10/21 に 16 拍、さらに 12 拍（338 フレーム）へ詰めた（v1.3：実際のプレイ画面 S09 を
# 伸ばすため、爆散のあと止めて見せる間を短く。爆散は 2.8 秒目・ロゴの完成は 3.6 秒目のまま）。背景は v3 を 1522 フレームまで撮り直した
# 連番の PV 957〜、ロゴはゲームの登場演出を S23 と同じ 1.6 倍で 562 フレーム書き出したもの（頭の frames 枚を使う。10/21 まで等速の
# logo_s03_long）。build_s03_t_long.jsx（→ build_s03_t.jsx）が計画の "s03" を読んで
# TESTOPIA_PV_S03_long.aep に組む。S04 は S03 の頭 + frames から（テイク s04_s05 の S04 225 フレーム・S05 S05_FRAMES フレーム）。
S03_LONG = {"frames": 338, "logo_dir": "artifacts/pv_capture/logo_s03_x16/", "bg_first": "artifacts/pv_capture/v3_frames/pv_0001.jpg",
            "bg_start_frame": 957, "bg_min_frames": 1518, "aep": "docs/pv/previz/ae/TESTOPIA_PV_S03_long.aep", "comp": "PV_S03_T"}
S01_S07_AEP = "docs/pv/previz/ae/AIQUIZ_PV_S01_S07.aep"
S23_AEP = "docs/pv/previz/ae/TESTOPIA_PV_S23_S24.aep"

# 曲：手を加えずに、S03 でタイトルが出はじめるところ（PV フレーム 957 = 15.933 秒）から一定の音量で流す
MUSIC_START_FRAME = 956
MUSIC_DB = -4.0                  # 効果音（ゲームの音量のまま）に対して。S01〜S07 の試聴版（v5）と同じつり合い
TARGET_TP = -1.5                 # 全体に一定の倍率を掛けて、true peak をここにそろえる（AAC にしても −1 dBFS を超えないよう余裕）
LIMIT_TP = -1.0

HELI = SFX / "helicopter"
CROWD_FADE = 0.8
WALL_LAND_TRIM_DB = -6.0         # S06 の着地の音を一定の量下げる。10/20 19:38 の版は本物のオンライン生成の速さで、10 枚が約 1.7 秒の間に
                                 # 続けて着地して音が重なり、そのままだと全体の倍率がここで決まって全体が小さくなる（−3 dB では −18.0 LUFS）
SHUTTER_DB = -4.0                # S07 の切り替えの「カチッ」（helicopter/belt_click ＋ ui_click）
# PV だけ、いちばん大きい爆発の音を一定の量だけ下げる（S02 の P2 の爆散は body_burst と barrier_explosion が同時に鳴り、
# ほかの音より 3.7 dB も大きいので、そのままだと全体の倍率がこの 1 か所で決まって全体が小さくなる）。どの回も同じ量。
PV_CUE_TRIM_DB = {"barrier_explosion": -4.0, "body_burst": -3.0}
# AudioManager の表に無いが、ゲームが sfx_played で知らせる音（ファイル, dB）
EXTRA_CUES = {"saw_start": (SFX / "se_lab" / "saw_start.ogg", -8.0)}   # scripts/world/saw_chase_controller.gd の起動音
# 絵コンテのテロップのうち、通しでは出さないもの（{テロップの名前: 理由}。名前は <カット>_<絵コンテの順番>）
TELOP_SKIP = {
    "S21_1": "ゲームの見出し「スコアタワー」「正解数 × (残りHP+0.5) で勝負！」が上の中央に 2 秒ほど出て重なり、下は得点のカード。"
             "見出しがテロップの代わりになる（docs/pv/takes/s21.md、レーン 3 の案。10/20 夜も出さないままと決定）",
}

# S06：v1.3 で 12 拍から 8 拍へ詰めた。テイク s06_s07 の頭の「0/10」のまま待つところ（1〜94）と、「問題ができました！」（195）の
# あと止まっているところを削り、S06_SRC_IN から使う（届き始める 95 の 0.9 秒前から、できあがりの 1.2 秒あとまで）
S06_SRC_IN = 40
# S07：左上の教科名と学年（2 拍ずつ。production_lanes.md レーン 1）。v1.3 で 10 拍に詰め、6 問目（2 回目の算数、算数 6 年）を外した。
# v1.6（10/22、ユーザーの指示）で後半（社会 6 年・英語 3 年）を切り、テロップ「小1〜小6の5教科から出題！」が出ている 3 問・6 拍にした。
# S07 は次の問題へ切り替わる前のフレームで終わる（拍の切れ目より 1 フレーム早ければ、その分 S06 を長くする）
S07_TAGS = ["算数 4年", "国語 6年", "理科 3年"]
S07_ZOOM = [100, 103]
# S01・S02 の画面の揺れ（AE で 2D に足す）。撮影にも弱い揺れは入っているが伝わらないので、出来事の音の時刻（v3 の cues.json）に
# 合わせて、乱数を使わない決まった揺れを足す（減衰する 2 つのサイン波の和。端が見えないよう、揺れの大きさに合わせて少し拡大する）。
# (キュー, 横の振れ幅 px（縦はその 0.75 倍）, 収まるまでの秒)。強さは 爆散 ＞ 着地 ＞ ゴツン
SHAKES = [("wall_land", 22.0, 0.42),      # S01 Q1 の壁が空から落ちて着地（PV 142）
          ("wall_crash", 14.0, 0.35),     # S02 P2 がゴツンで脱落（PV 626）
          ("body_burst", 30.0, 0.50)]     # S02 P2 が爆散（PV 746）
SHAKE_CUTS = ("S01", "S02")
# S04：「ゲーム開始」まで設定パネルの中心へ 1.0 → 1.12 倍に寄って止める（build_s04_s07.jsx と同じ）
S04_PANEL_CENTER = [410, 440]
S04_ZOOM = 112
S04_FRAMES = 225                 # 8 拍（テイク s04_s05 の 1〜225）
S05_FRAMES = 337                 # 12 拍（テイク s04_s05 の 226〜562。10/21 に 8 拍から伸ばした：飛び去るのを見送る間と帯のワイプ）
S05_WIPE_BEATS = 1.0             # S05 → S06 の帯が覆い始める拍（S05 の終わりから。10/21 に 1 拍から 3 拍へゆっくりにしたが、10/28 に
                                 # S03 → S04 と同じ速さにそろえて 1 拍に戻した。S05 の長さ（12 拍）はそのまま）

# S09（72 拍）は 10 問の通しから切り出す。10/20 夜（案 A）から S16（チップソー）と S17（サメの逆襲）を別のカットにせず、
# 2 人版の 1 本の通し（テイク s09）に混ぜた：落ちてサメに噛まれた P2 は幽霊のサメになり、照準 → チャージ → PERFECT → P1 に体当たりする。
# 噛みつきは右下の小窓に出る。手順と出来事のフレームは docs/pv/takes/s09.md。人数のちがうテイクは混ぜない。
# v1.5（10/22、ユーザーの指示）：カットを挟みすぎず、2 本の通し（S09 の中のカットは 1 回）で見せる。テイクも v5 に撮り直した
# （ジャンプを減らし、プレイヤー同士の押し合いを多く。体当たりはボス壁の直前の 9 問目なので、そのままボス壁まで続けて撮れる）。
# (名前, 拍, 探すテイク（順に）, 手がかり) 手がかり = 上から順に探す (種類, キー, その出来事を部分の頭から何拍目に置くか)。
#   event: report.json の events[キー]（テイクのフレーム）  cue_first / cue_last: cues.json のそのキューの最初／最後
#   continue: 前の部分の続きのフレームから切らずにつなぐ（同じテイクのとき）。キーの出来事がこの部分に入るかだけ確かめる
# 絵コンテの S09 のテロップの区間は、この拍の割り振りに合わせてある。変えるときは両方を直す。
# v1.9（10/22 夜、ユーザーの指示）：S09 は、2 人で遊んだ試合（テイク s09_play。遊んだキー入力を記録して、本番の画質で流し直したもの。
# docs/pv/takes/s09_play.md）から 4 本に切り出す。幽霊のサメのきっかけは海への落下ではなく、ハートがなくなって脱落すること。
#   カウントダウンから1問目まで（0〜22 拍）：カウントダウンの「3」から（テイク 606。2 人が踊っている）、爆発（786）を 6.4 拍目。
#     1 問目に P2 が不正解の赤いドアにゴツン（1121、ハート 3 → 2）、P1 が正解を突き破る（1163）
#   ハートが0で脱落（22〜30 拍）：5 問目に P2 が赤いドアへ走って最後のゴツン（2578、ハート 1 → 0）を 4.7 拍目。甲板の上で脱落し、
#     右下の小窓で魂が抜ける（2612〜）。魂が飛び始めたところ（2663）で切る
#   ビームから体当たりまで（30〜56 拍）：幽霊が乗ったサメがビームを出す（`ghost_mount_beam` 2885）→ 6 問目の壁の上に柱 → サメが海から
#     上がって全身が見え（3050〜、P1 は 6 問目にゴツン）、右上へ滑る → 照準（3237）→ PERFECT（3424）で体当たりが命中（3466、20.7 拍目）
#     → 弾かれて遅れた P1 の後ろにチップソー（3500〜）
#   ボス壁（56〜76 拍）：9 問目の頭から（P1 は 1 回跳ぶ、幽霊が狙う）→ 9 問目の突破（4575）→ 4 択のボス壁（幽霊の 3 回目の突進は外れる）
#     → 突破（`boss_break` 4872）を 18 拍目、そのあと「GOAL へ走れ！」を 2 拍
# 前の版（v1.8）は台本の撮影 s09（自動の動き。P2 が 3 問目に海へ落ちる）から 3 本（40・9・27 拍）だった。
S09_PIECES = [
    ("カウントダウンから1問目まで", 22, ["s09_play"], [("event", "countdown_burst", 6.4), ("cue_first", "barrier_explosion", 6.4)]),
    ("ハートが0で脱落", 8, ["s09_play"], [("event", "ghost_phase_death_hold", 4.7)]),
    ("ビームから体当たりまで", 26, ["s09_play"], [("cue_first", "ghost_mount_beam", 0.0)]),
    ("ボス壁", 20, ["s09_play"], [("event", "boss_break", 18), ("cue_last", "door_correct", 18)]),
]
# 撮影で傷のあるコマを、隣のコマに差し替える（テイク → {傷のあるコマ: 代わりのコマ}）。
# s09・s09_fall の 640（カウントダウンの壁の爆発）は、PLAYING に入った最初のフレームで選手が一瞬 T ポーズになって半透明に重なる（ゲーム本体の見た目の不具合）
BAD_FRAMES = {"s09": {640: 641}, "s09_fall": {640: 641}}
# ゲームの HUD とぶつかる左下・右下のテロップを持ち上げる（{カット: 下からの割合}）。2 人版の S09 は左下に P1 の対戦カード
# （x 24〜305・y 906〜1026）、P2 が脱落したあとは右下に GHOST RIDER の案内（x 1418〜1894・y 848〜）が出るので、
# テロップの下端を y 853 にする（長い「遅れると、チップソーに巻き込まれる！」の右の端が案内の左上の角にかからない高さ）。
TELOP_BOTTOM_2P = {"S09": 0.21}
# 2 人版の噛みつきは右下の小窓（x 1392〜1884・y 588〜960）に出るので、小窓へ寄せる（AE で拡大）。v5 では右の端の押し落としも
# 同じ寄りの中に入る（端の 2 人は画面の x 1550〜1700・y 650〜780 ほど）ので、P1 が P2 に触れる 0.5 秒前（edge_contact − 30）から寄せ、
# 押し落とし → 落下 → 小窓のサメ → P1 が戻って突き破るまでを 1 回の寄りで見せる。部分の終わりまで保つ。
# 拡大の中心（anchor）は、小窓が画面の右半分に収まり、端が見えない点（拡大の中心が画面の中にあれば端は出ない）。
# 幽霊のサメの体当たりは本画面のまま（寄せると、弾かれた P1 の後ろに映るチップソーが画面の外に出る）
# "piece" を書いたものは、その部分の頭から決まった倍率で寄せたまま（v1.7 の「ビームを出して上昇」は小窓へ 2.5 倍に寄せていた。
# v1.8 で小窓をやめ、本画面のまま見せるので外した）
S09_ZOOMS = [{"event": "edge_contact", "lead": 30, "ease": 20, "scale": 180, "anchor": [1884, 880], "players": 2},
             {"event": "shark_bite", "lead": 24, "ease": 15, "scale": 180, "anchor": [1884, 880], "players": 2}]
# 1:1 で置くテイク（テイクのフレーム cut_in_frame（report.json、既定 1）からカットの長さだけ）
# 1:1 で置くテイク。S16・S17 は 10/20 夜に S09 へ統合したので、絵コンテに無ければ飛ばす
# S21 は v1.9（10/22 夜）から、S09 で 2 人が遊んだ試合の本当の結果発表（s21_play）。前の撮影（8 正解・HP 2 と 9 正解・HP 1）は --take=S21:s21
SIMPLE_TAKES = {"S16": "s16", "S17": "s17", "S21": "s21_play"}
# 画面を左右に分けるカット（v1.4、10/21 夜）：S20 は左に帽子（カスタマイズのスキンのタブ、6 拍の通し）、右にエモート（同じ画面の
# エモートのタブ、2 拍ずつ 3 本。帽子と同じ 0・2・4 拍目に替わる）。どちらもキャラのまわりだけを切り出す
# （crop：テイクの画素 [x0, y0, x1, y1]、dest：画面の [x0, y0, x1, y1]。縦横の比をそろえる。右のエモートの一覧のパネルは映らない）。
# 各半分の左上に札（S07 の教科名と同じ形）、境目に帯と同じ黄色の線。pieces = [(テイク, 拍, 名前)]（テイクはどれも 1 から）
SPLIT_SCREEN = {"S20": {
    "sides": [
        {"label": "スキン", "crop": [0, 0, 960, 1080], "dest": [0, 0, 960, 1080], "pieces": [("s20", 6.0, "帽子")]},
        {"label": "エモート", "crop": [40, 40, 900, 1007], "dest": [960, 0, 1920, 1080],
         "pieces": [("s20_emote", 2.0, "ヒップホップ"), ("s20_emote_b", 2.0, "ハウスダンス"), ("s20_emote_c", 2.0, "ヘッドスピン")]},
    ],
    "divider": {"x": 960, "w": 10},
}}
RACE_BED_CUTS = {"S16", "S17"}   # 走っている間の観客の声援を敷くカット（S09 はカウントダウンの爆発から）
S18_GLOB = "docs/pv/media/s18_*.mp4"
S18_SIDECAR = "docs/pv/media/s18_cuts.json"   # {"pieces": [{"in": 秒, "beats": 3}, ...], "audio_db": null|数}


def rel(p: Path | str) -> str:
    return Path(p).resolve().relative_to(ROOT).as_posix()


def rhu(x: float) -> int:
    """四捨五入（.5 は上へ）"""
    return int(math.floor(x + 0.5))


def log(*a) -> None:
    print(*a, flush=True)


# ------------------------------------------------------------------------------------------------ takes


class Take:
    """artifacts/pv_capture/<name>_frames の連番と report.json・cues.json"""

    def __init__(self, name: str, min_frames: int):
        self.name = name
        self.dir = CAP / f"{name}_frames"
        self.ready = False
        self.reason = ""
        self.report: dict = {}
        self.cues: list = []
        self.frames = 0
        self.warnings: list[str] = []
        rp, cp = self.dir / "report.json", self.dir / "cues.json"
        if not self.dir.is_dir():
            self.reason = "連番がまだ無い"
            return
        lock = CAP / "GPU_LOCK"
        if lock.exists() and re.search(rf"\b{re.escape(name)}\b", lock.read_text(encoding="utf-8", errors="replace")):
            self.reason = "撮影中（GPU_LOCK：" + lock.read_text(encoding="utf-8", errors="replace").strip() + "）"
            return
        nums = sorted(int(m.group(1)) for p in self.dir.glob("pv_*.jpg") if (m := re.fullmatch(r"pv_(\d{4,5})\.jpg", p.name)))
        if not rp.exists() or not cp.exists():
            self.reason = "report.json / cues.json がまだ無い"
            return
        if len(nums) < min_frames:
            self.reason = f"連番が {len(nums)} 枚（{min_frames} 枚より少ない：古い版か書き出し途中）"
            return
        newest = max((self.dir / f"pv_{n:04d}.jpg").stat().st_mtime for n in nums[-8:])
        if rp.stat().st_mtime + 5 < newest:
            self.reason = "report.json が連番より古い（書き出し途中？）"
            return
        self.report = json.loads(rp.read_text(encoding="utf-8"))
        self.cues = json.loads(cp.read_text(encoding="utf-8"))
        if nums[0] != 1 or nums[-1] != len(nums):
            self.warnings.append(f"連番が 1〜{len(nums)} の続きになっていない（{nums[0]}〜{nums[-1]}）")
        if self.report.get("failures"):
            self.warnings.append("report.json の failures：" + "; ".join(map(str, self.report["failures"])))
        self.frames = nums[-1]
        self.ready = True

    def first(self) -> str:
        return rel(self.dir / "pv_0001.jpg")

    def jpg(self, n: int) -> str:
        return rel(self.dir / f"pv_{n:04d}.jpg")

    def event(self, key: str):
        """出来事のフレーム。events は {名前: フレーム} か [{"name", "frame"}, ...]（s09 の書き方）。無ければ report の直下"""
        ev = self.report.get("events", {})
        if isinstance(ev, list):
            v = next((e.get("frame") for e in ev if isinstance(e, dict) and e.get("name") == key), self.report.get(key))
        else:
            v = ev.get(key, self.report.get(key)) if isinstance(ev, dict) else self.report.get(key)
        if isinstance(v, dict):
            v = v.get("frame")
        return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None

    def cue_frames(self, cue: str) -> list[int]:
        return [int(c["frame"]) for c in self.cues if c.get("cue") == cue and "frame" in c]


# ------------------------------------------------------------------------------------------------ plan


class Plan:
    def __init__(self):
        self.layers: list[dict] = []
        self.overlays: list[dict] = []
        self.audio: list[dict] = []
        self.cuts: list[dict] = []
        self.markers: list[list] = []
        self.unknown_cues: set[str] = set()
        self.table, self.beds = cue_table()
        self.table.update(EXTRA_CUES)
        self.skipped_telops: list[str] = []

    # --- video
    def seq(self, take: Take, src_in: int, start: int, frames: int, name: str, **extra) -> None:
        """テイクのフレーム src_in（1 始まり）から frames 枚を start に置く。連番が足りなければ最後のコマで止める"""
        avail = max(0, min(frames, take.frames - src_in + 1))
        place = {k: extra[k] for k in ("crop", "dest") if k in extra}      # 切り出し（S20 の左右）は差し替えの静止画にも
        bad = {f: g for f, g in BAD_FRAMES.get(take.name, {}).items() if src_in <= f < src_in + avail}
        if bad and extra.get("scale"):
            take.warnings.append(f"{name}：寄りのあるレイヤーでは傷のコマを差し替えない")
            bad = {}
        a = src_in
        for f in sorted(bad) + [src_in + avail]:
            if f > a:
                self.layers.append({"kind": "seq", "first": take.first(), "src_in": a - 1, "start": start + a - src_in,
                                    "frames": f - a, "name": name, **extra})
            if f in bad:
                self.layers.append({"kind": "still", "file": take.jpg(bad[f]), "start": start + f - src_in, "frames": 1,
                                    "name": f"{name}（{f} を {bad[f]} に差し替え）", "cover": True, **place})
            a = f + 1
        if avail < frames:
            self.layers.append({"kind": "still", "file": take.jpg(take.frames), "start": start + avail,
                                "frames": frames - avail, "name": name + "（最後のコマで止める）", "cover": True, **place})
            take.warnings.append(f"{name}：連番が {frames - avail} フレーム足りないので最後のコマで止めた")

    def still(self, file: str, start: int, frames: int, name: str, placeholder: bool = True) -> None:
        self.layers.append({"kind": "still", "file": file, "start": start, "frames": frames, "name": name,
                            "cover": True, "placeholder": placeholder})

    # --- overlays
    def telops(self, shot: dict, start: int, frames: int, skip_baked: bool, bottom: float | None = None) -> None:
        for k, t in enumerate(shot["telops"]):
            if skip_baked and t["baked"]:
                continue
            if f"{shot['id']}_{k + 1}" in TELOP_SKIP:
                self.skipped_telops.append(f"{shot['id']}_{k + 1}「{t['text']}」：{TELOP_SKIP[shot['id'] + '_' + str(k + 1)]}")
                continue
            t0, t1 = start + rhu(t["from"] * frames), start + rhu(t["to"] * frames)
            sub0 = start + rhu(t["subFrom"] * frames) if t["subFrom"] is not None else None
            self.overlays.append({"kind": "telop", "label": f"{shot['id']}_{k + 1}", "text": t["text"], "sub": t["sub"],
                                  "pos": t["pos"], "t0": t0, "t1": t1, "subFrom": sub0,
                                  **({"bottom": bottom} if bottom and t["pos"] in ("bl", "br") else {})})

    def label(self, cut: dict, text: str) -> None:
        self.overlays.append({"kind": "label", "text": text, "t0": cut["start"], "t1": cut["start"] + cut["frames"]})

    # --- audio
    def sfx(self, cue: str, at: float, trim_db: float = 0.0, why: str = "") -> None:
        if cue not in self.table:
            self.unknown_cues.add(cue)
            return
        path, db = self.table[cue]
        self.audio.append({"kind": "oneshot", "file": rel(path) if path.exists() else str(path), "at": round(at, 4),
                           "db": db + trim_db + PV_CUE_TRIM_DB.get(cue, 0.0), "why": why or cue})

    def file_sfx(self, path: Path, at: float, db: float, why: str) -> None:
        self.audio.append({"kind": "oneshot", "file": rel(path) if path.exists() else str(path), "at": round(at, 4),
                           "db": db, "why": why})

    def bed(self, path: Path, start: float, end: float, db: float, why: str, fade_in=0.0, fade_out=0.0, src_offset=0.0) -> None:
        if end <= start:
            return
        self.audio.append({"kind": "bed", "file": rel(path) if path.exists() else str(path), "start": round(start, 4),
                           "end": round(end, 4), "db": db, "fade_in": fade_in, "fade_out": fade_out, "why": why,
                           "src_offset": src_offset})

    def crowd(self, kind: str, start: float, end: float, why: str, fade_in=0.0, fade_out=0.0) -> None:
        if kind in self.beds:
            path, db = self.beds[kind]
            self.bed(path, start, end, db, why, fade_in, fade_out)

    def take_pre_audio(self, take: Take, src_in: int, start: int, why: str) -> None:
        """撮影の頭より前から鳴っている音（report.json の audio_before_take：
        [{"cue", "seconds_into_sound_at_frame_1", "cut_at_frame"}]）を、テイクのフレーム 1 の位置から途中から置き、cut_at_frame で切る"""
        for a in take.report.get("audio_before_take") or []:
            cue = a.get("cue")
            if cue not in self.table:
                self.unknown_cues.add(str(cue))
                continue
            path, db = self.table[cue]
            skip = (src_in - 1) / FPS                                   # カットがテイクの途中から始まるとき
            ss = float(a.get("seconds_into_sound_at_frame_1", 0.0)) + skip
            dur = (int(a["cut_at_frame"]) - src_in) / FPS if a.get("cut_at_frame") else None
            if dur is not None and dur <= 0:
                continue
            self.audio.append({"kind": "clip", "file": rel(path) if path.exists() else str(path), "src_in": round(ss, 4),
                               "at": round(start / FPS, 4), "dur": round(dur, 4) if dur else None, "db": db + PV_CUE_TRIM_DB.get(cue, 0.0),
                               "fade_out": 0.01, "why": f"{why} {cue}（撮影の前から）"})

    def take_cues(self, take: Take, src_in: int, start: int, frames: int, why: str, skip=(), trims=None, tail=0.0) -> None:
        """テイクのフレーム src_in から frames 枚ぶんの効果音を、master の start に合わせて置く（cues.json の t は撮影の秒）。
        tail：切れ目のすぐ後（その秒数まで）に鳴る音も入れる（切った直後の出来事の音を、つなぎ目で鳴らすとき）"""
        t0 = (src_in - 1) / FPS
        for c in take.cues:
            t = float(c.get("t", (c.get("frame", 1) - 1) / FPS))
            if c["cue"] in skip or not (t0 <= t < t0 + frames / FPS + tail):
                continue
            self.sfx(c["cue"], start / FPS + (t - t0), (trims or {}).get(c["cue"], 0.0), f"{why} {c['cue']}")


def players_of(take: "Take") -> int:
    """テイクの人数（report.json の players / start.players / final.hp の数 / 引数の players=。無ければ 1）"""
    r = take.report
    v = r.get("players") or (r.get("start") or {}).get("players")
    if not v and isinstance((r.get("final") or {}).get("hp"), list):   # s09 の 2 人版は final.hp が 2 人ぶん
        v = len(r["final"]["hp"])
    if not v:
        v = next((int(a.split("=", 1)[1]) for a in r.get("args", []) if str(a).startswith("players=")), 1)
    return int(v)


def load_take_json(folder: str) -> tuple[list, dict]:
    """撮影済みのテイク（v3・s04_s05）の cues.json と report.json"""
    d = CAP / folder
    return (json.loads((d / "cues.json").read_text(encoding="utf-8")),
            json.loads((d / "report.json").read_text(encoding="utf-8")))


def storyboard_shots() -> dict:
    out = subprocess.run(["node", str(ROOT / "tools/pv/storyboard_shots.mjs")], capture_output=True, check=True)
    return json.loads(out.stdout.decode("utf-8"))


def make_plan(force_placeholder: set[str], take_over: dict[str, str]) -> dict:
    sb = storyboard_shots()
    if abs(sb["bpm"] - 128) > 1e-6:
        raise SystemExit(f"絵コンテの BPM が 128 ではない（{sb['bpm']}）")
    shots = sb["shots"]
    beats = sum(s["beats"] for s in shots)
    total = rhu(beats * BEAT_F)
    fixed = dict(FIXED_STARTS)
    fixed["S04"] = fixed["S03"] + S03_LONG["frames"]
    fixed["S05"] = fixed["S04"] + S04_FRAMES
    fixed["S06"] = fixed["S05"] + S05_FRAMES
    starts, b = {}, 0
    for s in shots:
        starts[s["id"]] = fixed.get(s["id"], rhu(b * BEAT_F))
        b += s["beats"]
    p = Plan()
    takes: dict[str, Take] = {}
    two_player_cuts: set[str] = set()

    def take(name: str, min_frames: int) -> Take:
        if name not in takes:
            takes[name] = Take(name, min_frames)
        return takes[name]

    # S06・S07（テイク s06_s07、12 拍 + 12 拍 = 675 フレーム前後。旧版（v5、8 拍 + 8 拍 = 450）は使わない）。
    # v1.3 から S06 は S06_SRC_IN から、S07 は 5 問（6 問目へ切り替わる前で終わる）
    t67 = take("s06_s07", 600)
    use67 = t67.ready and not ({"S06", "S07"} & force_placeholder)
    # S07 の頭：report.json の cuts.S07[0]（レーン 1 の書き方）、s07_start_frame、無ければ 339 = bf(12)
    s07_cut = (t67.report.get("cuts") or {}).get("S07") if use67 else None
    s07_src = (int(s07_cut[0]) if s07_cut else (t67.event("s07_start_frame") or rhu(12 * BEAT_F) + 1)) if use67 else None
    sw = []
    if use67:
        sw = ((t67.report.get("s07") or {}).get("switch_frames") or t67.report.get("s07_switch_frames")
              or t67.report.get("switch_frames") or [f for f in t67.cue_frames("ui_click") if f >= s07_src])
        if len(sw) > len(S07_TAGS):
            s07_max = int(sw[len(S07_TAGS)]) - s07_src             # 次の問題へ切り替わる前のフレームまで
            starts["S07"] = max(starts["S07"], starts["S09"] - s07_max)
    ids = [s["id"] for s in shots]
    cuts = []
    for i, s in enumerate(shots):
        st = starts[s["id"]]
        en = starts[ids[i + 1]] if i + 1 < len(ids) else total
        cuts.append({"id": s["id"], "title": s["title"], "beats": s["beats"], "start": st, "frames": en - st,
                     "source": "", "placeholder": False})
    cut = {c["id"]: c for c in cuts}
    shot = {s["id"]: s for s in shots}

    def placeholder(cid: str, why: str, images: list[tuple[str, float, float]] | None = None, note: str = "絵コンテの画像") -> None:
        c, s = cut[cid], shot[cid]
        if images is None:
            images = [(q["img"], q["from"], q["to"]) for q in s["seq"]] or [(s["img"], 0.0, 1.0)]
        for k, (img, f0, f1) in enumerate(images):
            a, z = c["start"] + rhu(f0 * c["frames"]), c["start"] + rhu(f1 * c["frames"])
            p.still(img, a, z - a, f"{cid} 仮 {k + 1}（{Path(img).name}）")
        c["placeholder"] = True
        c["source"] = f"仮（{note}）：{why}"
        p.label(c, f"{cid} {s['title']}")

    # --- S03（タイトル、12 拍）：背景（v3 の連番 1518 枚以上）とロゴの連番（logo_s03_long）がそろっていること
    s03_bg = CAP / "v3_frames"
    s03_logo = ROOT / S03_LONG["logo_dir"]
    n_bg = len(list(s03_bg.glob("pv_*.jpg")))
    n_logo = len(list(s03_logo.glob("l_*.png"))) if s03_logo.is_dir() else 0
    lock = (CAP / "GPU_LOCK").read_text(encoding="utf-8", errors="replace") if (CAP / "GPU_LOCK").exists() else ""
    if n_bg < S03_LONG["bg_min_frames"] or n_logo < S03_LONG["frames"] or not (s03_logo / "report.json").exists() or "v3" in lock:
        raise SystemExit(f"S03 の素材がまだそろっていない：v3_frames {n_bg} 枚（{S03_LONG['bg_min_frames']} 枚以上）、"
                         f"{S03_LONG['logo_dir']} {n_logo} 枚（{S03_LONG['frames']} 枚）" + (f"、GPU_LOCK：{lock.strip()}" if lock else ""))
    c3 = cut["S03"]
    p.layers.append({"kind": "comp", "aep": S03_LONG["aep"], "comp": S03_LONG["comp"], "src_in": 0, "start": c3["start"],
                     "frames": c3["frames"], "name": f"S03 タイトル（{S03_LONG['comp']}、{c3['frames']} フレーム）"})
    c3["source"] = f"撮影（v3 の連番 PV {S03_LONG['bg_start_frame']}〜 ＋ {S03_LONG['logo_dir']}、TESTOPIA_PV_S03_long.aep）"

    # --- S01・S02（撮影済み、v5 のコンポ PV_S01_S07 の頭 956 フレーム）
    for cid in ("S01", "S02"):
        c = cut[cid]
        p.layers.append({"kind": "comp", "aep": S01_S07_AEP, "comp": "PV_S01_S07", "src_in": c["start"],
                         "start": c["start"], "frames": c["frames"], "name": f"{cid}（PV_S01_S07）",
                         **({"shake": True} if cid in SHAKE_CUTS else {})})
        c["source"] = "撮影済み（AIQUIZ_PV_S01_S07.aep の PV_S01_S07）"
    # S01〜S03 の音（mix_s01_s07.py と同じ）：v3 のキュー、スタートまでざわめき、そこから声援
    v3_cues, v3_report = load_take_json("v3_frames")
    shakes = []
    for cue, amp, dur in SHAKES:
        t = next((float(c["t"]) for c in v3_cues if c["cue"] == cue), None)
        if t is None:
            log(f"  ! 揺れ：v3 の cues.json に {cue} が無い")
            continue
        shakes.append({"t": round(t, 4), "amp": amp, "dur": dur, "why": cue, "pv_frame": int(t * FPS) + 1})
    skip_v3 = {"countdown_go", "countdown_beep", "countdown_rumble", "ui_click", "ui_start"}
    for c in v3_cues:
        if c["cue"] not in skip_v3:
            p.sfx(c["cue"], float(c["t"]), why=f"S01-S03 {c['cue']}")
    race_t = (v3_report.get("plan", {}).get("frames", {}).get("race", 507) - 1) / FPS
    v3_end = cut["S04"]["start"] / FPS
    p.crowd("murmur", 0.0, race_t + CROWD_FADE, "S01-S02 ざわめき", fade_out=CROWD_FADE)
    p.crowd("race", race_t, v3_end, "S02-S03 声援", fade_in=CROWD_FADE, fade_out=0.25)

    # --- S04・S05（テイク s04_s05 の連番から組む。2 人版は 10/20）
    c4, c5 = cut["S04"], cut["S05"]
    t45 = take("s04_s05", S04_FRAMES + S05_FRAMES)
    # S03 の黄色い帯（PV_S03_T の WIPE_TO_S04）は S04 の頭でそのまま左へ抜ける
    p.overlays.append({"kind": "wipe_out", "t": c4["start"], "name": "S04_WIPE_OUT（S03 の帯の続き）"})
    if t45.ready and not ({"S04", "S05"} & force_placeholder):
        press = int(t45.report.get("press_frame") or rhu(5.5 * BEAT_F) + 1)
        p.seq(t45, 1, c4["start"], c4["frames"], f"S04 教科と学年をえらぶ（s04_s05 1〜{c4['frames']}）",
              anchor=S04_PANEL_CENTER, scale_keys=[[c4["start"], 100, False], [c4["start"] + press - 1, S04_ZOOM, True]])
        p.seq(t45, c4["frames"] + 1, c5["start"], c5["frames"], f"S05 ヘリのお迎え（s04_s05 {c4['frames'] + 1}〜{c4['frames'] + c5['frames']}）")
        players = (t45.report.get("start") or {}).get("players", "?")
        c4["source"] = c5["source"] = f"撮影（{rel(t45.dir)}、{t45.frames} フレーム、{players} 人）"
        # 設定の矢印とゲーム開始の音（撮影で鳴ったもの）。メニューでは UI 以外の効果音が鳴らないので、ヘリの音はここで置く
        a0 = c4["start"] / FPS
        for c in t45.cues:
            if c["cue"] in ("ui_click", "ui_start"):
                p.sfx(c["cue"], a0 + float(c["t"]), why=f"S04 {c['cue']}")
        ev = t45.report.get("events") or {}
        depart = int(ev.get("departure_frame") or t45.report.get("departure_frame") or press + 33)
        launch = int(t45.report["launch_frame"])
        grabs = [g for g in (t45.event("grab_frame"), t45.event("grab2_frame")) if g]   # 2 人版は P2 の grab2_frame（events の中）
        tf = lambda f: (f - 1) / FPS  # noqa: E731
        end6 = cut["S06"]["start"] / FPS
        for h, off in enumerate([0.0, 0.37][:max(1, len(grabs))]):   # 2 機なら同じループを少しずらして重ねる（同じ音がぴったり重ならないよう）
            p.bed(HELI / "rotor_loop.ogg", a0 + tf(depart), a0 + tf(launch) + 0.25, -9.0 - 3.0 * (len(grabs) > 1),
                  f"S04-S05 ローター {h + 1}", fade_in=0.6, fade_out=0.25, src_offset=off)
            p.bed(HELI / "jet_loop.ogg", a0 + tf(launch), end6 + 0.05, -6.0 - 3.0 * (len(grabs) > 1),
                  f"S05 ジェット {h + 1}", fade_in=0.05, fade_out=0.2, src_offset=off)
        for h, g in enumerate(grabs):
            p.file_sfx(HELI / "grip.ogg", a0 + tf(g), -4.0, f"S05 つかまる {h + 1}")
        p.file_sfx(HELI / "jet_ignite.ogg", a0 + tf(launch), -2.0, "S05 ジェット点火")
    else:
        placeholder("S04", t45.reason if not t45.ready else "指定で仮")
        placeholder("S05", t45.reason if not t45.ready else "指定で仮")
    # S05 → S06：S03 → S04 と同じ黄色い斜めの帯が、S05 の最後の S05_WIPE_BEATS 拍で右から覆い、S06 の頭で左へ抜ける
    p.overlays.append({"kind": "wipe_in", "t0": c5["start"] + c5["frames"] - rhu(S05_WIPE_BEATS * BEAT_F),
                       "t1": c5["start"] + c5["frames"], "name": "S05_WIPE_IN（S03 の WIPE_TO_S04 と同じ）"})
    p.overlays.append({"kind": "wipe_out", "t": cut["S06"]["start"], "name": "S06_WIPE_OUT"})

    # --- S06・S07
    c6, c7 = cut["S06"], cut["S07"]
    if use67:
        p.seq(t67, S06_SRC_IN, c6["start"], c6["frames"], f"S06 実際の準備画面（s06_s07 {S06_SRC_IN}〜{S06_SRC_IN + c6['frames'] - 1}）")
        p.seq(t67, s07_src, c7["start"], c7["frames"], f"S07 5教科×6学年（s06_s07 {s07_src}〜{s07_src + c7['frames'] - 1}）", scale=S07_ZOOM)
        c6["source"] = c7["source"] = f"撮影（{rel(t67.dir)}、{t67.frames} フレーム）"
        p.take_cues(t67, S06_SRC_IN, c6["start"], c6["frames"], "S06", skip={"ui_click", "ui_start"},
                    trims={"wall_land": WALL_LAND_TRIM_DB})
        p.take_cues(t67, s07_src, c7["start"], c7["frames"], "S07", skip={"ui_click", "ui_start"},
                    trims={"wall_land": WALL_LAND_TRIM_DB})
        switches = [c7["start"] + int(f) - s07_src for f in sw][:len(S07_TAGS)]
        if len(switches) != len(S07_TAGS):
            t67.warnings.append(f"S07 の切り替えが {len(switches)} 回（{len(S07_TAGS)} 回のはず）。足りない分は 2 拍ごと")
    else:
        why = t67.reason if not t67.ready else "指定で仮"
        placeholder("S06", why)
        q = [f"docs/pv/previz/v6/placeholder/s07_v5_q{k}.jpg" for k in (1, 2, 3, 4, 5)]
        nq = len(S07_TAGS)
        placeholder("S07", why, [(q[k], k / nq, (k + 1) / nq) for k in range(nq)], note="旧 S07（10/19）の 5 問")
        switches = []
    grid = [c7["start"] + rhu(k * 2 * BEAT_F) for k in range(len(S07_TAGS))]
    switches = switches + grid[len(switches):]
    for k, f in enumerate(switches):
        f1 = switches[k + 1] if k + 1 < len(switches) else c7["start"] + c7["frames"]
        p.overlays.append({"kind": "tag", "text": S07_TAGS[k], "t0": f, "t1": f1})
        p.overlays.append({"kind": "flash", "t": f, "opacity": 45 if k == 0 else 70})
        p.file_sfx(HELI / "belt_click.ogg", f / FPS, SHUTTER_DB, f"S07 シャッター {k + 1}")
        p.sfx("ui_click", f / FPS + 0.045, -6.0, f"S07 シャッター {k + 1}（ui_click）")
    p.crowd("murmur", c6["start"] / FPS, (c7["start"] + c7["frames"]) / FPS, "S06-S07 ざわめき", fade_in=0.15, fade_out=0.25)

    # --- S09（通しを 72 拍に詰める）
    c9 = cut["S09"]
    t9s = {n: take(n, 600) for n in ("s09_play", "s09", "s09_fall")}   # s09_play：2 人で遊んだ試合（v1.9）
    # 人数のちがうテイクを混ぜない（s09 を 2 人で撮り直したのに s09_fall が 1 人版のまま、など）
    n9 = players_of(t9s["s09"]) if t9s["s09"].ready else None
    for tn, tk in t9s.items():
        if tk.ready and n9 is not None and players_of(tk) != n9:
            tk.ready, tk.reason = False, f"{players_of(tk)} 人版（s09 は {n9} 人版）なので使わない"
    if any(t.ready for t in t9s.values()) and "S09" not in force_placeholder:
        b0 = sum(shot[x]["beats"] for x in ids[:ids.index("S09")])
        if abs(sum(pc[1] for pc in S09_PIECES) - shot["S09"]["beats"]) > 1e-6:
            raise SystemExit(f"S09_PIECES の拍の合計（{sum(pc[1] for pc in S09_PIECES)}）が絵コンテの S09（{shot['S09']['beats']} 拍）と違う")
        acc, bounds = 0, [c9["start"]]
        for _, nb, _, _ in S09_PIECES:
            acc += nb
            bounds.append(rhu((b0 + acc) * BEAT_F) if acc < shot["S09"]["beats"] else c9["start"] + c9["frames"])
        burst_master = None
        notes = []
        prev = None                                   # (テイク, 前の部分の最後のフレーム)
        for k, (name, nb, names, hints) in enumerate(S09_PIECES):
            a, z = bounds[k], bounds[k + 1]
            anchor = None
            for tn in names:
                tk = t9s[tn]
                if not tk.ready:
                    continue
                for kind, key, at in hints:
                    if kind == "continue":
                        if prev and prev[0] is tk:
                            ev = tk.event(key) or next(iter(tk.cue_frames(key)), None)
                            if ev and not (prev[1] + 1 <= ev < prev[1] + 1 + z - a):
                                tk.warnings.append(f"S09 {name}：続きでつなぐと {key}（{ev}）が部分に入らない")
                            anchor = (tk, prev[1] + 1, 0.0, f"{tn} {prev[1] + 1}〜（続き）")
                            break
                        continue
                    if kind == "event":
                        f = tk.event(key)
                    else:
                        fs = tk.cue_frames(key)
                        f = (fs[0] if kind == "cue_first" else fs[-1]) if fs else None
                    if f:
                        anchor = (tk, f, at, f"{tn} {kind}:{key}@{f}")
                        break
                if anchor:
                    break
            if anchor is None:
                why = "、".join(f"{tn}：{t9s[tn].reason or '出来事が見つからない'}" for tn in names)
                f0 = (a - c9["start"]) / c9["frames"]
                img = next((q["img"] for q in shot["S09"]["seq"] if q["from"] <= f0 + 1e-6 < q["to"]), shot["S09"]["img"])
                p.still(img, a, z - a, f"S09 仮 {name}（{Path(img).name}）")
                p.overlays.append({"kind": "label", "text": f"S09 {name}", "t0": a, "t1": z})
                notes.append(f"{name}=仮（{why}）")
                prev = None
                continue
            tk, f, at, note = anchor
            src = max(1, min(f - rhu(at * BEAT_F), tk.frames - (z - a) + 1))
            zoom = {}
            for pz in S09_ZOOMS:               # 部分の中に出来事があれば、その少し前から寄せて部分の終わりまで保つ（1 つの部分に 1 つまで）
                if "piece" in pz:              # その部分の頭から決まった倍率で寄せたまま
                    if pz["piece"] == name and players_of(tk) == pz["players"] and not zoom:
                        zoom = {"anchor": pz["anchor"], "scale_keys": [[a, pz["scale"], False]]}
                        notes.append(f"{name} を {pz['scale']}% に寄せたまま")
                    continue
                ev = tk.event(pz["event"])
                if players_of(tk) == pz["players"] and ev and src <= ev < src + (z - a) and not zoom:
                    z0 = max(a, a + (ev - src) - pz["lead"])
                    zoom = {"anchor": pz["anchor"], "scale_keys": [[z0, 100, False], [z0 + pz["ease"], pz["scale"], True]]}
                    notes.append(f"{pz['event']} へ {pz['scale']}% に寄せる（{z0}〜）")
            p.seq(tk, src, a, z - a, f"S09 {name}（{tk.name} {src}〜{src + z - a - 1}）", **zoom)
            nxt = S09_PIECES[k + 1][3][0][0] if k + 1 < len(S09_PIECES) else None
            p.take_cues(tk, src, a, z - a, f"S09 {name}", tail=0.0 if nxt == "continue" else 1.5 / FPS)
            notes.append(f"{name}={note}")
            if k == 0:
                burst_master = a + (f - src)
            prev = (tk, src + z - a - 1)
        c9["source"] = "撮影を詰めた：" + "、".join(notes)
        if any(players_of(t) == 2 for t in t9s.values() if t.ready):
            two_player_cuts.add("S09")
        c9["placeholder"] = any("=仮" in n for n in notes)
        end9 = (c9["start"] + c9["frames"]) / FPS
        if burst_master is not None:
            p.crowd("murmur", c9["start"] / FPS, burst_master / FPS + CROWD_FADE, "S09 ざわめき", fade_in=0.15, fade_out=CROWD_FADE)
            p.crowd("race", burst_master / FPS, end9, "S09 声援", fade_in=CROWD_FADE, fade_out=0.25)
        else:
            p.crowd("race", c9["start"] / FPS, end9, "S09 声援", fade_in=0.15, fade_out=0.25)
    else:
        placeholder("S09", t9s["s09"].reason if not t9s["s09"].ready else "指定で仮")

    # --- S16・S17・S20・S21（1:1）
    for cid, name in {**SIMPLE_TAKES, **take_over}.items():
        if cid not in cut:            # 絵コンテから外したカット（10/20 夜：S16・S17 は S09 に統合）
            continue
        c = cut[cid]
        tk = take(name, int(c["frames"] * 0.9))
        if tk.ready and cid not in force_placeholder:
            src = tk.event("cut_in_frame") or 1
            p.seq(tk, src, c["start"], c["frames"], f"{cid} {shot[cid]['title']}（{name} {src}〜）")
            p.take_cues(tk, src, c["start"], c["frames"], cid)
            p.take_pre_audio(tk, src, c["start"], cid)
            if cid in RACE_BED_CUTS:
                p.crowd("race", c["start"] / FPS, (c["start"] + c["frames"]) / FPS, f"{cid} 声援", fade_in=0.15, fade_out=0.25)
            c["source"] = f"撮影（{rel(tk.dir)}、{tk.frames} フレーム、{src} から）"
        else:
            placeholder(cid, tk.reason if not tk.ready else "指定で仮")

    # --- S20（画面を左右に分ける）
    for cid, cfg in SPLIT_SCREEN.items():
        if cid not in cut or cid in take_over:
            continue
        c = cut[cid]
        b0 = sum(shot[x]["beats"] for x in ids[:ids.index(cid)])
        notes = []
        for side in cfg["sides"]:
            if abs(sum(pc[1] for pc in side["pieces"]) - shot[cid]["beats"]) > 1e-6:
                raise SystemExit(f"SPLIT_SCREEN[{cid}] の {side['label']} の拍の合計が絵コンテの {cid}（{shot[cid]['beats']} 拍）と違う")
            acc, a = 0.0, c["start"]
            for k, (name, nb, label) in enumerate(side["pieces"]):
                acc += nb
                z = rhu((b0 + acc) * BEAT_F) if k + 1 < len(side["pieces"]) else c["start"] + c["frames"]
                tk = take(name, int((z - a) * 0.9))
                place = {"crop": side["crop"], "dest": side["dest"]}
                if tk.ready and cid not in force_placeholder:
                    p.seq(tk, 1, a, z - a, f"{cid} {side['label']} {label}（{name} 1〜{z - a}）", **place)
                    p.take_cues(tk, 1, a, z - a, f"{cid} {side['label']} {label}")
                    notes.append(f"{side['label']}・{label}={name}")
                else:
                    f0 = (a - c["start"]) / c["frames"]
                    img = next((q["img"] for q in shot[cid]["seq"] if q["from"] <= f0 + 1e-6 < q["to"]), shot[cid]["img"])
                    p.layers.append({"kind": "still", "file": img, "start": a, "frames": z - a, "name": f"{cid} 仮 {side['label']} {label}",
                                     "placeholder": True, **place})
                    p.overlays.append({"kind": "label", "text": f"{cid} {side['label']} {label}", "t0": a, "t1": z})
                    notes.append(f"{side['label']}・{label}=仮（{tk.reason or '指定で仮'}）")
                    c["placeholder"] = True
                a = z
            p.overlays.append({"kind": "tag", "text": side["label"], "t0": c["start"], "t1": c["start"] + c["frames"],
                               "x": side["dest"][0] + W * 0.055})
        d = cfg.get("divider")
        if d:
            p.overlays.append({"kind": "bar", "x": d["x"], "w": d["w"], "t0": c["start"], "t1": c["start"] + c["frames"],
                               "name": f"{cid}_DIVIDER"})
        c["source"] = "撮影を左右に並べた：" + "、".join(notes)

    # --- S18（ユーザーの画面録画。10/20 夜に外した。絵コンテに戻せばまた使える）
    c18 = cut.get("S18")
    vids = sorted(glob.glob(str(ROOT / S18_GLOB)), key=lambda x: Path(x).stat().st_mtime)
    if c18 is None:
        pass
    elif vids and "S18" not in force_placeholder:
        side = ROOT / S18_SIDECAR
        cfg = json.loads(side.read_text(encoding="utf-8")) if side.exists() else {}
        pieces = cfg.get("pieces") or [{"in": 0.0, "beats": shot["S18"]["beats"]}]
        b0 = sum(shot[x]["beats"] for x in ids[:ids.index("S18")])
        acc, a = 0, c18["start"]
        for k, pc in enumerate(pieces):
            acc += pc["beats"]
            z = rhu((b0 + acc) * BEAT_F) if k + 1 < len(pieces) else c18["start"] + c18["frames"]
            p.layers.append({"kind": "video", "file": rel(vids[-1]), "src_in_sec": float(pc["in"]), "start": a,
                             "frames": z - a, "name": f"S18 {k + 1}（{Path(vids[-1]).name} {pc['in']} 秒〜）", "cover": True})
            if cfg.get("audio_db") is not None:
                p.audio.append({"kind": "clip", "file": rel(vids[-1]), "src_in": float(pc["in"]), "at": a / FPS,
                                "dur": (z - a) / FPS, "db": float(cfg["audio_db"]), "why": f"S18 録画の音 {k + 1}"})
            a = z
        c18["source"] = f"画面録画（{rel(vids[-1])}" + ("" if side.exists() else "、s18_cuts.json が無いので頭から") + "）"
    else:
        placeholder("S18", "docs/pv/media/s18_*.mp4 がまだ無い")

    # --- S23（撮影済み、TESTOPIA_PV_S23_S24.aep の最初の 5.625 秒）
    c23 = cut["S23"]
    p.layers.append({"kind": "comp", "aep": S23_AEP, "comp": "PV_S23_S24", "src_in": 0, "start": c23["start"],
                     "frames": c23["frames"], "name": "S23 ロゴ（PV_S23_S24）"})
    c23["source"] = "撮影済み（TESTOPIA_PV_S23_S24.aep の PV_S23_S24、最初の 5.625 秒）"

    # --- テロップ（絵コンテの「編集で足す文字」。撮影済みのコンポに入っているもの（baked）は足さない）
    for c in cuts:
        p.telops(shot[c["id"]], c["start"], c["frames"], skip_baked=c["id"] in ("S01", "S02", "S03", "S23") or (c["id"] in ("S04", "S05") and c["placeholder"]),
                 bottom=TELOP_BOTTOM_2P.get(c["id"]) if c["id"] in two_player_cuts else None)
        p.markers.append([c["start"], f"{c['id']} {c['title']}" + ("（仮）" if c["placeholder"] else "")])

    music_len = probe_duration(MUSIC)
    music_at = MUSIC_START_FRAME / FPS
    if music_at + music_len > total / FPS + 1e-3:
        raise SystemExit(f"曲が PV に収まらない（{music_at:.3f} + {music_len:.3f} > {total / FPS:.3f}）。曲は切らない")
    plan = {
        "fps": FPS, "width": W, "height": H, "frames": total, "seconds": round(total / FPS, 4), "beats": beats,
        "comp": COMP, "aep": rel(AEP), "audio_file": rel(AUDIO_PATH),
        "music": {"file": rel(MUSIC), "at": round(music_at, 4), "db": MUSIC_DB, "seconds": music_len},
        "cuts": cuts, "layers": p.layers, "overlays": p.overlays, "audio": p.audio, "markers": p.markers,
        "takes": {n: {"ready": t.ready, "reason": t.reason, "frames": t.frames, "warnings": t.warnings} for n, t in takes.items()},
        "s03": S03_LONG,
        "unknown_cues": sorted(p.unknown_cues), "skipped_telops": p.skipped_telops, "shakes": shakes,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    PLAN_PATH.write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"計画：{rel(PLAN_PATH)}（{total} フレーム = {total / FPS:.3f} 秒、{beats} 拍、曲 {music_at:.3f}〜{music_at + music_len:.3f} 秒）")
    for c in cuts:
        log(f"  {c['id']}  {c['start'] / FPS:6.2f}〜{(c['start'] + c['frames']) / FPS:6.2f} 秒 {c['frames']:4d} f  {c['source']}")
    for n, t in takes.items():
        for w in t.warnings:
            log(f"  ! {n}: {w}")
    if p.unknown_cues:
        log("  ! 効果音の表に無いキュー（置かなかった）：" + ", ".join(sorted(p.unknown_cues)))
    for t in p.skipped_telops:
        log("  - 出さないテロップ " + t)
    return plan


# ------------------------------------------------------------------------------------------------ audio


def probe_duration(path: Path) -> float:
    out = subprocess.run([FFPROBE, "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=duration",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


_decoded: dict[str, np.ndarray] = {}


def decode(path: Path, ss: float | None = None, dur: float | None = None) -> np.ndarray:
    key = f"{path}|{ss}|{dur}"
    if key not in _decoded:
        cmd = [FFMPEG, "-v", "error"]
        if ss is not None:
            cmd += ["-ss", f"{ss:.4f}"]
        cmd += ["-i", str(path)]
        if dur is not None:
            cmd += ["-t", f"{dur:.4f}"]
        cmd += ["-map", "0:a:0", "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"]
        raw = subprocess.run(cmd, capture_output=True, check=True).stdout
        _decoded[key] = np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)
    return _decoded[key]


def loudness(path: Path) -> dict:
    """ebur128 で測るだけ（音は変えない）"""
    out = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-i", str(path), "-map", "0:a:0", "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
    summary = out[out.rfind("Summary:"):]
    lufs = float(re.search(r"I:\s+(-?[\d.]+|-inf) LUFS", summary).group(1).replace("-inf", "-200"))
    tp = float(re.search(r"True peak:\s+Peak:\s+(-?[\d.]+|-inf) dBFS", summary, re.S).group(1).replace("-inf", "-200"))
    return {"lufs": lufs, "true_peak": tp}


def write_wav(path: Path, buf: np.ndarray, codec: str) -> None:
    subprocess.run([FFMPEG, "-y", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", codec, str(path)],
                   input=buf.astype("<f4").tobytes(), check=True)


def make_audio(plan: dict) -> dict:
    n = int(round(plan["frames"] / FPS * SR))
    buf = np.zeros((n, 2), dtype=np.float64)
    missing = []

    def add(x: np.ndarray, at: float, db: float) -> None:
        i = int(round(at * SR))
        if i < 0:
            x, i = x[-i:], 0
        m = min(len(x), n - i)
        if m > 0:
            buf[i:i + m] += x[:m] * (10 ** (db / 20))

    for ev in plan["audio"]:
        path = ROOT / ev["file"]
        if not path.exists():
            missing.append(ev["file"])
            continue
        if ev["kind"] == "oneshot":
            add(decode(path), ev["at"], ev["db"])
        elif ev["kind"] == "bed":
            src = decode(path)
            off = int(round(ev.get("src_offset", 0.0) * SR)) % len(src)
            length = int(round((ev["end"] - ev["start"]) * SR))
            x = np.tile(src, (length // len(src) + 2, 1))[off:off + length].copy()
            fi, fo = int(ev["fade_in"] * SR), int(ev["fade_out"] * SR)
            if fi > 0:
                x[:fi] *= np.linspace(0, 1, fi)[:, None]
            if fo > 0:
                x[-fo:] *= np.linspace(1, 0, fo)[:, None]
            add(x, ev["start"], ev["db"])
        elif ev["kind"] == "clip":
            x = decode(path, ev["src_in"], ev.get("dur")).copy()
            fo = int(ev.get("fade_out", 0.0) * SR)
            if 0 < fo < len(x):
                x[-fo:] *= np.linspace(1, 0, fo)[:, None]
            add(x, ev["at"], ev["db"])
    sfx_only = buf.copy()
    m = plan["music"]
    music = decode(ROOT / m["file"])
    if int(round(m["at"] * SR)) + len(music) > n:
        raise SystemExit("曲が PV に収まらない（曲は切らない）")
    add(music, m["at"], m["db"])

    raw = OUT / "PV_full_audio_raw.wav"
    write_wav(raw, buf, "pcm_f32le")
    before = loudness(raw)
    gain_db = TARGET_TP - before["true_peak"]
    buf *= 10 ** (gain_db / 20)
    write_wav(AUDIO_PATH, buf, "pcm_s24le")
    raw.unlink()
    after = loudness(AUDIO_PATH)
    sample_peak = 20 * math.log10(max(np.abs(buf).max(), 1e-12))
    sfx_peak = 20 * math.log10(max(np.abs(sfx_only).max(), 1e-12)) + gain_db
    info = {"out": rel(AUDIO_PATH), "seconds": round(n / SR, 4), "gain_db": round(gain_db, 2), "music_db": m["db"],
            "music_db_final": round(m["db"] + gain_db, 2), "sfx_db_final": round(gain_db, 2),
            "true_peak": after["true_peak"], "sample_peak": round(sample_peak, 2), "sfx_only_peak": round(sfx_peak, 2),
            "lufs": after["lufs"], "events": len(plan["audio"]), "missing": sorted(set(missing))}
    AUDIO_INFO.write_text(json.dumps(info, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"音：{rel(AUDIO_PATH)}  一定の倍率 {gain_db:+.2f} dB（曲は {m['db'] + gain_db:+.2f} dB）、true peak {after['true_peak']} dBFS、"
        f"サンプルのピーク {sample_peak:.2f} dBFS、{after['lufs']} LUFS、効果音 {len(plan['audio'])} 個")
    if missing:
        log("  ! 無いファイル（鳴らない）：" + ", ".join(sorted(set(missing))))
    if after["true_peak"] > LIMIT_TP:
        raise SystemExit(f"true peak が {LIMIT_TP} dBFS を超えた")
    return info


# ------------------------------------------------------------------------------------------------ AE / render / mux / check


def run_jsx(name: str) -> dict:
    """docs/pv/previz/ae/<name> を AE で流し、結果（result）を返す"""
    res_file = OUT / "_ae_result.json"
    res_file.unlink(missing_ok=True)
    out = subprocess.run(["node", str(AE_RUN), str(AE_DIR / name), str(res_file)], capture_output=True, timeout=900)
    text = res_file.read_text(encoding="utf-8") if res_file.exists() else ""
    res_file.unlink(missing_ok=True)
    try:
        res = json.loads(text)
    except ValueError:
        raise SystemExit(f"AE（{name}）の結果が読めない：\n" + text + out.stdout.decode("utf-8", errors="replace")
                         + out.stderr.decode("utf-8", errors="replace"))
    r = res.get("result") or {}
    if not res.get("ok") or r.get("error"):
        raise SystemExit(f"AE（{name}）で失敗：\n" + text[:4000])
    return r


def run_s03() -> None:
    r = run_jsx("build_s03_t_long.jsx")
    log(f"S03：{r.get('comp')} {r.get('frames')} フレーム、BURST {r.get('burst', 0):.2f} 秒、ワイプ {r.get('out', 0):.2f} 秒〜、"
        f"ロゴ {r.get('logoFrames')} 枚・背景 {r.get('bgFrames')} 枚 → {r.get('saved')}")


def run_ae() -> None:
    res_file = OUT / "_ae_result.json"
    res_file.unlink(missing_ok=True)
    out = subprocess.run(["node", str(AE_RUN), str(AE_DIR / "build_master.jsx"), str(res_file)], capture_output=True, timeout=900)
    text = res_file.read_text(encoding="utf-8") if res_file.exists() else ""
    res_file.unlink(missing_ok=True)
    try:
        res = json.loads(text)
    except ValueError:
        raise SystemExit("AE の結果が読めない：\n" + text + out.stdout.decode("utf-8", errors="replace")
                         + out.stderr.decode("utf-8", errors="replace"))
    r = res.get("result") or {}
    if not res.get("ok") or r.get("error"):
        raise SystemExit("AE で失敗：\n" + text[:4000])
    log("AE：" + json.dumps(r, ensure_ascii=False))


def run_render() -> None:
    if VIDEO_PATH.exists():
        VIDEO_PATH.unlink()
    logf = CAP / "aerender_master.log"
    t0 = time.time()
    with open(logf, "wb") as f:
        rc = subprocess.run([str(AERENDER), "-project", str(AEP), "-comp", COMP, "-RStemplate", RS_TEMPLATE,
                             "-OMtemplate", OM_TEMPLATE, "-output", str(VIDEO_PATH)], stdout=f, stderr=subprocess.STDOUT).returncode
    if rc != 0 or not VIDEO_PATH.exists():
        raise SystemExit(f"aerender が失敗（{rc}）。{rel(logf)} を見る")
    log(f"書き出し：{rel(VIDEO_PATH)}（{time.time() - t0:.0f} 秒）")


def run_mux() -> None:
    subprocess.run([FFMPEG, "-y", "-v", "error", "-i", str(VIDEO_PATH), "-i", str(AUDIO_PATH), "-map", "0:v", "-map", "1:a",
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", str(FULL_PATH)], check=True)
    subprocess.run([FFMPEG, "-y", "-v", "error", "-i", str(FULL_PATH), "-vf", "scale=1280:720:flags=lanczos",
                    "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(FULL_720)], check=True)
    log(f"音つき：{rel(FULL_PATH)}、{rel(FULL_720)}")


def run_check(plan: dict) -> None:
    from PIL import Image, ImageDraw, ImageFont

    pr = subprocess.run([FFPROBE, "-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries",
                         "stream=nb_read_frames,width,height,r_frame_rate", "-of", "json", str(FULL_PATH)],
                        capture_output=True, text=True, check=True)
    v = json.loads(pr.stdout)["streams"][0]
    ad = probe_duration(FULL_PATH)
    lo = loudness(FULL_PATH)
    bd = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-i", str(FULL_720), "-vf", "blackdetect=d=0.1:pix_th=0.06",
                         "-an", "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
    blacks = re.findall(r"black_start:([\d.]+) black_end:([\d.]+)", bd)
    log(f"確認：{v['width']}x{v['height']} {v['r_frame_rate']} {v['nb_read_frames']} フレーム（計画 {plan['frames']}）、"
        f"音 {ad:.3f} 秒、AAC の true peak {lo['true_peak']} dBFS、{lo['lufs']} LUFS、黒いコマ {blacks or 'なし'}")
    if int(v["nb_read_frames"]) != plan["frames"]:
        log("  ! フレーム数が計画と違う")
    if lo["true_peak"] > LIMIT_TP:
        log(f"  ! AAC の true peak が {LIMIT_TP} dBFS を超えた")

    # 要所のコマ：各カットの 30% と 75%、テロップの出ているところ
    picks = []
    for c in plan["cuts"]:
        for frac in (0.3, 0.75):
            picks.append((c["start"] + int(c["frames"] * frac), c["id"] + ("（仮）" if c["placeholder"] else "")))
    picks.sort()
    tmp = OUT / "_contact"
    tmp.mkdir(exist_ok=True)
    for f in tmp.glob("*.png"):
        f.unlink()
    sel = "+".join(f"eq(n\\,{f})" for f, _ in picks)
    subprocess.run([FFMPEG, "-y", "-v", "error", "-i", str(FULL_PATH), "-vf", f"select='{sel}',scale=480:270",
                    "-vsync", "0", str(tmp / "c_%03d.png")], check=True)
    files = sorted(tmp.glob("c_*.png"))
    cols, tw, th, lab = 7, 480, 270, 30
    rows = math.ceil(len(files) / cols)
    sheet = Image.new("RGB", (cols * tw, rows * (th + lab)), (16, 20, 32))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 20)
    except OSError:
        font = ImageFont.load_default()
    for k, fp in enumerate(files):
        x, y = (k % cols) * tw, (k // cols) * (th + lab)
        sheet.paste(Image.open(fp).convert("RGB"), (x, y + lab))
        f, cid = picks[k]
        draw.text((x + 8, y + 4), f"{cid}  {f / FPS:5.2f}s  f{f}", fill=(240, 240, 240), font=font)
        fp.unlink()
    tmp.rmdir()
    CONTACT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(CONTACT, quality=88)
    log(f"一覧：{rel(CONTACT)}")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force, take_over = set(), {}
    for a in sys.argv[1:]:
        if a.startswith("--placeholder="):
            force |= set(a.split("=", 1)[1].split(","))
        elif a.startswith("--take="):           # 例 --take=S20:s20_skin（1:1 で置くカットのテイクを替える）
            cid, name = a.split("=", 1)[1].split(":")
            if cid not in SIMPLE_TAKES:
                raise SystemExit(f"--take は {', '.join(SIMPLE_TAKES)} だけ")
            take_over[cid] = name
    steps = ["plan", "audio", "s03", "ae", "render", "mux", "check"]
    todo = [s for s in steps if not args or s in args]
    plan = make_plan(force, take_over) if "plan" in todo or not PLAN_PATH.exists() else json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    if "audio" in todo:
        make_audio(plan)
    if "s03" in todo:
        run_s03()
    if "ae" in todo:
        run_ae()
    if "render" in todo:
        run_render()
    if "mux" in todo:
        run_mux()
    if "check" in todo:
        run_check(plan)


if __name__ == "__main__":
    main()

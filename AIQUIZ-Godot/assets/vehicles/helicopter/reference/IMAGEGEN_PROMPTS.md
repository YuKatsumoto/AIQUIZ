# Reference image generation prompts

The generated PNG files in this directory are the outputs of these prompts. Generate the 3/4 anchor first, then use that image as the sole image reference for each orthographic view.

## 3/4 anchor

```text
Use case: stylized-concept
Asset type: multi-view anchor reference for a real-time game prop and Tripo Multi-View generation
Primary request: Create one original compact low-poly civilian rescue helicopter, inspired only by a simple readable civilian helicopter silhouette, designed to drop one blocky game character through a belly hatch.
Subject: rounded wedge cockpit, long thin tail boom, landing skids, large main rotor, tail rotor, and a clearly visible rectangular belly hatch or recessed cargo opening beneath the fuselage.
Style/medium: clean stylized low-poly 3D product render; faceted, friendly, readable at gameplay distance; suitable for AIQUIZ toon shading.
Materials: neutral matte white recolorable body-paint region, charcoal rotors and skids, pale-cyan windows.
Composition: exact three-quarter front-left product view; full helicopter centered; generous even margins around the entire rotor and tail; plain light-gray background; no crop.
Lighting: soft uniform studio lighting, minimal soft contact shadow, no dramatic highlights.
Consistency target: this image will be the geometry and material anchor for later exact front, back, left, and right orthographic views.
Constraints: main rotor, tail rotor, and hatch must read as separable parts; civilian design; no pilot, no visible detailed interior, no weapons, no text, no logo, no military markings, no motion blur, no scenery, no watermark.
```

## Orthographic view template

Replace `[VIEW DESCRIPTION]` with one of the four descriptions below and provide `helicopter_anchor_three_quarter.png` as the reference image.

```text
Use case: stylized-concept
Asset type: Tripo Multi-View reference
Primary request: Render the exact same helicopter from the supplied anchor image with identical geometry, proportions, part placement, faceting, materials, and colors.
Composition: exact orthographic [VIEW DESCRIPTION]; no perspective and no three-quarter angle. Full helicopter including every main-rotor tip, skids, tail boom, and tail surfaces centered with generous even margins. Match the anchor's object scale and camera height. Plain light-gray background.
Lighting: identical soft uniform studio lighting, minimal contact shadow.
Materials: unchanged neutral matte white body-paint region, charcoal rotors and skids, pale-cyan windows.
Constraints: do not redesign, add, remove, mirror, or reshape any part; keep separable main rotor, tail rotor, and belly hatch; no text, logo, markings, motion blur, scenery, pilot, interior detail, or watermark.
```

- Front: `FRONT view, looking straight at the helicopter nose`
- Back: `BACK view, looking straight at the helicopter tail from behind`
- Left: `LEFT SIDE view, showing the full left profile with the nose pointing left`
- Right: `RIGHT SIDE view, showing the full right profile with the nose pointing right`

## 日本語での使い方

1. 最初に3/4アンカーを生成します。
2. 前・後・左・右は、それぞれ別の生成処理でアンカー1枚だけを参照画像に指定します。
3. 形状が変わった面は採用せず、アンカーとローター枚数、窓、ハッチ、スキッド、尾翼が一致する画像を使います。
4. Tripo Multi-Viewには正投影4枚を投入し、3/4アンカーは生成結果の形状確認に使います。

# AIQUIZ Helicopter - Tripo production brief

Workflow reference: [Tripo Multi-View to 3D guide](https://www.tripo3d.ai/blog/multi-view-to-3d)

## Recommended inputs

Upload these four images to Tripo Multi-View in this order. The 3/4 image is the visual anchor and is useful for checking the result, but the four orthographic views are the production inputs.

1. `reference/helicopter_front.png`
2. `reference/helicopter_back.png`
3. `reference/helicopter_left.png`
4. `reference/helicopter_right.png`

Visual anchor: `reference/helicopter_anchor_three_quarter.png`

## English prompt

```text
Create one original compact low-poly civilian rescue helicopter for a real-time game. Match the supplied front, back, left, and right references as one consistent vehicle. Preserve the rounded wedge cockpit, long thin tail boom, landing skids, large main rotor, tail rotor, and rectangular belly hatch or recessed cargo opening.

Keep a clean, friendly, faceted low-poly silhouette that remains readable at gameplay distance and works with toon shading. The main body-paint region must remain neutral white and be easy to recolor at runtime. Keep the windows pale cyan and the rotors and landing skids charcoal; those parts must not share the body-paint material.

The MainRotor and TailRotor must be separable rotating parts. A separate DropHatch is preferred; if it cannot be produced cleanly, leave a readable recessed opening on the underside so the character can be dropped directly from the fuselage.

Civilian design only. No pilot, detailed interior, weapons, text, logos, military markings, motion blur, scenery, or watermark.
```

## 日本語プロンプト

```text
リアルタイムゲーム用の、オリジナルでコンパクトなローポリ民間救助ヘリコプターを1機生成してください。前・後・左・右の参照画像を同一機体として扱い、丸みのあるくさび型コックピット、細長いテールブーム、着陸スキッド、大型メインローター、テールローター、長方形の機体下面ハッチまたは凹んだ貨物開口部を維持してください。

ゲームプレイ距離でも読み取りやすく、トゥーンシェーディングに適した、親しみやすい面構成のローポリシルエットにしてください。機体の塗装領域は実行時に色変更しやすいニュートラルな白のままにします。窓は淡いシアン、ローターと着陸スキッドはチャコール色を維持し、機体塗装と同じマテリアルに統合しないでください。

MainRotor と TailRotor は回転できる分離部品にしてください。DropHatch の分離が望ましいですが、きれいに生成できない場合は、機体下面から直接キャラクターを投下できるよう、判別しやすい凹型開口部を残してください。

民間機デザインのみ。パイロット、詳細な内装、武器、文字、ロゴ、軍用マーキング、モーションブラー、背景物、透かしは不要です。
```

## Export and Blender contract

- Export format: GLB
- Unit: meters, transforms applied
- Geometry budget: no more than 25,000 triangles
- Texture budget: one 1024 px texture set
- Root origin: center of the aircraft body
- Godot forward direction: nose points toward `-Z`
- Required separated object/material names:
  - `BodyPaint` - the only runtime recolorable region
  - `MainRotor` - origin centered on the main rotor shaft
  - `TailRotor` - origin centered on the tail rotor shaft
- Optional separated object: `DropHatch`
- Windows, rotors, and landing skids must not use `BodyPaint`.
- Apply scale and rotation before GLB export. Check that both rotor origins spin without orbiting.
- Final destination in this project: `assets/vehicles/helicopter/helicopter_drop.glb`

The same GLB is shared by P1 and P2. The game duplicates only the `BodyPaint` material and replaces its albedo with the matching player theme color.

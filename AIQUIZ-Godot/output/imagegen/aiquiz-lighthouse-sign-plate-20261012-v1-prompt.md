# AIQUIZ lighthouse sign: clean background plate

Tool: built-in image_gen (one image, one generation call).

Input image / strict edit target: C:/AIQUIZ/AIQUIZ-Godot/assets/aiquiz_stadium/source/textures/lighthouse_sign.png (1500x600).

Output: assets/aiquiz_stadium/source/textures/lighthouse_sign_plate.png

Purpose: remove the old white illuminated AIQUIZ channel letters to provide a clean navy panel for a replacement logo to be composited later.

Review: inspected the generated image and the final 1500x600 plate at original resolution. No visible trace of the old AIQUIZ letters remains: no white faces, grey side returns, letter-shaped shadows, or glow. The upper area contains deep navy painted metal with subtle texture and continuous horizontal and vertical panel seams. Small seam rivets are visible in the reconstructed area. The brushed steel frame, corner screws, yellow STADIUM lettering, orange left bar, and blue right bar retain the original source pixels and exact placement.

Saved PNG: 1500x600, opaque, 5:2. The tool returned a 1983x793 PNG, which was resampled to the source canvas with high-quality bicubic interpolation. The generated upper panel was blended into the source only within x=135..1404, y=42..398, with a narrow feathered perimeter; the frame and entire lower signage area were retained from the original. Pixel comparison found zero differences in the protected area. The source image was preserved.

Only the requested plate PNG and this prompt record were written in the project; no game integration.

## Edit prompt

Use case: precise-object-edit / background plate.
Asset type: clean background plate for the AIQUIZ STADIUM sign, for a replacement logo to be composited later.
Input image: lighthouse_sign.png (1500x600) is the strict edit target. Generate exactly ONE edited image.

Remove the large white illuminated "AIQUIZ" channel letters completely, including their grey side returns, their glow and their cast shadows on the panel. Reconstruct what was behind them: the same deep navy painted metal panel with its subtle texture, the same faint horizontal and vertical panel seams continuing straight through, and the same small screws/rivets where they were. The entire upper sign area must be empty navy panel with absolutely no letter silhouettes, no white fragments, no grey side pieces, no residual halos, and no letter-shaped shadows.
Keep everything else exactly as it is and in exactly the same place: the brushed steel outer frame, the corner screws, the yellow "STADIUM" lettering, and the orange bar on the left and the blue bar on the right. Do not repaint or redesign these elements; preserve their shape, texture, color, lighting, and exact relative position.
Same lighting, same camera, same framing, same 5:2 aspect ratio, full frame edges at the same relative coordinates as the 1500x600 source. No new text, no new objects, no logo, no letters in the upper area. Opaque image; the reconstructed panel is the background, not transparency.

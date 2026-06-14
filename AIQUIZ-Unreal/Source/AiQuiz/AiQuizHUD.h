#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "AiQuizHUD.generated.h"

class AAiQuizGameModeBase;
class UFont;
class UCanvas;

/**
 * Canvas-driven HUD (Phase 7). Faithful-in-content port of scripts/ui/gameplay_hud.gd
 * (+ a compact main-menu) drawn entirely in C++ so it needs no WBP uasset:
 *  - Menu: subject / grade / difficulty selector + start prompt.
 *  - Countdown: big 3-2-1.
 *  - Playing: question, score, 10-question progress bar, correct flash + message, streak.
 *  - GameOver/Clear: result card (title, reason, explanation, stats, retry/menu prompts)
 *    with the Godot 4s death-delay fade before the panel appears.
 * Japanese UI strings live here (presentation layer), encoded UTF-8 with BOM.
 */
UCLASS()
class AIQUIZ_API AAiQuizHUD : public AHUD
{
	GENERATED_BODY()

public:
	virtual void DrawHUD() override;

protected:
	AAiQuizGameModeBase* ResolveGM();

	void DrawMenu();
	void DrawCountdown();
	void DrawPlaying();
	void DrawResult();
	void DrawFlashOverlay();

	// --- low-level Canvas helpers ---
	float ScaleForHeight(float DesiredPx) const;
	float DrawText(const FString& S, float X, float Y, float DesiredPx, const FLinearColor& Color, bool bCenterX, bool bShadow = true);
	void FillRect(float X, float Y, float W, float H, const FLinearColor& Color);

private:
	UPROPERTY(Transient) TObjectPtr<AAiQuizGameModeBase> GM = nullptr;
	UPROPERTY(Transient) TObjectPtr<UFont> Font = nullptr;
	float ScreenW = 0.f;
	float ScreenH = 0.f;
};

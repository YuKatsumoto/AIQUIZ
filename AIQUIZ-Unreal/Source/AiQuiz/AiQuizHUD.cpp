#include "AiQuizHUD.h"
#include "AiQuizGameModeBase.h"
#include "Engine/Canvas.h"
#include "Engine/Font.h"
#include "Engine/Engine.h"
#include "CanvasItem.h"
#include "Kismet/GameplayStatics.h"

// ---- Japanese UI strings live in the presentation layer (this file is UTF-8 w/ BOM). ----
namespace AiQuizUI
{
	static const TCHAR* MenuTitle      = TEXT("AIQUIZ 3D");
	static const TCHAR* MenuSubject    = TEXT("教科");
	static const TCHAR* MenuGrade      = TEXT("学年");
	static const TCHAR* MenuDifficulty = TEXT("難易度");
	static const TCHAR* MenuStart      = TEXT("Enter / Space で スタート");
	static const TCHAR* MenuControls   = TEXT("A / D : 教科     W / S : 学年     Q / E : 難易度");
	static const TCHAR* DifficultyNames[3] = { TEXT("簡単"), TEXT("普通"), TEXT("難しい") };
	static const TCHAR* Correct        = TEXT("正解！");
	static const TCHAR* TitleClear     = TEXT("CLEAR!");
	static const TCHAR* TitleGameOver  = TEXT("GAME OVER");
	static const TCHAR* ClearSub       = TEXT("10問完走！");
	static const TCHAR* ScoreSub       = TEXT("正解 / 10問");
	static const TCHAR* StatRate       = TEXT("正答率");
	static const TCHAR* StatStreak     = TEXT("連続正解");
	static const TCHAR* StatTime       = TEXT("時間");
	static const TCHAR* ResultPrompt   = TEXT("R : リトライ        Esc : メニュー");
	static const TCHAR* MagmaMsg       = TEXT("マグマに落ちてしまった！");
	static const TCHAR* Door2[2]       = { TEXT("左"), TEXT("右") };
	static const TCHAR* Door4[4]       = { TEXT("A"), TEXT("B"), TEXT("C"), TEXT("D") };

	static FString GradeLabel(int32 G) { return FString::Printf(TEXT("%d年"), G); }
	static FString ScoreLine(int32 Score, int32 Index) { return FString::Printf(TEXT("正解: %d  問題: %d/10"), Score, Index); }
	static FString StreakLine(int32 N) { return FString::Printf(TEXT("%d 連続正解！"), N); }
	static FString WrongDoorMsg(const FString& AnswerLabel) { return FString::Printf(TEXT("不正解！ 正解は %s"), *AnswerLabel); }

	// Split a (CJK) string into lines of at most MaxChars characters for the question panel.
	static TArray<FString> Wrap(const FString& S, int32 MaxChars)
	{
		TArray<FString> Lines;
		FString Cur;
		for (int32 i = 0; i < S.Len(); ++i)
		{
			const TCHAR Ch = S[i];
			if (Ch == TEXT('\n')) { Lines.Add(Cur); Cur.Reset(); continue; }
			Cur.AppendChar(Ch);
			if (Cur.Len() >= MaxChars) { Lines.Add(Cur); Cur.Reset(); }
		}
		if (Cur.Len() > 0) { Lines.Add(Cur); }
		return Lines;
	}
}

using namespace AiQuizUI;

AAiQuizGameModeBase* AAiQuizHUD::ResolveGM()
{
	if (!GM)
	{
		GM = Cast<AAiQuizGameModeBase>(UGameplayStatics::GetGameMode(this));
	}
	return GM;
}

float AAiQuizHUD::ScaleForHeight(float DesiredPx) const
{
	if (!Font || !Canvas) { return 1.0f; }
	float W = 0.f, H = 0.f;
	Canvas->TextSize(Font, TEXT("Ag8日"), W, H, 1.0f, 1.0f);
	return (H > 1.0f) ? (DesiredPx / H) : (DesiredPx / 20.0f);
}

float AAiQuizHUD::DrawText(const FString& S, float X, float Y, float DesiredPx, const FLinearColor& Color, bool bCenterX, bool bShadow)
{
	if (!Font || !Canvas || S.IsEmpty()) { return 0.0f; }
	const float Sc = ScaleForHeight(DesiredPx);
	float W = 0.f, H = 0.f;
	Canvas->TextSize(Font, S, W, H, Sc, Sc);
	const float DX = bCenterX ? (X - W * 0.5f) : X;
	FCanvasTextItem TI(FVector2D(DX, Y), FText::FromString(S), Font, Color);
	TI.Scale = FVector2D(Sc, Sc);
	if (bShadow) { TI.EnableShadow(FLinearColor(0.f, 0.f, 0.f, 0.85f)); }
	Canvas->DrawItem(TI);
	return W;
}

void AAiQuizHUD::FillRect(float X, float Y, float W, float H, const FLinearColor& Color)
{
	if (!Canvas) { return; }
	FCanvasTileItem Tile(FVector2D(X, Y), FVector2D(W, H), Color);
	Tile.BlendMode = SE_BLEND_Translucent;
	Canvas->DrawItem(Tile);
}

void AAiQuizHUD::DrawHUD()
{
	Super::DrawHUD();
	if (!Canvas) { return; }
	if (!ResolveGM()) { return; }
	if (!Font)
	{
		Font = LoadObject<UFont>(nullptr, TEXT("/Game/AiQuiz/UI/F_NotoSansJP.F_NotoSansJP"));
		if (!Font && GEngine) { Font = GEngine->GetLargeFont(); } // ASCII fallback if not imported
	}
	ScreenW = Canvas->SizeX;
	ScreenH = Canvas->SizeY;

	DrawFlashOverlay();

	switch (GM->State)
	{
	case EAiQuizState::Menu:      DrawMenu();      break;
	case EAiQuizState::Countdown: DrawCountdown(); break;
	case EAiQuizState::Playing:   DrawPlaying();   break;
	case EAiQuizState::GameOver:  DrawResult();    break;
	case EAiQuizState::Clear:     DrawResult();    break;
	default: break;
	}
}

void AAiQuizHUD::DrawFlashOverlay()
{
	if (GM->CorrectFlash > 0.0f)
	{
		FillRect(0, 0, ScreenW, ScreenH, FLinearColor(0.2f, 1.0f, 0.4f, GM->CorrectFlash * 0.4f));
	}
	else if (GM->WrongFlash > 0.0f)
	{
		FillRect(0, 0, ScreenW, ScreenH, FLinearColor(1.0f, 0.2f, 0.2f, GM->WrongFlash * 0.6f));
	}
}

void AAiQuizHUD::DrawMenu()
{
	const float CX = ScreenW * 0.5f;
	DrawText(MenuTitle, CX, ScreenH * 0.12f, ScreenH * 0.10f, FLinearColor(1.0f, 0.85f, 0.25f), true);

	const TArray<FString> Subjects = GM->GetAvailableSubjects();
	const int32 SubIdx = Subjects.Num() > 0 ? FMath::Clamp(GM->MenuSubjectIndex, 0, Subjects.Num() - 1) : 0;
	const FString CurSubject = Subjects.IsValidIndex(SubIdx) ? Subjects[SubIdx] : FString();
	const TArray<int32> Grades = GM->GetAvailableGrades(CurSubject);
	const int32 GradeIdx = Grades.Num() > 0 ? FMath::Clamp(GM->MenuGradeIndex, 0, Grades.Num() - 1) : 0;
	const int32 DiffIdx = FMath::Clamp(GM->MenuDifficultyIndex, 0, 2);

	const float RowPx = ScreenH * 0.045f;
	const FLinearColor Sel(1.0f, 0.9f, 0.3f), Dim(0.6f, 0.65f, 0.75f), Head(0.5f, 0.7f, 1.0f);

	auto DrawRow = [&](const TCHAR* Head1, const TArray<FString>& Items, int32 Selected, float Y)
	{
		DrawText(Head1, ScreenW * 0.5f, Y, RowPx, Head, true);
		// items centered as a single row
		FString Line;
		for (int32 i = 0; i < Items.Num(); ++i)
		{
			Line += (i == Selected) ? FString::Printf(TEXT("[ %s ]   "), *Items[i]) : FString::Printf(TEXT("%s   "), *Items[i]);
		}
		DrawText(Line, ScreenW * 0.5f, Y + RowPx * 1.2f, RowPx, Sel, true);
	};

	float Y = ScreenH * 0.34f;
	DrawRow(MenuSubject, Subjects, SubIdx, Y);
	Y += ScreenH * 0.14f;

	TArray<FString> GradeItems;
	for (int32 G : Grades) { GradeItems.Add(GradeLabel(G)); }
	DrawRow(MenuGrade, GradeItems, GradeIdx, Y);
	Y += ScreenH * 0.14f;

	TArray<FString> DiffItems = { DifficultyNames[0], DifficultyNames[1], DifficultyNames[2] };
	DrawRow(MenuDifficulty, DiffItems, DiffIdx, Y);

	DrawText(MenuStart, CX, ScreenH * 0.82f, ScreenH * 0.05f, FLinearColor(0.9f, 0.95f, 1.0f), true);
	DrawText(MenuControls, CX, ScreenH * 0.90f, ScreenH * 0.032f, Dim, true);
}

void AAiQuizHUD::DrawCountdown()
{
	const int32 N = GM->GetCountdownDisplay();
	if (N > 0)
	{
		DrawText(FString::FromInt(N), ScreenW * 0.5f, ScreenH * 0.34f, ScreenH * 0.26f, FLinearColor(1.0f, 0.9f, 0.3f), true);
	}
}

void AAiQuizHUD::DrawPlaying()
{
	// Score (top-left).
	DrawText(ScoreLine(GM->Score, GM->CurrentWallIndex + 1), ScreenW * 0.03f, ScreenH * 0.04f,
		ScreenH * 0.04f, FLinearColor(0.95f, 0.97f, 1.0f), false);

	// 10-question progress bar (top-center).
	const float BarW = ScreenW * 0.4f, BarH = ScreenH * 0.022f;
	const float BarX = ScreenW * 0.5f - BarW * 0.5f, BarY = ScreenH * 0.05f;
	FillRect(BarX, BarY, BarW, BarH, FLinearColor(0.12f, 0.14f, 0.22f, 0.85f));
	const float Frac = FMath::Clamp((float)GM->CurrentWallIndex / 10.0f, 0.0f, 1.0f);
	FillRect(BarX, BarY, BarW * Frac, BarH, FLinearColor(0.25f, 0.55f, 1.0f, 0.95f));

	// Streak (top-right).
	if (GM->CurrentStreak >= 2)
	{
		DrawText(StreakLine(GM->CurrentStreak), ScreenW * 0.97f - ScreenW * 0.2f, ScreenH * 0.10f,
			ScreenH * 0.035f, FLinearColor(1.0f, 0.6f, 0.2f), false);
	}

	// Question panel (top, below the bar).
	const FQuizItem Q = GM->GetCurrentQuiz();
	if (!Q.Q.IsEmpty())
	{
		const TArray<FString> Lines = Wrap(Q.Q, 26);
		const float LinePx = ScreenH * 0.04f;
		const float PanelTop = ScreenH * 0.10f;
		const float PanelH = LinePx * 1.35f * Lines.Num() + ScreenH * 0.02f;
		FillRect(ScreenW * 0.12f, PanelTop, ScreenW * 0.76f, PanelH, FLinearColor(0.03f, 0.05f, 0.12f, 0.55f));
		float Ly = PanelTop + ScreenH * 0.01f;
		for (const FString& Line : Lines)
		{
			DrawText(Line, ScreenW * 0.5f, Ly, LinePx, FLinearColor::White, true);
			Ly += LinePx * 1.35f;
		}
	}

	// Correct-answer message (center, fades with correct_flash).
	if (GM->CorrectFlash > 0.0f)
	{
		const float A = FMath::Clamp(GM->CorrectFlash * 2.0f, 0.0f, 1.0f);
		DrawText(Correct, ScreenW * 0.5f, ScreenH * 0.42f, ScreenH * 0.07f, FLinearColor(0.2f, 1.0f, 0.4f, A), true);
	}
}

void AAiQuizHUD::DrawResult()
{
	const bool bClear = (GM->State == EAiQuizState::Clear);
	// Godot 1P: the panel only appears after the 4s death animation (game_over fade).
	if (!bClear && GM->GameOverTimer < 4.0f) { return; }

	// Dark card.
	const float CardX = ScreenW * 0.22f, CardW = ScreenW * 0.56f;
	const float CardY = ScreenH * 0.16f, CardH = ScreenH * 0.66f;
	FillRect(CardX, CardY, CardW, CardH, FLinearColor(0.05f, 0.07f, 0.14f, 0.92f));
	const float CX = ScreenW * 0.5f;
	float Y = CardY + ScreenH * 0.03f;

	// Title.
	DrawText(bClear ? TitleClear : TitleGameOver, CX, Y, ScreenH * 0.09f,
		bClear ? FLinearColor(1.0f, 0.8f, 0.2f) : FLinearColor(1.0f, 0.3f, 0.3f), true);
	Y += ScreenH * 0.12f;

	// Big score + subtitle.
	DrawText(FString::FromInt(GM->Score), CX, Y, ScreenH * 0.08f,
		bClear ? FLinearColor(1.0f, 0.85f, 0.2f) : FLinearColor(0.9f, 0.92f, 0.95f), true);
	Y += ScreenH * 0.09f;
	DrawText(bClear ? ClearSub : ScoreSub, CX, Y, ScreenH * 0.032f, FLinearColor(0.6f, 0.65f, 0.75f), true);
	Y += ScreenH * 0.055f;

	// Stats row: 正答率 / 連続正解 / 時間.
	const float Rate = (GM->TotalAnswered > 0) ? ((float)GM->Score / (float)GM->TotalAnswered * 100.0f) : 0.0f;
	const int32 Mins = (int32)GM->PlayTime / 60;
	const int32 Secs = (int32)GM->PlayTime % 60;
	const float ColW = CardW / 3.0f;
	const float StatVY = Y, StatLY = Y + ScreenH * 0.045f;
	auto Stat = [&](int32 Col, const FString& Val, const TCHAR* Label, const FLinearColor& VC)
	{
		const float Cx = CardX + ColW * (Col + 0.5f);
		DrawText(Val, Cx, StatVY, ScreenH * 0.04f, VC, true);
		DrawText(Label, Cx, StatLY, ScreenH * 0.028f, FLinearColor(0.45f, 0.5f, 0.6f), true);
	};
	const FLinearColor RateColor = Rate >= 80.f ? FLinearColor(0.3f, 1.0f, 0.5f) : (Rate >= 50.f ? FLinearColor(1.0f, 0.85f, 0.3f) : FLinearColor(1.0f, 0.4f, 0.3f));
	Stat(0, FString::Printf(TEXT("%.0f%%"), Rate), StatRate, RateColor);
	Stat(1, FString::FromInt(GM->MaxStreak), StatStreak, FLinearColor(1.0f, 0.6f, 0.2f));
	Stat(2, FString::Printf(TEXT("%d:%02d"), Mins, Secs), StatTime, FLinearColor(0.65f, 0.7f, 0.82f));
	Y = StatLY + ScreenH * 0.06f;

	// Reason + explanation (game over only).
	if (!bClear)
	{
		const FQuizItem Q = GM->GetCurrentQuiz();
		FString Reason;
		if (GM->LastOverReason == EAiQuizOverReason::Magma)
		{
			Reason = MagmaMsg;
		}
		else
		{
			// game_state.gd:1506-1521 — in 1P a pillar smash (Door<0) and a wrong door BOTH
			// show "不正解！ 正解は <answer>"; only magma death uses a different message.
			const int32 NC = GM->GetNumChoices();
			const int32 A = FMath::Clamp(Q.A, 0, NC - 1);
			const FString Lbl = (NC == 2) ? FString(Door2[FMath::Clamp(A, 0, 1)]) : FString(Door4[FMath::Clamp(A, 0, 3)]);
			Reason = WrongDoorMsg(Lbl);
		}
		DrawText(Reason, CX, Y, ScreenH * 0.04f, FLinearColor(1.0f, 0.55f, 0.5f), true);
		Y += ScreenH * 0.06f;

		if (!Q.E.IsEmpty())
		{
			for (const FString& Line : Wrap(Q.E, 30))
			{
				DrawText(Line, CX, Y, ScreenH * 0.032f, FLinearColor(0.82f, 0.85f, 0.92f), true);
				Y += ScreenH * 0.042f;
			}
		}
	}

	// Prompts.
	DrawText(ResultPrompt, CX, CardY + CardH - ScreenH * 0.06f, ScreenH * 0.038f, FLinearColor(0.85f, 0.9f, 1.0f), true);
}

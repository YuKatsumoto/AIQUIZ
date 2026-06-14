// Phase 6/7 — headless ("無描画") verification of the quiz-wall pooling and the
// full menu->round->result loop, on top of the Phase 2 state-machine tests.
//
//   UnrealEditor-Cmd AiQuiz.uproject -NullRHI -unattended -nopause -nosplash -nosound \
//     -ExecCmds="Automation RunTests AiQuiz" -TestExit="Automation Test Queue Empty" -log
//
// All distances are METERS, identical to aiquiz_game_specification.md.

#include "CoreMinimal.h"
#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"
#include "AiQuizGameModeBase.h"
#include "AiQuizWorld.h"
#include "AiQuizWall.h"
#include "AiQuizTypes.h"
#include "QuizItem.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace AiQuizP67
{
	static FQuizItem MakeQuiz(int32 Answer, float T = 4.0f)
	{
		FQuizItem Q;
		Q.Subject = TEXT("Test"); Q.Grade = 3; Q.Q = TEXT("Q");
		Q.C = { TEXT("L"), TEXT("R") };
		Q.A = Answer; Q.T = T; Q.NumChoices = 2;
		return Q;
	}
	static bool StepUntil(AAiQuizGameModeBase* GM, TFunctionRef<bool()> P, int32 Max = 6000)
	{
		const float Dt = 1.0f / 60.0f;
		for (int32 i = 0; i < Max; ++i) { if (P()) { return true; } GM->TestStep(Dt); }
		return P();
	}
}

// ---------------------------------------------------------------------------
// Wall pooling — pure index math (game_world.gd::_update_walls), no world needed.
// ---------------------------------------------------------------------------
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FAiQuizWallPoolingTest,
	"AiQuiz.Wall.Pooling",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FAiQuizWallPoolingTest::RunTest(const FString& /*Parameters*/)
{
	const float WallStartZ = 22.0f, WallSpacing = 30.0f, FloorBackZ = -12.5f;
	const int32 MaxVisible = 4, Target = 10;

	// --- Start of the run: scroll=0, current=0. Walls 0..6 visible (MAX_VISIBLE+3=7 slots). ---
	{
		const TArray<int32> N = AAiQuizWorld::ComputeNeededIndices(0, Target, 0.0f, WallStartZ, WallSpacing, FloorBackZ, MaxVisible);
		TestTrue(TEXT("start: wall 0 needed"), N.Contains(0));
		TestEqual(TEXT("start: 7 walls (MAX_VISIBLE+3)"), N.Num(), 7);
		TestEqual(TEXT("start: furthest is wall 6"), N.Last(), 6);
		TestFalse(TEXT("start: wall 7 not yet needed"), N.Contains(7));
	}

	// --- Scrolled so wall 0 has fallen behind FLOOR_BACK_Z (local z <= -12.5). ---
	{
		// wall0 localZ = 22 - scroll; choose scroll so localZ = -13.5 < -12.5.
		const float Scroll = 35.5f;
		const TArray<int32> N = AAiQuizWorld::ComputeNeededIndices(1, Target, Scroll, WallStartZ, WallSpacing, FloorBackZ, MaxVisible);
		TestFalse(TEXT("scrolled: culled wall 0 dropped"), N.Contains(0));
		TestTrue(TEXT("scrolled: wall 1 still needed"), N.Contains(1));
	}

	// --- Near the end: current=9, target=10. Never spawn past wall 9 (max_wall_idx). ---
	{
		const TArray<int32> N = AAiQuizWorld::ComputeNeededIndices(9, Target, 9.0f * WallSpacing, WallStartZ, WallSpacing, FloorBackZ, MaxVisible);
		TestTrue(TEXT("end: wall 9 needed"), N.Contains(9));
		TestFalse(TEXT("end: wall 10 never spawned (fixed count)"), N.Contains(10));
		for (int32 Idx : N) { TestTrue(TEXT("end: no index beyond target-1"), Idx <= 9); }
	}

	return true;
}

// ---------------------------------------------------------------------------
// Phase 6/7 GameMode additions: flash decay, death physics, full result/menu loop.
// ---------------------------------------------------------------------------
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FAiQuizLoopTest,
	"AiQuiz.Loop.MenuAndResult",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FAiQuizLoopTest::RunTest(const FString& /*Parameters*/)
{
	using namespace AiQuizP67;

	// ---- Flash / shake decay rates (game_state.gd:610-612) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		GM->CorrectFlash = 1.0f; GM->WrongFlash = 1.0f; GM->CameraShake = 1.0f;
		GM->TestStep(0.1f);
		TestEqual(TEXT("correct_flash decays at 1.5/s"), GM->CorrectFlash, 1.0f - 0.1f * 1.5f, 0.001f);
		TestEqual(TEXT("wrong_flash decays at 1.2/s"), GM->WrongFlash, 1.0f - 0.1f * 1.2f, 0.001f);
		TestEqual(TEXT("camera_shake decays at 2.8/s"), GM->CameraShake, 1.0f - 0.1f * 2.8f, 0.001f);
	}

	// ---- Countdown shows 3 -> 2 -> 1 ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0) };
		GM->StartRoundWithQuizzes(Q, 1);
		TestEqual(TEXT("countdown shows 3 at start"), GM->GetCountdownDisplay(), 3);
		GM->TestStep(1.01f);
		TestEqual(TEXT("countdown shows 2 after ~1s"), GM->GetCountdownDisplay(), 2);
		GM->TestStep(1.0f);
		TestEqual(TEXT("countdown shows 1"), GM->GetCountdownDisplay(), 1);
	}

	// ---- Correct door fires no-stop continue + sets correct_flash (game_state.gd:1499-1505) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0), MakeQuiz(0) }; // answer = door 0 (+3.5)
		GM->StartRoundWithQuizzes(Q, 2);
		GM->TestStep(3.01f);
		GM->PlayerX = 3.5f;
		StepUntil(GM.Get(), [&]() { return GM->CurrentWallIndex >= 1; });
		TestTrue(TEXT("correct -> still Playing (no stop)"), GM->State == EAiQuizState::Playing);
		TestEqual(TEXT("correct -> score 1"), GM->Score, 1);
		TestEqual(TEXT("correct -> streak 1"), GM->CurrentStreak, 1);
		TestTrue(TEXT("correct -> correct_flash raised"), GM->CorrectFlash > 0.5f);
	}

	// ---- Wrong door: game over with knockback velocities (game_state.gd:1439-1450) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0) }; // correct = door 0 (+3.5)
		GM->StartRoundWithQuizzes(Q, 1);
		GM->TestStep(3.01f);
		GM->PlayerX = -3.5f; // wrong door
		StepUntil(GM.Get(), [&]() { return GM->State != EAiQuizState::Playing; });
		TestTrue(TEXT("wrong -> GameOver"), GM->State == EAiQuizState::GameOver);
		TestTrue(TEXT("wrong -> reason WrongDoor"), GM->LastOverReason == EAiQuizOverReason::WrongDoor);
		TestEqual(TEXT("wrong -> VelY knockback = JUMP*0.8"), GM->VelY, 7.0f * 0.8f, 0.01f);
		TestEqual(TEXT("wrong -> VelZ knockback = -12"), GM->VelZ, -12.0f, 0.01f);
		TestTrue(TEXT("wrong -> wrong_flash raised"), GM->WrongFlash > 0.5f);

		// Death physics: timer ticks and the body flies backward (PlayerWorldZ decreases).
		const float Z0 = GM->PlayerWorldZ;
		for (int32 i = 0; i < 10; ++i) { GM->TestStep(1.0f / 60.0f); }
		TestTrue(TEXT("game_over_timer advances"), GM->GameOverTimer > 0.1f);
		TestTrue(TEXT("dead body knocked backward"), GM->PlayerWorldZ < Z0);
	}

	// ---- Clearing the target fires CLEAR (game_state.gd:496->clear_game) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0), MakeQuiz(0), MakeQuiz(0) };
		GM->StartRoundWithQuizzes(Q, 3);
		GM->TestStep(3.01f);
		GM->PlayerX = 3.5f;
		StepUntil(GM.Get(), [&]() { return GM->State == EAiQuizState::Clear || GM->State == EAiQuizState::GameOver; });
		TestTrue(TEXT("3 corrects -> Clear"), GM->State == EAiQuizState::Clear);
		TestEqual(TEXT("clear -> score 3"), GM->Score, 3);
		TestTrue(TEXT("clear -> correct_flash raised"), GM->CorrectFlash > 0.5f);
	}

	// ---- Menu data + full menu->round->menu loop (uses DT_QuizBank) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TestTrue(TEXT("starts at Menu"), GM->State == EAiQuizState::Menu);

		const TArray<FString> Subjects = GM->GetAvailableSubjects();
		TestTrue(TEXT("DataTable exposes >=1 subject"), Subjects.Num() >= 1);
		if (Subjects.Num() >= 1)
		{
			const TArray<int32> Grades = GM->GetAvailableGrades(Subjects[0]);
			TestTrue(TEXT("subject exposes >=1 grade"), Grades.Num() >= 1);

			GM->MenuSubjectIndex = 0; GM->MenuGradeIndex = 0; GM->MenuDifficultyIndex = 1; // Normal -> 2 doors
			GM->StartRoundFromMenu();
			TestTrue(TEXT("StartRoundFromMenu -> Countdown"), GM->State == EAiQuizState::Countdown);
			TestTrue(TEXT("loaded quizzes from the bank"), GM->Quizzes.Num() > 0);
			TestTrue(TEXT("Normal difficulty -> 2-choice walls"), GM->GetNumChoices() == 2);

			GM->TestStep(3.01f);
			TestTrue(TEXT("countdown over -> Playing"), GM->State == EAiQuizState::Playing);

			GM->ReturnToMenu();
			TestTrue(TEXT("ReturnToMenu -> Menu"), GM->State == EAiQuizState::Menu);
			TestEqual(TEXT("ReturnToMenu clears quizzes"), GM->Quizzes.Num(), 0);
		}
	}

	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// Phase 2 — headless ("無描画") verification of the AIQUIZ core state machine.
//
// Drives AAiQuizGameModeBase with dummy input (no PIE, no rendering, no DataTable)
// and asserts that every transition matches the Godot source of truth
// (AIQUIZ-Godot/scripts/core/game_state.gd). Run via:
//
//   UnrealEditor-Cmd AiQuiz.uproject -NullRHI -unattended -nopause -nosplash -nosound \
//     -ExecCmds="Automation RunTests AiQuiz.StateMachine.CoreTransitions" \
//     -TestExit="Automation Test Queue Empty" -log
//
// All distances are METERS, identical to aiquiz_game_specification.md.

#include "CoreMinimal.h"
#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"
#include "AiQuizGameModeBase.h"
#include "AiQuizTypes.h"
#include "QuizItem.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace AiQuizTestHelpers
{
	// A deterministic 2-choice question. Door 0 center = +3.5 ("left"), door 1 = -3.5
	// ("right"), each half-width 1.8 (game_tuning.gd). T=4.0 -> first wall speed
	// 28/(4+3.5) = 3.733 m/s.
	static FQuizItem MakeQuiz(int32 Answer, float T = 4.0f)
	{
		FQuizItem Q;
		Q.Subject = TEXT("Test");
		Q.Grade = 3;
		Q.Q = TEXT("Q");
		Q.C = { TEXT("L"), TEXT("R") };
		Q.A = Answer;
		Q.T = T;
		Q.NumChoices = 2;
		return Q;
	}

	// Tick the state machine (dt = 1/60) until Predicate() holds or MaxSteps is hit.
	static bool StepUntil(AAiQuizGameModeBase* GM, TFunctionRef<bool()> Predicate, int32 MaxSteps = 6000)
	{
		const float Dt = 1.0f / 60.0f;
		for (int32 i = 0; i < MaxSteps; ++i)
		{
			if (Predicate())
			{
				return true;
			}
			GM->TestStep(Dt);
		}
		return Predicate();
	}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FAiQuizStateMachineTest,
	"AiQuiz.StateMachine.CoreTransitions",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FAiQuizStateMachineTest::RunTest(const FString& /*Parameters*/)
{
	using namespace AiQuizTestHelpers;

	// ---- Scenario A: Menu -> Countdown -> Playing ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TestTrue(TEXT("A: initial state is Menu"), GM->State == EAiQuizState::Menu);

		TArray<FQuizItem> Q = { MakeQuiz(0), MakeQuiz(0), MakeQuiz(0) };
		GM->StartRoundWithQuizzes(Q, 3);
		TestTrue(TEXT("A: StartRound -> Countdown"), GM->State == EAiQuizState::Countdown);
		TestEqual(TEXT("A: TargetCount = 3"), GM->TargetCount, 3);
		TestEqual(TEXT("A: first wall speed = 28/(4+3.5)"), GM->ActiveWallSpeed, 28.0f / 7.5f, 0.01f);

		GM->TestStep(3.01f); // exhaust the 3s countdown
		TestTrue(TEXT("A: countdown over -> Playing"), GM->State == EAiQuizState::Playing);
	}

	// ---- Scenario B: correct door keeps PLAYING (no stop), clears at target ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0), MakeQuiz(0), MakeQuiz(0) }; // answer = door 0 (+3.5)
		GM->StartRoundWithQuizzes(Q, 3);
		GM->TestStep(3.01f);
		TestTrue(TEXT("B: Playing"), GM->State == EAiQuizState::Playing);

		GM->PlayerX = 3.5f; // sit in the correct door for every wall
		const bool bTerminal = StepUntil(GM.Get(),
			[&]() { return GM->State == EAiQuizState::Clear || GM->State == EAiQuizState::GameOver; });
		TestTrue(TEXT("B: reached a terminal state"), bTerminal);
		TestTrue(TEXT("B: three corrects -> Clear"), GM->State == EAiQuizState::Clear);
		TestEqual(TEXT("B: score == 3"), GM->Score, 3);
		TestEqual(TEXT("B: advanced past wall 3"), GM->CurrentWallIndex, 3);
	}

	// ---- Scenario C: wrong door -> GameOver(WrongDoor) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0) }; // correct = door 0 (+3.5)
		GM->StartRoundWithQuizzes(Q, 1);
		GM->TestStep(3.01f);
		GM->PlayerX = -3.5f; // door 1 (wrong)
		StepUntil(GM.Get(), [&]() { return GM->State != EAiQuizState::Playing; });
		TestTrue(TEXT("C: wrong door -> GameOver"), GM->State == EAiQuizState::GameOver);
		TestTrue(TEXT("C: reason = WrongDoor"), GM->LastOverReason == EAiQuizOverReason::WrongDoor);
		TestEqual(TEXT("C: score stays 0"), GM->Score, 0);
	}

	// ---- Scenario D: between doors (pillar) -> GameOver(Wall) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0) };
		GM->StartRoundWithQuizzes(Q, 1);
		GM->TestStep(3.01f);
		GM->PlayerX = 0.0f; // x=0 is inside neither [1.7,5.3] nor [-5.3,-1.7] -> pillar
		StepUntil(GM.Get(), [&]() { return GM->State != EAiQuizState::Playing; });
		TestTrue(TEXT("D: pillar -> GameOver"), GM->State == EAiQuizState::GameOver);
		TestTrue(TEXT("D: reason = Wall"), GM->LastOverReason == EAiQuizOverReason::Wall);
	}

	// ---- Scenario E: run off the side -> magma death (player_y < -8) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0) };
		GM->StartRoundWithQuizzes(Q, 1);
		GM->TestStep(3.01f);
		GM->PlayerX = 13.0f; // beyond FloorHalfWidth(12) -> no floor underfoot -> falls
		const bool bDied = StepUntil(GM.Get(), [&]() { return GM->State != EAiQuizState::Playing; }, 600);
		TestTrue(TEXT("E: side fall ends the round"), bDied);
		TestTrue(TEXT("E: side fall -> GameOver"), GM->State == EAiQuizState::GameOver);
		TestTrue(TEXT("E: reason = Magma"), GM->LastOverReason == EAiQuizOverReason::Magma);
	}

	// ---- Scenario F: jump arc fidelity (v=7, g=18) ----
	// Continuous apex = v^2/(2g) = 49/36 ~= 1.361 m, but both Godot and this port use the
	// SAME explicit-Euler step (set VelY, subtract g*dt, integrate position), which undershoots
	// the closed form by ~4% at 60 fps (measured ~1.303 m). The faithful assertion is that the
	// apex tracks that shared discrete integration, so we allow a 0.07 m band bracketing the
	// discrete value while still rejecting any gross physics regression.
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		TArray<FQuizItem> Q = { MakeQuiz(0) };
		GM->StartRoundWithQuizzes(Q, 1);
		GM->TestStep(3.01f);
		GM->PlayerX = 3.5f;          // stay over the floor; wall is far (z=22) so no early hit
		GM->SetInput(0.0f, true);    // queue a jump

		float MaxY = 0.0f;
		for (int32 i = 0; i < 90; ++i) // ~1.5s covers the full arc
		{
			GM->TestStep(1.0f / 60.0f);
			MaxY = FMath::Max(MaxY, GM->PlayerY);
			GM->SetInput(0.0f, false);
		}
		TestEqual(TEXT("F: jump apex ~= 1.361 m (60fps Euler ~= 1.303)"), MaxY, 49.0f / 36.0f, 0.07f);
		TestTrue(TEXT("F: apex undershoots the continuous ideal (Euler)"), MaxY < 49.0f / 36.0f);
		TestTrue(TEXT("F: still Playing after a grounded jump"), GM->State == EAiQuizState::Playing);
		TestEqual(TEXT("F: landed back on the floor"), GM->PlayerY, 0.0f, 0.001f);
	}

	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

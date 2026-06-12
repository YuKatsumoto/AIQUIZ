// Phase 4/5 — headless verification of the Pawn's pure mappings:
//  (1) the coordinate transform incl. the D/Right "sign trap", and
//  (2) the state -> animation-clip selection ladder.
// No PIE, no input injection: we drive the GameMode state machine and assert the
// Pawn's static helpers, which is exactly the chain key->state->visual.

#include "CoreMinimal.h"
#include "Misc/AutomationTest.h"
#include "UObject/StrongObjectPtr.h"
#include "AiQuizPawn.h"
#include "AiQuizGameModeBase.h"
#include "AiQuizTypes.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FAiQuizPawnMappingTest,
	"AiQuiz.Pawn.CoordsAndAnim",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FAiQuizPawnMappingTest::RunTest(const FString& /*Parameters*/)
{
	// ---- Coordinate transform (UU=100, floor top -120) ----
	{
		// At rest: centred, on the floor. (FVector components are double in UE5 -> cast.)
		const FVector Rest = AAiQuizPawn::ComputePawnLocation(0.0f, 0.0f, 0.0f);
		TestEqual(TEXT("rest X (fixed, treadmill)"), (float)Rest.X, 0.0f, 0.01f);
		TestEqual(TEXT("rest Y (centred)"), (float)Rest.Y, 0.0f, 0.01f);
		TestEqual(TEXT("rest Z (floor top)"), (float)Rest.Z, -120.0f, 0.01f);

		// THE SIGN TRAP: the door the game calls "right" is right_door_x = -3.5 (Godot).
		// With UE_Y = -100*PlayerX it must sit at +350 (+Y), and "left" (+3.5) at -350.
		const FVector RightDoor = AAiQuizPawn::ComputePawnLocation(0.0f, -3.5f, 0.0f);
		TestEqual(TEXT("right door (PlayerX=-3.5) -> UE +Y"), (float)RightDoor.Y, 350.0f, 0.01f);
		const FVector LeftDoor = AAiQuizPawn::ComputePawnLocation(0.0f, 3.5f, 0.0f);
		TestEqual(TEXT("left door (PlayerX=+3.5) -> UE -Y"), (float)LeftDoor.Y, -350.0f, 0.01f);

		// Height maps up: a 1.36 m jump apex sits 136 uu above the floor.
		const FVector Apex = AAiQuizPawn::ComputePawnLocation(0.0f, 0.0f, 1.36f);
		TestEqual(TEXT("apex Z = floor + 136"), (float)Apex.Z, -120.0f + 136.0f, 0.01f);
	}

	// ---- Full chain: pressing D/Right moves the pawn toward the RIGHT door (+Y) ----
	{
		TStrongObjectPtr<AAiQuizGameModeBase> GM(NewObject<AAiQuizGameModeBase>());
		GM->bAutoStartInPIE = false;
		TArray<FQuizItem> None;
		GM->StartRoundWithQuizzes(None, 0); // free-run, no walls
		GM->TestStep(3.01f);                // exhaust countdown -> Playing
		TestTrue(TEXT("Playing"), GM->State == EAiQuizState::Playing);

		const float X0 = GM->PlayerX;
		// D / Right key -> AxisX = -1.0 (the Pawn forwards this verbatim).
		for (int32 i = 0; i < 30; ++i) { GM->SetInput(-1.0f, false); GM->TestStep(1.0f / 60.0f); }
		TestTrue(TEXT("D/Right decreases PlayerX (toward right_door_x=-3.5)"), GM->PlayerX < X0);

		const FVector Loc = AAiQuizPawn::ComputePawnLocation(GM->GetPlayerLocalZ(), GM->PlayerX, GM->PlayerY);
		TestTrue(TEXT("D/Right moves the pawn toward +Y (visual right)"), Loc.Y > 0.0f);
	}

	// ---- Animation selection ladder (animation_rig.gd:291-332) ----
	{
		TestTrue(TEXT("Playing+grounded -> Run"),
			AAiQuizPawn::SelectAnim(EAiQuizState::Playing, 0.0f, 0.0f) == EAiQuizAnim::Run);
		TestTrue(TEXT("Menu/grounded -> Idle"),
			AAiQuizPawn::SelectAnim(EAiQuizState::Menu, 0.0f, 0.0f) == EAiQuizAnim::Idle);
		TestTrue(TEXT("airborne rising -> Jump"),
			AAiQuizPawn::SelectAnim(EAiQuizState::Playing, 0.5f, 5.0f) == EAiQuizAnim::Jump);
		TestTrue(TEXT("airborne descending -> Fall"),
			AAiQuizPawn::SelectAnim(EAiQuizState::Playing, 0.5f, -5.0f) == EAiQuizAnim::Fall);
		TestTrue(TEXT("below magma line -> Drowning"),
			AAiQuizPawn::SelectAnim(EAiQuizState::Playing, -2.0f, -5.0f) == EAiQuizAnim::Drowning);
		TestTrue(TEXT("GameOver grounded -> Idle"),
			AAiQuizPawn::SelectAnim(EAiQuizState::GameOver, 0.0f, 0.0f) == EAiQuizAnim::Idle);
	}

	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

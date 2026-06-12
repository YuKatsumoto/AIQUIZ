#include "AiQuizGameModeBase.h"
#include "AiQuizPawn.h"
#include "Engine/DataTable.h"
#include "UObject/ConstructorHelpers.h"

DEFINE_LOG_CATEGORY_STATIC(LogAiQuiz, Log, All);

AAiQuizGameModeBase::AAiQuizGameModeBase()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;
	DefaultPawnClass = AAiQuizPawn::StaticClass();
}

void AAiQuizGameModeBase::BeginPlay()
{
	Super::BeginPlay();
	ResolveQuizBank();

	if (bAutoStartInPIE)
	{
		// Phase 4/5: enter gameplay immediately. count=0 -> empty quiz list -> free-run
		// (no walls, no door collision) so movement / jump / fall / camera / anim can be
		// observed indefinitely. Real rounds come from the menu in Phase 7.
		const TArray<FQuizItem> Empty;
		StartRoundWithQuizzes(Empty, DebugAutoStartCount);
		UE_LOG(LogAiQuiz, Display, TEXT("Auto-start (PIE): free-run round, count=%d"), DebugAutoStartCount);
	}
}

UDataTable* AAiQuizGameModeBase::ResolveQuizBank()
{
	if (QuizBank)
	{
		return QuizBank;
	}
	UDataTable* DT = LoadObject<UDataTable>(nullptr, TEXT("/Game/AiQuiz/Data/DT_QuizBank.DT_QuizBank"));
	QuizBank = DT;
	if (!DT)
	{
		UE_LOG(LogAiQuiz, Error, TEXT("DT_QuizBank could not be loaded."));
	}
	return DT;
}

void AAiQuizGameModeBase::SetInput(float AxisX, bool bJumpPressed)
{
	InputAxisX = AxisX;
	if (bJumpPressed)
	{
		bJumpQueued = true;
	}
}

float AAiQuizGameModeBase::GetWallWorldZ(int32 Index) const
{
	return WallStartZ + (float)Index * WallSpacing;
}

FQuizItem AAiQuizGameModeBase::GetCurrentQuiz() const
{
	if (Quizzes.IsValidIndex(CurrentWallIndex))
	{
		return Quizzes[CurrentWallIndex];
	}
	return FQuizItem();
}

float AAiQuizGameModeBase::GetDoorCenterX(int32 NumChoices, int32 ChoiceIndex) const
{
	if (NumChoices == 2)
	{
		const float Centers[2] = { 3.5f, -3.5f };          // choice 0 = left, 1 = right
		return Centers[FMath::Clamp(ChoiceIndex, 0, 1)];
	}
	const float Centers[4] = { -5.8f, -1.95f, 1.95f, 5.8f }; // 4-choice (game_tuning.gd door4_xs)
	return Centers[FMath::Clamp(ChoiceIndex, 0, 3)];
}

float AAiQuizGameModeBase::GetDoorHalfWidth(int32 NumChoices) const
{
	return (NumChoices == 2) ? 1.8f : 1.45f;
}

int32 AAiQuizGameModeBase::CheckPlayerDoor(float X, const FQuizItem& Q) const
{
	const int32 N = (Q.NumChoices == 2) ? 2 : 4;
	const float HalfW = GetDoorHalfWidth(N);
	for (int32 i = 0; i < N; ++i)
	{
		if (FMath::Abs(X - GetDoorCenterX(N, i)) <= HalfW)
		{
			return i;
		}
	}
	return -1; // hit a pillar / between doors -> crash
}

void AAiQuizGameModeBase::SetState(EAiQuizState NewState)
{
	if (State == NewState)
	{
		return;
	}
	State = NewState;
	UE_LOG(LogAiQuiz, Display, TEXT("State -> %s"), *UEnum::GetValueAsString(NewState));
}

void AAiQuizGameModeBase::RecalcWallSpeed()
{
	float Est = 4.0f;
	if (Quizzes.IsValidIndex(CurrentWallIndex))
	{
		Est = FMath::Max(0.1f, Quizzes[CurrentWallIndex].T);
	}
	const float StageFactor = 1.0f + FMath::Clamp((float)CurrentWallIndex / 9.0f, 0.0f, 1.0f) * 0.15f;
	const float Speed = VisibleDistance / (Est + MoveBuffer) * StageFactor;
	ActiveWallSpeed = FMath::Clamp(Speed, WallSpeedMin, WallSpeedMax);
}

void AAiQuizGameModeBase::LoadQuizzes(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count)
{
	Quizzes.Reset();
	UDataTable* DT = ResolveQuizBank();
	if (!DT)
	{
		return;
	}

	TArray<FQuizItem> Pool;
	for (const TPair<FName, uint8*>& Row : DT->GetRowMap())
	{
		const FQuizItem* Item = reinterpret_cast<const FQuizItem*>(Row.Value);
		if (Item && Item->Subject == Subject && Item->Grade == Grade)
		{
			Pool.Add(*Item);
		}
	}

	// Fisher-Yates shuffle
	for (int32 i = Pool.Num() - 1; i > 0; --i)
	{
		Pool.Swap(i, FMath::RandRange(0, i));
	}

	const bool bIsHard = (Difficulty == EAiQuizDifficulty::Hard);

	for (int32 i = 0; i < Pool.Num() && Quizzes.Num() < Count; ++i)
	{
		FQuizItem Q = Pool[i];
		// 4-choice -> 2-choice reduction for non-hard (game_state.gd:529-549)
		if (!bIsHard && Q.NumChoices == 4 && Q.C.Num() == 4)
		{
			const int32 Correct = FMath::Clamp(Q.A, 0, 3);
			TArray<int32> Distractors;
			for (int32 k = 0; k < 4; ++k)
			{
				if (k != Correct) { Distractors.Add(k); }
			}
			const int32 D = Distractors[FMath::RandRange(0, Distractors.Num() - 1)];
			TArray<FString> NewC;
			int32 NewCorrect;
			if (FMath::RandBool())
			{
				NewC.Add(Q.C[Correct]); NewC.Add(Q.C[D]); NewCorrect = 0;
			}
			else
			{
				NewC.Add(Q.C[D]); NewC.Add(Q.C[Correct]); NewCorrect = 1;
			}
			Q.C = NewC;
			Q.A = NewCorrect;
			Q.NumChoices = 2;
		}
		Quizzes.Add(Q);
	}

	UE_LOG(LogAiQuiz, Display, TEXT("LoadQuizzes subject=%s grade=%d diff=%d -> %d items (pool=%d)"),
		*Subject, Grade, (int32)Difficulty, Quizzes.Num(), Pool.Num());
}

void AAiQuizGameModeBase::ResetRoundState()
{
	PlayerX = 0.0f;
	PlayerY = 0.0f;
	PlayerWorldZ = 0.0f;
	VelY = 0.0f;
	WorldScrollZ = 0.0f;
	CurrentWallIndex = 0;
	Score = 0;
	bOnFloor = true;
	InputAxisX = 0.0f;
	bJumpQueued = false;
	LastOverReason = EAiQuizOverReason::None;

	RecalcWallSpeed();
	CountdownTimer = CountdownSeconds;
	SetState(EAiQuizState::Countdown);
}

void AAiQuizGameModeBase::StartRound(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count)
{
	LoadQuizzes(Subject, Grade, Difficulty, Count);
	TargetCount = FMath::Min(Count, Quizzes.Num());
	ResetRoundState();

	UE_LOG(LogAiQuiz, Display, TEXT("StartRound target=%d firstSpeed=%.2f"), TargetCount, ActiveWallSpeed);
}

void AAiQuizGameModeBase::StartRoundWithQuizzes(const TArray<FQuizItem>& InQuizzes, int32 Count)
{
	Quizzes = InQuizzes;
	TargetCount = FMath::Min(Count, Quizzes.Num());
	ResetRoundState();

	UE_LOG(LogAiQuiz, Display, TEXT("StartRoundWithQuizzes target=%d items=%d firstSpeed=%.2f"),
		TargetCount, Quizzes.Num(), ActiveWallSpeed);
}

void AAiQuizGameModeBase::UpdatePlaying(float Dt)
{
	// Treadmill: world scrolls toward player; player world Z advances equally.
	WorldScrollZ += ActiveWallSpeed * Dt;
	PlayerWorldZ += ActiveWallSpeed * Dt;

	// Lateral movement. NO clamp — game_state.gd removed it so the player can run
	// off the sides and fall into the magma (PlayerX += axis * speed * dt).
	PlayerX += InputAxisX * PlayerSpeed * Dt;

	// On-floor test (game_state.gd::_is_on_track_floor). In the slice the player's
	// local Z stays ~0 (advances with the scroll), so FLOOR_BACK_Z is always met
	// and only the lateral half-width matters.
	const bool bOverFloor = FMath::Abs(PlayerX) <= FloorHalfWidth;

	// Jump must come from the floor (game_state.gd checks player_y<=0 && is_on_floor).
	if (bJumpQueued && PlayerY <= 0.0f && bOverFloor)
	{
		VelY = JumpForce;
	}
	bJumpQueued = false;

	// Gravity
	VelY -= Gravity * Dt;
	PlayerY += VelY * Dt;

	// Land only when standing over the floor; otherwise keep falling.
	bOnFloor = false;
	if (PlayerY <= 0.0f && bOverFloor)
	{
		PlayerY = 0.0f;
		VelY = 0.0f;
		bOnFloor = true;
	}

	// Magma death: fell off the side and dropped past the kill plane (player_y < -8).
	if (PlayerY < MagmaDeathY)
	{
		PlayerY = MagmaDeathY;
		VelY = 0.0f;
		DoGameOver(EAiQuizOverReason::Magma);
		return;
	}

	// Wall collision / door judgement (world coords, like game_state.gd).
	if (Quizzes.IsValidIndex(CurrentWallIndex))
	{
		const float WallZ = GetWallWorldZ(CurrentWallIndex);
		if (PlayerWorldZ >= WallZ - HitOffsetZ)
		{
			PlayerWorldZ = WallZ - HitOffsetZ; // prevent clipping through (game_state.gd:899)
			ResolveCollision();
		}
	}
}

void AAiQuizGameModeBase::ResolveCollision()
{
	if (!Quizzes.IsValidIndex(CurrentWallIndex))
	{
		return;
	}
	const FQuizItem Q = Quizzes[CurrentWallIndex];
	const int32 Door = CheckPlayerDoor(PlayerX, Q);
	if (Door == Q.A)
	{
		AdvanceAfterCorrect();
	}
	else if (Door < 0)
	{
		DoGameOver(EAiQuizOverReason::Wall);      // missed every door / hit a pillar
	}
	else
	{
		DoGameOver(EAiQuizOverReason::WrongDoor);  // entered the wrong door
	}
}

void AAiQuizGameModeBase::AdvanceAfterCorrect()
{
	Score++;
	CurrentWallIndex++;
	UE_LOG(LogAiQuiz, Display, TEXT("Correct! score=%d nextWall=%d"), Score, CurrentWallIndex);
	if (CurrentWallIndex >= TargetCount || CurrentWallIndex >= Quizzes.Num())
	{
		SetState(EAiQuizState::Clear);
	}
	else
	{
		RecalcWallSpeed(); // stay in Playing
	}
}

void AAiQuizGameModeBase::DoGameOver(EAiQuizOverReason Reason)
{
	LastOverReason = Reason;
	UE_LOG(LogAiQuiz, Display, TEXT("GameOver reason=%s wall=%d score=%d"),
		*UEnum::GetValueAsString(Reason), CurrentWallIndex, Score);
	SetState(EAiQuizState::GameOver);
}

void AAiQuizGameModeBase::TestStep(float Dt)
{
	switch (State)
	{
	case EAiQuizState::Countdown:
		CountdownTimer -= Dt;
		if (CountdownTimer <= 0.0f) { SetState(EAiQuizState::Playing); }
		break;
	case EAiQuizState::Playing:
		UpdatePlaying(Dt);
		break;
	default:
		break;
	}
}

void AAiQuizGameModeBase::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	switch (State)
	{
	case EAiQuizState::Countdown:
		CountdownTimer -= DeltaSeconds;
		if (CountdownTimer <= 0.0f)
		{
			SetState(EAiQuizState::Playing);
		}
		break;
	case EAiQuizState::Playing:
		UpdatePlaying(DeltaSeconds);
		break;
	default:
		break;
	}
}

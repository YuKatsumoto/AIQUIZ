#include "AiQuizGameModeBase.h"
#include "Engine/DataTable.h"
#include "UObject/ConstructorHelpers.h"

DEFINE_LOG_CATEGORY_STATIC(LogAiQuiz, Log, All);

AAiQuizGameModeBase::AAiQuizGameModeBase()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;
}

void AAiQuizGameModeBase::BeginPlay()
{
	Super::BeginPlay();
	ResolveQuizBank();
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

void AAiQuizGameModeBase::StartRound(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count)
{
	LoadQuizzes(Subject, Grade, Difficulty, Count);
	TargetCount = FMath::Min(Count, Quizzes.Num());

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

	RecalcWallSpeed();
	CountdownTimer = CountdownSeconds;
	SetState(EAiQuizState::Countdown);

	UE_LOG(LogAiQuiz, Display, TEXT("StartRound target=%d firstSpeed=%.2f"), TargetCount, ActiveWallSpeed);
}

void AAiQuizGameModeBase::UpdatePlaying(float Dt)
{
	// Treadmill: world scrolls toward player; player world Z advances equally.
	WorldScrollZ += ActiveWallSpeed * Dt;
	PlayerWorldZ += ActiveWallSpeed * Dt;

	// Lateral movement (clamped to safe rail range)
	PlayerX = FMath::Clamp(PlayerX + InputAxisX * PlayerSpeed * Dt, MinX, MaxX);

	// Jump / gravity
	if (bJumpQueued && bOnFloor)
	{
		VelY = JumpForce;
		bOnFloor = false;
	}
	bJumpQueued = false;
	VelY -= Gravity * Dt;
	PlayerY += VelY * Dt;
	if (PlayerY <= 0.0f)
	{
		PlayerY = 0.0f;
		VelY = 0.0f;
		bOnFloor = true;
	}

	// Wall collision / door judgement (world coords, like game_state.gd)
	if (Quizzes.IsValidIndex(CurrentWallIndex))
	{
		const float WallZ = GetWallWorldZ(CurrentWallIndex);
		if (PlayerWorldZ >= WallZ - HitOffsetZ)
		{
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
	else
	{
		DoGameOver();
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

void AAiQuizGameModeBase::DoGameOver()
{
	UE_LOG(LogAiQuiz, Display, TEXT("GameOver at wall=%d score=%d"), CurrentWallIndex, Score);
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

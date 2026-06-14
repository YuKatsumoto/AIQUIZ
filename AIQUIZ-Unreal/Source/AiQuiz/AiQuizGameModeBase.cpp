#include "AiQuizGameModeBase.h"
#include "AiQuizPawn.h"
#include "AiQuizWorld.h"
#include "AiQuizHUD.h"
#include "Engine/DataTable.h"
#include "Engine/World.h"
#include "UObject/ConstructorHelpers.h"

DEFINE_LOG_CATEGORY_STATIC(LogAiQuiz, Log, All);

AAiQuizGameModeBase::AAiQuizGameModeBase()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;
	DefaultPawnClass = AAiQuizPawn::StaticClass();
	HUDClass = AAiQuizHUD::StaticClass();   // Phase 7: Canvas-driven menu / HUD / result
}

void AAiQuizGameModeBase::BeginPlay()
{
	Super::BeginPlay();
	ResolveQuizBank();

	// Phase 6: spawn the visual world manager (wall pool). Spawning here avoids having
	// to hand-place the director in L_Game.umap (binary uasset).
	if (UWorld* W = GetWorld())
	{
		FActorSpawnParameters Params;
		Params.Owner = this;
		Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		WallDirector = W->SpawnActor<AAiQuizWorld>(AAiQuizWorld::StaticClass(), FTransform::Identity, Params);
	}

	if (bAutoStartInPIE)
	{
		// Debug free-run: enter gameplay immediately (count=0 -> empty list -> no walls).
		const TArray<FQuizItem> Empty;
		StartRoundWithQuizzes(Empty, DebugAutoStartCount);
		UE_LOG(LogAiQuiz, Display, TEXT("Auto-start (PIE): free-run round, count=%d"), DebugAutoStartCount);
	}
	else
	{
		// Phase 7: start at the menu; the HUD + Pawn drive StartRoundFromMenu.
		SetState(EAiQuizState::Menu);
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

int32 AAiQuizGameModeBase::GetCountdownDisplay() const
{
	const int32 N = FMath::CeilToInt(CountdownTimer);
	return (N > 0) ? N : 0;
}

FQuizItem AAiQuizGameModeBase::GetCurrentQuiz() const
{
	if (Quizzes.IsValidIndex(CurrentWallIndex))
	{
		return Quizzes[CurrentWallIndex];
	}
	return FQuizItem();
}

int32 AAiQuizGameModeBase::GetNumChoices() const
{
	if (Quizzes.IsValidIndex(CurrentWallIndex))
	{
		return (Quizzes[CurrentWallIndex].NumChoices == 2) ? 2 : 4;
	}
	return 2;
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
	OnStateChanged.Broadcast(NewState);
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
		// Hard keeps the DataTable's 4 choices (NumChoices already 4); CheckPlayerDoor /
		// the wall treat NumChoices as a binary 2-or-4 selector.
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
	VelZ = 0.0f;
	WorldScrollZ = 0.0f;
	CurrentWallIndex = 0;
	Score = 0;
	bOnFloor = true;
	InputAxisX = 0.0f;
	bJumpQueued = false;
	LastOverReason = EAiQuizOverReason::None;

	CorrectFlash = 0.0f;
	WrongFlash = 0.0f;
	CameraShake = 0.0f;
	GameOverTimer = 0.0f;
	PlayTime = 0.0f;
	MaxStreak = 0;
	CurrentStreak = 0;
	TotalAnswered = 0;

	RecalcWallSpeed();
	CountdownTimer = CountdownSeconds;
	SetState(EAiQuizState::Countdown);
	OnQuizLoaded.Broadcast(CurrentWallIndex);
}

void AAiQuizGameModeBase::StartRound(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count)
{
	LoadQuizzes(Subject, Grade, Difficulty, Count);
	TargetCount = FMath::Min(Count, Quizzes.Num());
	ResetRoundState();

	UE_LOG(LogAiQuiz, Display, TEXT("StartRound target=%d firstSpeed=%.2f"), TargetCount, ActiveWallSpeed);
}

void AAiQuizGameModeBase::StartRoundFromMenu()
{
	const TArray<FString> Subjects = GetAvailableSubjects();
	if (Subjects.Num() == 0)
	{
		UE_LOG(LogAiQuiz, Warning, TEXT("StartRoundFromMenu: no subjects in DataTable."));
		return;
	}
	const FString Subject = Subjects[FMath::Clamp(MenuSubjectIndex, 0, Subjects.Num() - 1)];

	const TArray<int32> Grades = GetAvailableGrades(Subject);
	const int32 Grade = Grades.IsValidIndex(MenuGradeIndex) ? Grades[MenuGradeIndex]
		: (Grades.Num() > 0 ? Grades[0] : 1);

	const EAiQuizDifficulty Diff = (EAiQuizDifficulty)FMath::Clamp(MenuDifficultyIndex, 0, 2);
	StartRound(Subject, Grade, Diff, 10);
}

void AAiQuizGameModeBase::StartRoundWithQuizzes(const TArray<FQuizItem>& InQuizzes, int32 Count)
{
	Quizzes = InQuizzes;
	TargetCount = FMath::Min(Count, Quizzes.Num());
	ResetRoundState();

	UE_LOG(LogAiQuiz, Display, TEXT("StartRoundWithQuizzes target=%d items=%d firstSpeed=%.2f"),
		TargetCount, Quizzes.Num(), ActiveWallSpeed);
}

void AAiQuizGameModeBase::ReturnToMenu()
{
	Quizzes.Reset();
	PlayerX = PlayerY = PlayerWorldZ = 0.0f;
	VelY = VelZ = 0.0f;
	WorldScrollZ = 0.0f;
	CurrentWallIndex = 0;
	Score = 0;
	CorrectFlash = WrongFlash = CameraShake = 0.0f;
	GameOverTimer = 0.0f;
	LastOverReason = EAiQuizOverReason::None;
	SetState(EAiQuizState::Menu);
}

TArray<FString> AAiQuizGameModeBase::GetAvailableSubjects() const
{
	TArray<FString> Subjects;
	UDataTable* DT = const_cast<AAiQuizGameModeBase*>(this)->ResolveQuizBank();
	if (!DT)
	{
		return Subjects;
	}
	// Collect distinct subjects in a deterministic order (sorted by smallest row name,
	// so the menu order is stable across runs despite the row map being unordered).
	TMap<FString, FName> FirstKey;
	for (const TPair<FName, uint8*>& Row : DT->GetRowMap())
	{
		const FQuizItem* Item = reinterpret_cast<const FQuizItem*>(Row.Value);
		if (!Item || Item->Subject.IsEmpty()) { continue; }
		FName* Existing = FirstKey.Find(Item->Subject);
		if (!Existing || Row.Key.LexicalLess(*Existing))
		{
			FirstKey.Add(Item->Subject, Row.Key);
		}
	}
	FirstKey.GetKeys(Subjects);
	Subjects.Sort([&FirstKey](const FString& A, const FString& B)
	{
		return FirstKey[A].LexicalLess(FirstKey[B]);
	});
	return Subjects;
}

TArray<int32> AAiQuizGameModeBase::GetAvailableGrades(const FString& Subject) const
{
	TArray<int32> Grades;
	UDataTable* DT = const_cast<AAiQuizGameModeBase*>(this)->ResolveQuizBank();
	if (!DT)
	{
		return Grades;
	}
	for (const TPair<FName, uint8*>& Row : DT->GetRowMap())
	{
		const FQuizItem* Item = reinterpret_cast<const FQuizItem*>(Row.Value);
		if (Item && Item->Subject == Subject)
		{
			Grades.AddUnique(Item->Grade);
		}
	}
	Grades.Sort();
	return Grades;
}

void AAiQuizGameModeBase::DecayFeedback(float Dt)
{
	// game_state.gd::update() top — flash/shake decay every frame regardless of state.
	CorrectFlash = FMath::Max(0.0f, CorrectFlash - Dt * 1.5f);
	WrongFlash   = FMath::Max(0.0f, WrongFlash   - Dt * 1.2f);
	CameraShake  = FMath::Max(0.0f, CameraShake  - Dt * 2.8f);
}

void AAiQuizGameModeBase::UpdateCountdown(float Dt)
{
	CountdownTimer -= Dt;
	if (CountdownTimer <= 0.0f)
	{
		SetState(EAiQuizState::Playing);
	}
}

void AAiQuizGameModeBase::UpdatePlaying(float Dt)
{
	PlayTime += Dt;

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
	TotalAnswered++;

	if (Door == Q.A)
	{
		// No-stop: stay in PLAYING and advance immediately (game_state.gd:1499-1505).
		Score++;
		CurrentStreak++;
		MaxStreak = FMath::Max(MaxStreak, CurrentStreak);
		CorrectFlash = 1.0f;
		CameraShake = 0.22f;
		OnCorrect.Broadcast(CurrentWallIndex, Q.A); // fire BEFORE the index advances (door break)
		AdvanceAfterCorrect();
	}
	else
	{
		// Wrong door / pillar -> game over with knockback (game_state.gd:1419-1450).
		CurrentStreak = 0;
		VelY = JumpForce * 0.8f;
		VelZ = -12.0f;
		DoGameOver((Door < 0) ? EAiQuizOverReason::Wall : EAiQuizOverReason::WrongDoor);
	}
}

void AAiQuizGameModeBase::AdvanceAfterCorrect()
{
	CurrentWallIndex++;
	UE_LOG(LogAiQuiz, Display, TEXT("Correct! score=%d nextWall=%d"), Score, CurrentWallIndex);
	if (CurrentWallIndex >= TargetCount || CurrentWallIndex >= Quizzes.Num())
	{
		CorrectFlash = 1.0f;
		SetState(EAiQuizState::Clear);
		OnCleared.Broadcast();
	}
	else
	{
		RecalcWallSpeed();        // stay in Playing
		OnQuizLoaded.Broadcast(CurrentWallIndex);
	}
}

void AAiQuizGameModeBase::DoGameOver(EAiQuizOverReason Reason)
{
	LastOverReason = Reason;
	WrongFlash = 1.0f;
	CameraShake = 0.35f;
	GameOverTimer = 0.001f;     // game_state.gd starts the explosion/death timer here
	UE_LOG(LogAiQuiz, Display, TEXT("GameOver reason=%s wall=%d score=%d"),
		*UEnum::GetValueAsString(Reason), CurrentWallIndex, Score);
	SetState(EAiQuizState::GameOver);
	OnWrong.Broadcast(Reason);
}

void AAiQuizGameModeBase::ProcessDeadPhysics(float Dt)
{
	// game_state.gd::_process_dead_player_physics (1P) — the body keeps flying for 2.5s.
	if (GameOverTimer > 0.0f && GameOverTimer < 2.5f)
	{
		VelY -= Gravity * Dt;
		PlayerY += VelY * Dt;
		VelZ = FMath::FInterpConstantTo(VelZ, 0.0f, Dt, 15.0f); // move_toward(vel_z, 0, dt*15)
		PlayerWorldZ += VelZ * Dt;

		const float LocalZ = PlayerWorldZ - WorldScrollZ;
		const bool bOver = (LocalZ >= FloorBackZ) && (FMath::Abs(PlayerX) <= FloorHalfWidth);
		const float LimitY = bOver ? 0.0f : MagmaDeathY;
		if (PlayerY <= LimitY && VelY < 0.0f)
		{
			PlayerY = LimitY;
			VelY = 0.0f;
			if (bOver) { VelZ = 0.0f; }
		}
	}
}

void AAiQuizGameModeBase::UpdateGameOver(float Dt)
{
	GameOverTimer += Dt;
	ProcessDeadPhysics(Dt);
}

void AAiQuizGameModeBase::TestStep(float Dt)
{
	DecayFeedback(Dt);
	switch (State)
	{
	case EAiQuizState::Countdown: UpdateCountdown(Dt); break;
	case EAiQuizState::Playing:   UpdatePlaying(Dt);   break;
	case EAiQuizState::GameOver:  UpdateGameOver(Dt);  break;
	default: break;
	}
}

void AAiQuizGameModeBase::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	DecayFeedback(DeltaSeconds);
	switch (State)
	{
	case EAiQuizState::Countdown: UpdateCountdown(DeltaSeconds); break;
	case EAiQuizState::Playing:   UpdatePlaying(DeltaSeconds);   break;
	case EAiQuizState::GameOver:  UpdateGameOver(DeltaSeconds);  break;
	default: break;
	}
}

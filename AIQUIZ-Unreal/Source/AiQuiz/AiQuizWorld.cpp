#include "AiQuizWorld.h"
#include "AiQuizWall.h"
#include "AiQuizGameModeBase.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"

TArray<int32> AAiQuizWorld::ComputeNeededIndices(int32 CurrentWallIndex, int32 TargetCount,
	float WorldScrollZ, float WallStartZ, float WallSpacing, float FloorBackZ, int32 MaxVisibleWalls)
{
	TArray<int32> Needed;
	const int32 StartIdx = FMath::Max(0, CurrentWallIndex - 3);
	const int32 MaxWallIdx = TargetCount - 1; // fixed-count (10Q) slice: walls 0..target-1
	for (int32 i = 0; i < MaxVisibleWalls + 3; ++i)
	{
		const int32 Idx = StartIdx + i;
		if (MaxWallIdx >= 0 && Idx > MaxWallIdx) { continue; }
		const float LocalZ = (WallStartZ + (float)Idx * WallSpacing) - WorldScrollZ;
		if (LocalZ > FloorBackZ) { Needed.Add(Idx); }
	}
	return Needed;
}

AAiQuizWorld::AAiQuizWorld()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;
	// Tick after the GameMode so we read freshly-updated WorldScrollZ in the same frame.
	PrimaryActorTick.TickGroup = TG_PostUpdateWork;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
}

void AAiQuizWorld::BeginPlay()
{
	Super::BeginPlay();
	ResolveGM();
}

AAiQuizGameModeBase* AAiQuizWorld::ResolveGM()
{
	if (!GM)
	{
		GM = Cast<AAiQuizGameModeBase>(UGameplayStatics::GetGameMode(this));
	}
	if (GM && !bBound)
	{
		GM->OnCorrect.AddDynamic(this, &AAiQuizWorld::HandleCorrect);
		GM->OnStateChanged.AddDynamic(this, &AAiQuizWorld::HandleStateChanged);
		bBound = true;
	}
	return GM;
}

void AAiQuizWorld::HandleCorrect(int32 WallIndex, int32 AnswerIndex)
{
	if (AAiQuizWall* Wall = FindWall(WallIndex))
	{
		Wall->BreakDoor(AnswerIndex);
	}
}

void AAiQuizWorld::HandleStateChanged(EAiQuizState NewState)
{
	if (NewState == EAiQuizState::Menu || NewState == EAiQuizState::Clear)
	{
		ClearAllWalls();
	}
}

AAiQuizWall* AAiQuizWorld::FindWall(int32 Index) const
{
	for (AAiQuizWall* W : ActiveWalls)
	{
		if (W && W->WallIndex == Index) { return W; }
	}
	return nullptr;
}

void AAiQuizWorld::ClearAllWalls()
{
	for (AAiQuizWall* W : ActiveWalls)
	{
		if (W) { W->Destroy(); }
	}
	ActiveWalls.Reset();
}

void AAiQuizWorld::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (!ResolveGM()) { return; }
	UpdateWalls();
}

void AAiQuizWorld::UpdateWalls()
{
	// game_world.gd::_update_walls — states with no walls (slice subset: MENU / CLEAR).
	if (GM->State == EAiQuizState::Menu || GM->State == EAiQuizState::Clear)
	{
		ClearAllWalls();
		return;
	}

	const float FloorBackZ = GM->FloorBackZ;
	const TArray<int32> Needed = ComputeNeededIndices(GM->CurrentWallIndex, GM->TargetCount,
		GM->WorldScrollZ, GM->WallStartZ, GM->WallSpacing, FloorBackZ, MaxVisibleWalls);

	// Remove walls no longer needed (shatter if they were culled out the back).
	TArray<AAiQuizWall*> ToRemove;
	for (AAiQuizWall* W : ActiveWalls)
	{
		if (!W || !Needed.Contains(W->WallIndex)) { ToRemove.Add(W); }
	}
	for (AAiQuizWall* W : ToRemove)
	{
		ActiveWalls.Remove(W);
		if (W)
		{
			if (GM->GetWallLocalZ(W->WallIndex) <= FloorBackZ + 0.1f)
			{
				W->ShatterWall();
			}
			W->Destroy();
		}
	}

	// Add missing walls.
	for (int32 Idx : Needed)
	{
		if (FindWall(Idx)) { continue; }
		const FVector Loc(GM->GetWallLocalZ(Idx) * 100.f, 0.f, 0.f);
		FActorSpawnParameters Params;
		Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		AAiQuizWall* Wall = GetWorld()->SpawnActor<AAiQuizWall>(AAiQuizWall::StaticClass(), FTransform(Loc), Params);
		if (Wall)
		{
			Wall->WallIndex = Idx;
			ActiveWalls.Add(Wall);
		}
	}

	// Reposition every active wall on the treadmill + label the wall being approached.
	const FQuizItem Current = GM->GetCurrentQuiz();
	const int32 NumChoices = GM->GetNumChoices();
	for (AAiQuizWall* W : ActiveWalls)
	{
		if (!W) { continue; }
		W->SetActorLocation(FVector(GM->GetWallLocalZ(W->WallIndex) * 100.f, 0.f, 0.f));
		if (W->WallIndex == GM->CurrentWallIndex && Current.C.Num() > 0)
		{
			W->SetQuiz(Current, NumChoices);
		}
	}
}

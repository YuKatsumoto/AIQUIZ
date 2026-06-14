#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "AiQuizTypes.h"
#include "AiQuizWorld.generated.h"

class AAiQuizGameModeBase;
class AAiQuizWall;

/**
 * Visual world manager (Phase 6) — the wall pool. Faithful port of the wall half of
 * Godot scripts/world/game_world.gd (_update_walls): pools up to MAX_VISIBLE_WALLS(+buffer)
 * AAiQuizWall actors, repositions them every tick on the treadmill, shatters/destroys
 * them once they fall behind FLOOR_BACK_Z, labels the wall the player is approaching,
 * and bursts the correct door when the GameMode fires OnCorrect.
 *
 * Spawned by AAiQuizGameModeBase::BeginPlay (so L_Game.umap needs no hand placement).
 */
UCLASS()
class AIQUIZ_API AAiQuizWorld : public AActor
{
	GENERATED_BODY()

public:
	AAiQuizWorld();

	virtual void Tick(float DeltaSeconds) override;
	virtual void BeginPlay() override;

	UPROPERTY(EditDefaultsOnly, Category = "AiQuiz") int32 MaxVisibleWalls = 4;

	/** Pure port of the index half of game_world.gd::_update_walls — which wall indices
	 *  should currently exist. Static so it is unit-testable without a world. */
	static TArray<int32> ComputeNeededIndices(int32 CurrentWallIndex, int32 TargetCount,
		float WorldScrollZ, float WallStartZ, float WallSpacing, float FloorBackZ, int32 MaxVisibleWalls);

protected:
	AAiQuizGameModeBase* ResolveGM();
	void UpdateWalls();
	void ClearAllWalls();
	AAiQuizWall* FindWall(int32 Index) const;

	UFUNCTION() void HandleCorrect(int32 WallIndex, int32 AnswerIndex);
	UFUNCTION() void HandleStateChanged(EAiQuizState NewState);

private:
	UPROPERTY(Transient) TObjectPtr<AAiQuizGameModeBase> GM = nullptr;
	UPROPERTY(Transient) TArray<TObjectPtr<AAiQuizWall>> ActiveWalls;
	bool bBound = false;
};

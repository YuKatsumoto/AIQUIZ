#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "QuizItem.h"
#include "AiQuizWall.generated.h"

class UStaticMesh;
class UStaticMeshComponent;
class UTextRenderComponent;
class UMaterialInterface;
class UMaterialInstanceDynamic;
class UFont;

/**
 * One quiz wall (Phase 6). Faithful port of Godot scripts/world/quiz_wall.gd:
 * beams/pillars (gray) procedurally framed around the doors, colored door panels,
 * NotoSansJP TextRender labels, correct-answer door burst (BreakDoor) and back
 * collapse (ShatterWall). Built entirely in C++ so it needs no hand-authored uasset.
 *
 * Coordinate map (UU=100, Godot X->UE -Y lateral, Godot Y->UE Z up, Godot Z->UE X depth),
 * identical to AAiQuizPawn. The wall actor's root is placed by AAiQuizWorld at
 * UE (X = 100*localZ, Y=0, Z=0); all child parts are built in Godot-local meters.
 */
UCLASS()
class AIQUIZ_API AAiQuizWall : public AActor
{
	GENERATED_BODY()

public:
	AAiQuizWall();

	/** Wall index in the run (mirrors Godot wall meta "wall_index"). */
	UPROPERTY(BlueprintReadOnly, Category = "AiQuiz") int32 WallIndex = -1;

	/** Build/relabel doors for this quiz (rebuilds the frame only when the door count changes). */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void SetQuiz(const FQuizItem& Quiz, int32 NumChoices);

	/** Blank all door labels. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void ClearLabels();

	/** Correct answer: hide a door panel and burst it into debris (quiz_wall.gd::break_door). */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void BreakDoor(int32 DoorIndex);

	/** Back-cull collapse: hide all parts and scatter a little debris (quiz_wall.gd::shatter_wall). */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void ShatterWall();

	// --- Godot(meters) -> UE(uu) helpers (public so AAiQuizWorld/tests can reuse) ---
	static FVector GodotToUE(float Gx, float Gy, float Gz) { return FVector(Gz * 100.f, -Gx * 100.f, Gy * 100.f); }
	/** Cube (1m) scale for a Godot box whose size is (lateral X, up Y, depth Z) meters. */
	static FVector GodotBoxScale(float SizeX, float SizeY, float SizeZ) { return FVector(SizeZ, SizeX, SizeY); }

protected:
	virtual void BeginPlay() override;

	void BuildFrame(int32 NumChoices);
	void BuildDoors(int32 NumChoices);
	UStaticMeshComponent* MakeBox(const FVector& GodotCenter, const FVector& GodotSize, const FLinearColor& Color);
	void SpawnDebris(const FVector& WorldCenter, const FVector& GodotSize, const FLinearColor& Color, int32 ChunksX, int32 ChunksY);
	UMaterialInstanceDynamic* MakeColorMID(const FLinearColor& Color);

private:
	UPROPERTY(Transient) TObjectPtr<UStaticMesh> CubeMesh = nullptr;
	UPROPERTY(Transient) TObjectPtr<UMaterialInterface> BaseMaterial = nullptr;
	UPROPERTY(Transient) TObjectPtr<UFont> LabelFont = nullptr;

	UPROPERTY(Transient) TObjectPtr<USceneComponent> Root = nullptr;
	UPROPERTY(Transient) TArray<TObjectPtr<UStaticMeshComponent>> FrameParts;
	UPROPERTY(Transient) TArray<TObjectPtr<UStaticMeshComponent>> Doors;
	UPROPERTY(Transient) TArray<TObjectPtr<UTextRenderComponent>> Labels;

	int32 CurrentNumChoices = -1;
};

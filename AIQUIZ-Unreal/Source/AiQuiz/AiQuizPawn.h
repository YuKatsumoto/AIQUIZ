#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "AiQuizTypes.h"
#include "AiQuizPawn.generated.h"

class UStaticMeshComponent;
class USkeletalMeshComponent;
class UCameraComponent;
class UAnimSequence;
class AAiQuizGameModeBase;

/**
 * Player avatar (Phase 4/5). Thin "input-push + visualizer":
 *  - each tick polls the keyboard exactly like Godot game_world.gd
 *    (Input.is_key_pressed), pushes it to AAiQuizGameModeBase::SetInput,
 *  - then reads the GameMode's authoritative state (PlayerX/PlayerY/State/VelY)
 *    and places itself on the treadmill + drives the FPS camera.
 * The GameMode owns ALL movement/physics; the Pawn never integrates motion.
 *
 * Coordinate map (UU=100, Godot Z->UE X forward, Godot X->UE Y lateral, Godot Y->UE Z up):
 *   UE_X = 100 * GetPlayerLocalZ()   (~0, fixed — the world scrolls toward the player)
 *   UE_Y = -100 * PlayerX            (NEGATIVE: reproduces Godot D/Right = axis.x -1)
 *   UE_Z = FloorTopZ + 100 * PlayerY (floor top at UE Z = -120; PlayerY is height >= 0)
 */
UCLASS()
class AIQUIZ_API AAiQuizPawn : public APawn
{
	GENERATED_BODY()

public:
	AAiQuizPawn();

	virtual void Tick(float DeltaSeconds) override;
	virtual void BeginPlay() override;

	// ---------- Components ----------
	UPROPERTY(VisibleAnywhere, Category = "AiQuiz") TObjectPtr<USceneComponent> Root;
	/** Placeholder box body (Phase 4). Hidden once the block-man is shown (Phase 5). */
	UPROPERTY(VisibleAnywhere, Category = "AiQuiz") TObjectPtr<UStaticMeshComponent> BodyBox;
	/** First-person camera (Godot FOV 44, eye 1.2 m). */
	UPROPERTY(VisibleAnywhere, Category = "AiQuiz") TObjectPtr<UCameraComponent> FpsCamera;
	/** Hidden Mixamo skeleton driving animation + bone sockets (Phase 5). */
	UPROPERTY(VisibleAnywhere, Category = "AiQuiz") TObjectPtr<USkeletalMeshComponent> AnimMesh;

	// ---------- Visual tuning (Godot camera_controller.gd) ----------
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Camera") float CameraFOV = 44.0f;
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Camera") float EyeHeightUU = 120.0f; // 1.2 m
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Camera") float BobAmpUU = 4.0f;      // 0.04 m
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Camera") float BobFreq = 1.2f;       // rad/s

	// ---------- Coordinate constants ----------
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Coords") float FloorTopZ = -120.0f;
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Coords") float UU = 100.0f;

	// ---------- Phase 5b: block-man (箱人間) ----------
	/** true = render the Godot-style colored box-man (skeleton hidden, just a pose source);
	 *  false = show the imported Mixamo mesh directly (Phase 5a). */
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Blockman") bool bUseBlockman = true;
	UPROPERTY(Transient) TArray<TObjectPtr<UStaticMeshComponent>> LimbBoxes;

	// ---------- Phase 5 animation assets (set in BP defaults or loaded by path) ----------
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Anim") TObjectPtr<UAnimSequence> AnimIdle;
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Anim") TObjectPtr<UAnimSequence> AnimRun;
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Anim") TObjectPtr<UAnimSequence> AnimJump;
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Anim") TObjectPtr<UAnimSequence> AnimFall;
	UPROPERTY(EditAnywhere, Category = "AiQuiz|Anim") TObjectPtr<UAnimSequence> AnimDrowning;

	// ---------- Pure helpers (also unit-tested headlessly) ----------
	/** World location for the pawn from GameMode state (meters in, UU out). */
	static FVector ComputePawnLocation(float PlayerLocalZ, float PlayerX, float PlayerY,
		float InFloorTopZ = -120.0f, float InUU = 100.0f)
	{
		return FVector(PlayerLocalZ * InUU, -InUU * PlayerX, InFloorTopZ + InUU * PlayerY);
	}

	/** Animation clip from gameplay state (mirrors animation_rig.gd:291-332). */
	static EAiQuizAnim SelectAnim(EAiQuizState State, float PlayerY, float VelY)
	{
		const float Air = 0.01f, Magma = -1.0f;
		const bool bActive = (State == EAiQuizState::Playing);
		if (PlayerY < Magma)                  return EAiQuizAnim::Drowning;
		if (PlayerY > Air && VelY > 0.0f)     return EAiQuizAnim::Jump;
		if (PlayerY > Air && VelY <= 0.0f)    return EAiQuizAnim::Fall;
		if (bActive)                          return EAiQuizAnim::Run;
		return EAiQuizAnim::Idle;
	}

protected:
	AAiQuizGameModeBase* ResolveGameMode();
	void GatherInputAndPush();
	void ApplyStateToActor(float Dt);
	void UpdateAnimation();
	void BuildBlockman();   // create the colored limb boxes (Phase 5b)
	void UpdateBlockman();  // place each box between its two bone sockets each tick

private:
	UPROPERTY(Transient) TObjectPtr<AAiQuizGameModeBase> GM = nullptr;
	float BobTime = 0.0f;
	EAiQuizAnim CurrentAnim = EAiQuizAnim::Idle;
	bool bAnimInited = false;
};

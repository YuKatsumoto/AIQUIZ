#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "AiQuizTypes.h"
#include "QuizItem.h"
#include "AiQuizGameModeBase.generated.h"

class UDataTable;

/**
 * Gameplay core for AIQUIZ (Hybrid: logic in C++, visuals/UI/content in Blueprint).
 * Faithful 1-player port of Godot game_state.gd. All distances are in METERS,
 * matching aiquiz_game_specification.md; the BP visual layer multiplies by 100 (UU).
 */
UCLASS()
class AIQUIZ_API AAiQuizGameModeBase : public AGameModeBase
{
	GENERATED_BODY()

public:
	AAiQuizGameModeBase();

	// ---------- Tuning (spec constants, meters) ----------
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float Gravity = 18.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float JumpForce = 7.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float PlayerSpeed = 7.6f;
	// Logical play range, used by camera/HUD hints. NOTE: not a hard clamp during
	// PLAYING — Godot deliberately lets the player run off the sides into the magma.
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float MinX = -6.5f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float MaxX = 6.5f;
	// Floor geometry (game_state.gd: FLOOR_HALF_WIDTH / FLOOR_BACK_Z, magma death at y < -8).
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float FloorHalfWidth = 12.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float FloorBackZ = -12.5f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float MagmaDeathY = -8.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float WallStartZ = 22.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float WallSpacing = 30.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float HitOffsetZ = 0.4f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float WallSpeedMin = 1.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float WallSpeedMax = 8.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float DefaultWallSpeed = 3.5f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float VisibleDistance = 28.0f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float MoveBuffer = 3.5f;
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float CountdownSeconds = 3.0f;

	// ---------- Data ----------
	/** Optional explicit DataTable; if null, loaded by path (/Game/AiQuiz/Data/DT_QuizBank). */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Data") TObjectPtr<UDataTable> QuizBank = nullptr;

	// ---------- Debug / Phase4-5 testing ----------
	/** If true, BeginPlay auto-starts a round so PIE enters gameplay (no menu yet).
	 *  Disable once the real WBP_MainMenu drives StartRound (Phase 7). */
	UPROPERTY(EditDefaultsOnly, BlueprintReadWrite, Category = "Debug") bool bAutoStartInPIE = true;
	/** Quizzes to auto-start with. 0 = free-run (no walls/collision) for movement+anim testing. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadWrite, Category = "Debug") int32 DebugAutoStartCount = 0;

	// ---------- Runtime state (read by BP visuals) ----------
	UPROPERTY(BlueprintReadOnly, Category = "State") EAiQuizState State = EAiQuizState::Menu;
	UPROPERTY(BlueprintReadOnly, Category = "State") float PlayerX = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float PlayerY = 0.0f;          // height above floor (>=0)
	UPROPERTY(BlueprintReadOnly, Category = "State") float PlayerWorldZ = 0.0f;     // advances with scroll
	UPROPERTY(BlueprintReadOnly, Category = "State") float VelY = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float WorldScrollZ = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 CurrentWallIndex = 0;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 Score = 0;
	UPROPERTY(BlueprintReadOnly, Category = "State") EAiQuizOverReason LastOverReason = EAiQuizOverReason::None;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 TargetCount = 10;
	UPROPERTY(BlueprintReadOnly, Category = "State") float ActiveWallSpeed = 3.5f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float CountdownTimer = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") bool bOnFloor = true;
	UPROPERTY(BlueprintReadOnly, Category = "State") TArray<FQuizItem> Quizzes;

	// ---------- Input (pushed by the Pawn each tick) ----------
	UPROPERTY(BlueprintReadWrite, Category = "Input") float InputAxisX = 0.0f;
	UPROPERTY(BlueprintReadWrite, Category = "Input") bool bJumpQueued = false;

	// ---------- API ----------
	/** Filter DT_QuizBank by subject+grade, take Count, reset and begin the round. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void StartRound(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count);

	/** Headless/deterministic entry point: begin a round from an explicit quiz list
	 *  (no DataTable, no shuffle). Used by automation tests and debug menus. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz|Test")
	void StartRoundWithQuizzes(const TArray<FQuizItem>& InQuizzes, int32 Count);

	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void SetInput(float AxisX, bool bJumpPressed);

	/** Test-only: advance the state machine by Dt without needing PIE. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz|Test")
	void TestStep(float Dt);

	/** World-space Z of wall i (meters). */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	float GetWallWorldZ(int32 Index) const;

	/** Player's fixed local Z (PlayerWorldZ - WorldScrollZ). */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	float GetPlayerLocalZ() const { return PlayerWorldZ - WorldScrollZ; }

	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	FQuizItem GetCurrentQuiz() const;

	/** Logical X center of a choice door (meters). choice 0..NumChoices-1. */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	float GetDoorCenterX(int32 NumChoices, int32 ChoiceIndex) const;

	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	float GetDoorHalfWidth(int32 NumChoices) const;

	virtual void Tick(float DeltaSeconds) override;
	virtual void BeginPlay() override;

protected:
	void SetState(EAiQuizState NewState);
	void ResetRoundState();
	void UpdatePlaying(float Dt);
	void ResolveCollision();
	/** Returns choice index the player X is within, or -1 if hitting a pillar. */
	int32 CheckPlayerDoor(float X, const FQuizItem& Q) const;
	void AdvanceAfterCorrect();
	void DoGameOver(EAiQuizOverReason Reason);
	void RecalcWallSpeed();
	void LoadQuizzes(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count);
	UDataTable* ResolveQuizBank();
};

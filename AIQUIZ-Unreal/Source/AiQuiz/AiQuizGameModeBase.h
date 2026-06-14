#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "AiQuizTypes.h"
#include "QuizItem.h"
#include "AiQuizGameModeBase.generated.h"

class UDataTable;
class AAiQuizWorld;

// ---- Event Dispatchers (Godot signals -> UE multicast delegates, plan §1.1) ----
// Bound by the HUD and the wall director; mirror game_state.gd's
// state_changed / quiz_loaded / correct_answer / wrong_answer / game_cleared.
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FAiQuizStateChanged, EAiQuizState, NewState);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FAiQuizQuizLoaded, int32, WallIndex);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FAiQuizCorrect, int32, WallIndex, int32, AnswerIndex);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FAiQuizWrong, EAiQuizOverReason, Reason);
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FAiQuizCleared);

/**
 * Gameplay core for AIQUIZ (Hybrid: logic in C++, visuals/UI/content procedural).
 * Faithful 1-player port of Godot game_state.gd. All distances are in METERS,
 * matching aiquiz_game_specification.md; the visual layer multiplies by 100 (UU).
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
	// 3-second 3-2-1 countdown (plan §Phase 7). GetCountdownDisplay() = ceil -> 3,2,1.
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Tuning") float CountdownSeconds = 3.0f;

	// ---------- Data ----------
	/** Optional explicit DataTable; if null, loaded by path (/Game/AiQuiz/Data/DT_QuizBank). */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Data") TObjectPtr<UDataTable> QuizBank = nullptr;

	// ---------- Debug / testing ----------
	/** If true, BeginPlay auto-starts a round (free-run for movement/anim testing) instead
	 *  of showing the menu. Phase 7 default is FALSE: the HUD menu drives StartRoundFromMenu. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadWrite, Category = "Debug") bool bAutoStartInPIE = false;
	/** Quizzes to auto-start with when bAutoStartInPIE. 0 = free-run (no walls/collision). */
	UPROPERTY(EditDefaultsOnly, BlueprintReadWrite, Category = "Debug") int32 DebugAutoStartCount = 0;

	// ---------- Runtime state (read by the visual layer) ----------
	UPROPERTY(BlueprintReadOnly, Category = "State") EAiQuizState State = EAiQuizState::Menu;
	UPROPERTY(BlueprintReadOnly, Category = "State") float PlayerX = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float PlayerY = 0.0f;          // height above floor (>=0)
	UPROPERTY(BlueprintReadOnly, Category = "State") float PlayerWorldZ = 0.0f;     // advances with scroll
	UPROPERTY(BlueprintReadOnly, Category = "State") float VelY = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float VelZ = 0.0f;             // death knockback (game_state.gd player_vel_z)
	UPROPERTY(BlueprintReadOnly, Category = "State") float WorldScrollZ = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 CurrentWallIndex = 0;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 Score = 0;
	UPROPERTY(BlueprintReadOnly, Category = "State") EAiQuizOverReason LastOverReason = EAiQuizOverReason::None;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 TargetCount = 10;
	UPROPERTY(BlueprintReadOnly, Category = "State") float ActiveWallSpeed = 3.5f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float CountdownTimer = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") bool bOnFloor = true;
	UPROPERTY(BlueprintReadOnly, Category = "State") TArray<FQuizItem> Quizzes;

	// HUD/camera feedback (game_state.gd correct_flash / wrong_flash / camera_shake / game_over_timer / play_time).
	UPROPERTY(BlueprintReadOnly, Category = "State") float CorrectFlash = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float WrongFlash = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float CameraShake = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") float GameOverTimer = 0.0f;   // ticks during GameOver/Clear
	UPROPERTY(BlueprintReadOnly, Category = "State") float PlayTime = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 MaxStreak = 0;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 CurrentStreak = 0;
	UPROPERTY(BlueprintReadOnly, Category = "State") int32 TotalAnswered = 0;

	// ---------- Menu selection (data-driven, no UI literals in C++) ----------
	UPROPERTY(BlueprintReadWrite, Category = "Menu") int32 MenuSubjectIndex = 0;
	UPROPERTY(BlueprintReadWrite, Category = "Menu") int32 MenuGradeIndex = 0;
	UPROPERTY(BlueprintReadWrite, Category = "Menu") int32 MenuDifficultyIndex = 0; // 0=Easy 1=Normal 2=Hard

	// ---------- Input (pushed by the Pawn each tick) ----------
	UPROPERTY(BlueprintReadWrite, Category = "Input") float InputAxisX = 0.0f;
	UPROPERTY(BlueprintReadWrite, Category = "Input") bool bJumpQueued = false;

	// ---------- Events (Event Dispatchers) ----------
	UPROPERTY(BlueprintAssignable, Category = "AiQuiz|Events") FAiQuizStateChanged OnStateChanged;
	UPROPERTY(BlueprintAssignable, Category = "AiQuiz|Events") FAiQuizQuizLoaded OnQuizLoaded;
	UPROPERTY(BlueprintAssignable, Category = "AiQuiz|Events") FAiQuizCorrect OnCorrect;
	UPROPERTY(BlueprintAssignable, Category = "AiQuiz|Events") FAiQuizWrong OnWrong;
	UPROPERTY(BlueprintAssignable, Category = "AiQuiz|Events") FAiQuizCleared OnCleared;

	// ---------- Round control ----------
	/** Filter DT_QuizBank by subject+grade, take Count, reset and begin the round. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void StartRound(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count);

	/** Begin a round from the current menu selection (subject/grade/difficulty), 10 questions. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void StartRoundFromMenu();

	/** Headless/deterministic entry point: begin a round from an explicit quiz list
	 *  (no DataTable, no shuffle). Used by automation tests and debug menus. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz|Test")
	void StartRoundWithQuizzes(const TArray<FQuizItem>& InQuizzes, int32 Count);

	/** Reset everything back to the menu (R-to-menu / game_state.gd reset_to_menu). */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void ReturnToMenu();

	UFUNCTION(BlueprintCallable, Category = "AiQuiz")
	void SetInput(float AxisX, bool bJumpPressed);

	/** Test-only: advance the state machine by Dt without needing PIE. */
	UFUNCTION(BlueprintCallable, Category = "AiQuiz|Test")
	void TestStep(float Dt);

	// ---------- Menu data (distinct values from DT_QuizBank — no UI literals) ----------
	UFUNCTION(BlueprintCallable, Category = "AiQuiz|Menu")
	TArray<FString> GetAvailableSubjects() const;

	UFUNCTION(BlueprintCallable, Category = "AiQuiz|Menu")
	TArray<int32> GetAvailableGrades(const FString& Subject) const;

	// ---------- Queries ----------
	/** World-space Z of wall i (meters). */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	float GetWallWorldZ(int32 Index) const;

	/** Wall i's fixed local Z (WallWorldZ - WorldScrollZ) — used for visual placement & culling. */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	float GetWallLocalZ(int32 Index) const { return GetWallWorldZ(Index) - WorldScrollZ; }

	/** Player's local Z (PlayerWorldZ - WorldScrollZ). */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	float GetPlayerLocalZ() const { return PlayerWorldZ - WorldScrollZ; }

	/** Countdown number to show on screen (3,2,1; 0 = blank). game_world.gd: int(ceil(timer)). */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	int32 GetCountdownDisplay() const;

	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	FQuizItem GetCurrentQuiz() const;

	/** Choices on the active wall (2 for Easy/Normal, 4 for Hard). */
	UFUNCTION(BlueprintPure, Category = "AiQuiz")
	int32 GetNumChoices() const;

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
	void DecayFeedback(float Dt);
	void UpdateCountdown(float Dt);
	void UpdatePlaying(float Dt);
	void UpdateGameOver(float Dt);
	void ProcessDeadPhysics(float Dt);
	void ResolveCollision();
	/** Returns choice index the player X is within, or -1 if hitting a pillar. */
	int32 CheckPlayerDoor(float X, const FQuizItem& Q) const;
	void AdvanceAfterCorrect();
	void DoGameOver(EAiQuizOverReason Reason);
	void RecalcWallSpeed();
	void LoadQuizzes(const FString& Subject, int32 Grade, EAiQuizDifficulty Difficulty, int32 Count);
	UDataTable* ResolveQuizBank();

private:
	/** Visual world manager (wall pool). Spawned in BeginPlay (no umap edit needed). */
	UPROPERTY(Transient) TObjectPtr<AAiQuizWorld> WallDirector = nullptr;
};

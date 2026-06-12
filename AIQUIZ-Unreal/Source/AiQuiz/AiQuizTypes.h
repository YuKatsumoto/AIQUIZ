#pragma once

#include "CoreMinimal.h"
#include "AiQuizTypes.generated.h"

/** Core gameplay state machine states (subset of Godot game_state.gd STATE_*). */
UENUM(BlueprintType)
enum class EAiQuizState : uint8
{
	Menu        UMETA(DisplayName = "Menu"),
	Preloading  UMETA(DisplayName = "Preloading"),
	Countdown   UMETA(DisplayName = "Countdown"),
	Playing     UMETA(DisplayName = "Playing"),
	GameOver    UMETA(DisplayName = "GameOver"),
	Clear       UMETA(DisplayName = "Clear")
};

UENUM(BlueprintType)
enum class EAiQuizMode : uint8
{
	TenQuestions UMETA(DisplayName = "TenQuestions"),
	Endless      UMETA(DisplayName = "Endless")
};

/** Difficulty as an enum so no non-ASCII literals are needed in C++.
 *  The Blueprint/menu layer maps 簡単/普通/難しい -> Easy/Normal/Hard. */
UENUM(BlueprintType)
enum class EAiQuizDifficulty : uint8
{
	Easy   UMETA(DisplayName = "Easy"),
	Normal UMETA(DisplayName = "Normal"),
	Hard   UMETA(DisplayName = "Hard")
};

/** Why the round ended in GameOver. The HUD/BP layer maps this to the
 *  Godot game-over messages (壁にぶつかった / 不正解 / マグマに落ちた) so no
 *  non-ASCII literals are needed in C++. */
UENUM(BlueprintType)
enum class EAiQuizOverReason : uint8
{
	None      UMETA(DisplayName = "None"),
	WrongDoor UMETA(DisplayName = "WrongDoor"),  // entered a door, but not the answer
	Wall      UMETA(DisplayName = "Wall"),       // missed every door / hit a pillar
	Magma     UMETA(DisplayName = "Magma")       // fell off the side of the floor
};

/** Avatar animation clip selected from the gameplay state. Mirrors the Godot
 *  player_controller.gd / animation_rig.gd ladder: chosen by PlayerY (height)
 *  and VelY (sign), NOT by horizontal speed. */
UENUM(BlueprintType)
enum class EAiQuizAnim : uint8
{
	Idle     UMETA(DisplayName = "Idle"),     // grounded, not in an active round
	Run      UMETA(DisplayName = "Run"),      // grounded, round active (Playing)
	Jump     UMETA(DisplayName = "Jump"),     // airborne, rising (VelY > 0)
	Fall     UMETA(DisplayName = "Fall"),     // airborne, descending (VelY <= 0)
	Drowning UMETA(DisplayName = "Drowning")  // fell into the magma (PlayerY < -1)
};

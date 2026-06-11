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

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "TestopiaMenuGameMode.generated.h"

/** メインメニュー用のゲームモード。ポーンは出さず、メニュー用のプレイヤーコントローラーだけを使う。 */
UCLASS()
class TESTOPIA_API ATestopiaMenuGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	ATestopiaMenuGameMode();
};

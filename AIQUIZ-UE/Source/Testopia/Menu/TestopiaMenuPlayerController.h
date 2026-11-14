#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "TestopiaMenuPlayerController.generated.h"

class UTestopiaMenuWidget;

/**
 * メインメニューのプレイヤーコントローラー。
 * レベルに置いた "MenuCamera" タグのカメラへ視点を固定し、メニューの UI を画面に出す。
 */
UCLASS()
class TESTOPIA_API ATestopiaMenuPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	ATestopiaMenuPlayerController();

	/** メニューのカメラに付けるアクタータグ。 */
	static const FName MenuCameraTag;

protected:
	virtual void BeginPlay() override;

private:
	UPROPERTY(Transient)
	TObjectPtr<UTestopiaMenuWidget> MenuWidget;
};

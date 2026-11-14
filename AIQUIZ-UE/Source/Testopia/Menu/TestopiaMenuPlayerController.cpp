#include "Menu/TestopiaMenuPlayerController.h"

#include "Blueprint/UserWidget.h"
#include "Kismet/GameplayStatics.h"
#include "Menu/TestopiaMenuWidget.h"

const FName ATestopiaMenuPlayerController::MenuCameraTag(TEXT("MenuCamera"));

ATestopiaMenuPlayerController::ATestopiaMenuPlayerController()
{
	// ポーンを持たないので、視点はレベルのカメラに自分で固定する。
	bAutoManageActiveCameraTarget = false;
	bShowMouseCursor = true;
	bEnableClickEvents = true;
	bEnableMouseOverEvents = true;
}

void ATestopiaMenuPlayerController::BeginPlay()
{
	Super::BeginPlay();

	if (!IsLocalController())
	{
		return;
	}

	TArray<AActor*> Cameras;
	UGameplayStatics::GetAllActorsWithTag(this, MenuCameraTag, Cameras);
	if (Cameras.Num() > 0)
	{
		SetViewTargetWithBlend(Cameras[0], 0.0f);
	}
	else
	{
		UE_LOG(LogTemp, Warning, TEXT("TestopiaMenu: '%s' タグのカメラがレベルにありません。"), *MenuCameraTag.ToString());
	}

	MenuWidget = CreateWidget<UTestopiaMenuWidget>(this, UTestopiaMenuWidget::StaticClass());
	if (MenuWidget)
	{
		MenuWidget->AddToViewport();
	}

	FInputModeGameAndUI InputMode;
	InputMode.SetHideCursorDuringCapture(false);
	InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
	SetInputMode(InputMode);
}

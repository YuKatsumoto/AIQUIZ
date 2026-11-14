#include "Menu/TestopiaMenuGameMode.h"

#include "Menu/TestopiaMenuPlayerController.h"

ATestopiaMenuGameMode::ATestopiaMenuGameMode()
{
	PlayerControllerClass = ATestopiaMenuPlayerController::StaticClass();
	DefaultPawnClass = nullptr;
	HUDClass = nullptr;
}

#include "Menu/TestopiaSpinner.h"

#include "Components/SceneComponent.h"

ATestopiaSpinner::ATestopiaSpinner()
{
	PrimaryActorTick.bCanEverTick = true;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
}

void ATestopiaSpinner::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	const float Step = DegreesPerSecond * DeltaSeconds;
	for (int32 Index = 0; Index < Targets.Num(); ++Index)
	{
		if (AActor* Target = Targets[Index])
		{
			const float Sign = (bAlternateDirection && (Index % 2 == 1)) ? -1.0f : 1.0f;
			Target->AddActorLocalRotation(FRotator(0.0f, Step * Sign, 0.0f));
		}
	}
}

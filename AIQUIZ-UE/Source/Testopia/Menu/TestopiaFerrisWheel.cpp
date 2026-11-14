#include "Menu/TestopiaFerrisWheel.h"

#include "Components/SceneComponent.h"

ATestopiaFerrisWheel::ATestopiaFerrisWheel()
{
	PrimaryActorTick.bCanEverTick = true;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
}

void ATestopiaFerrisWheel::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (!Rim || FMath::IsNearlyZero(PeriodSeconds))
	{
		return;
	}

	const FVector Axis = AxisWorld.GetSafeNormal();
	if (Axis.IsNearlyZero())
	{
		return;
	}

	const float Angle = (2.0f * UE_PI / PeriodSeconds) * DeltaSeconds;
	const FQuat Delta(Axis, Angle);
	const FVector Center = Rim->GetActorLocation();

	Rim->SetActorRotation(Delta * Rim->GetActorQuat());

	for (AActor* Gondola : Gondolas)
	{
		if (Gondola)
		{
			const FVector Offset = Gondola->GetActorLocation() - Center;
			Gondola->SetActorLocation(Center + Delta.RotateVector(Offset));
		}
	}
}

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "TestopiaSpinner.generated.h"

/**
 * 指定したアクターを、それぞれのローカル Z 軸まわりに回し続ける (のこぎりの刃など)。
 * 回すアクターとその子は Movable にしておくこと。
 */
UCLASS()
class TESTOPIA_API ATestopiaSpinner : public AActor
{
	GENERATED_BODY()

public:
	ATestopiaSpinner();

	virtual void Tick(float DeltaSeconds) override;

	UPROPERTY(EditAnywhere, Category = "Spinner")
	TArray<TObjectPtr<AActor>> Targets;

	/** 回る速さ (度/秒)。 */
	UPROPERTY(EditAnywhere, Category = "Spinner")
	float DegreesPerSecond = 540.0f;

	/** 隣どうしを逆向きに回す。 */
	UPROPERTY(EditAnywhere, Category = "Spinner")
	bool bAlternateDirection = true;
};

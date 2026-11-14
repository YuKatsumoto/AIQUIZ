#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "TestopiaFerrisWheel.generated.h"

/**
 * メニューの街の観覧車を回す (Godot 版 AiquizMenuStage._process の移植)。
 * 輪 (原点＝軸の中心) を軸まわりに回し、ゴンドラ (原点＝吊り点) は向きを変えずに位置だけ輪と同じだけ回す。
 */
UCLASS()
class TESTOPIA_API ATestopiaFerrisWheel : public AActor
{
	GENERATED_BODY()

public:
	ATestopiaFerrisWheel();

	virtual void Tick(float DeltaSeconds) override;

	/** 回る輪。原点が軸の中心にあること。 */
	UPROPERTY(EditAnywhere, Category = "Ferris Wheel")
	TObjectPtr<AActor> Rim;

	/** ゴンドラ。原点が吊り点にあること。 */
	UPROPERTY(EditAnywhere, Category = "Ferris Wheel")
	TArray<TObjectPtr<AActor>> Gondolas;

	/** 軸の向き (ワールド)。 */
	UPROPERTY(EditAnywhere, Category = "Ferris Wheel")
	FVector AxisWorld = FVector::ForwardVector;

	/** 1 周にかかる秒数。0 で止まる。負で逆回り。 */
	UPROPERTY(EditAnywhere, Category = "Ferris Wheel")
	float PeriodSeconds = 180.0f;
};

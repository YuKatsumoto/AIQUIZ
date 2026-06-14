#include "AiQuizWall.h"
#include "Components/StaticMeshComponent.h"
#include "Components/TextRenderComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/Font.h"
#include "Engine/World.h"
#include "TimerManager.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstanceDynamic.h"

namespace
{
	// quiz_wall.gd palette (sRGB-ish values applied as linear; close enough for the slice).
	static const FLinearColor WALL_COLOR(0.50f, 0.50f, 0.50f);
	static const FLinearColor DOOR_COLORS_2[2] = {
		FLinearColor(0.10f, 0.60f, 0.95f),  // 0 = left  (blue)
		FLinearColor(0.90f, 0.15f, 0.10f),  // 1 = right (red)
	};
	static const FLinearColor DOOR_COLORS_4[4] = {
		FLinearColor(0.10f, 0.55f, 0.95f),  // A blue
		FLinearColor(0.15f, 0.75f, 0.30f),  // B green
		FLinearColor(0.95f, 0.60f, 0.10f),  // C orange
		FLinearColor(0.90f, 0.15f, 0.15f),  // D red
	};
	// game_tuning.gd door positions / half-widths.
	static const float LEFT_DOOR_X = 3.5f;
	static const float RIGHT_DOOR_X = -3.5f;
	static const float DOOR4_XS[4] = { -5.8f, -1.95f, 1.95f, 5.8f };

	// Velocity helper: Godot (m/s) -> UE (cm/s) with the project's axis swap.
	static FVector GodotVel(float Gx, float Gy, float Gz) { return FVector(Gz * 100.f, -Gx * 100.f, Gy * 100.f); }
}

AAiQuizWall::AAiQuizWall()
{
	PrimaryActorTick.bCanEverTick = false;
	Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent = Root;
}

void AAiQuizWall::BeginPlay()
{
	Super::BeginPlay();
}

UMaterialInstanceDynamic* AAiQuizWall::MakeColorMID(const FLinearColor& Color)
{
	if (!BaseMaterial)
	{
		// Reuse the block-man base (has a "Color" vector param). Fallback: engine default.
		BaseMaterial = LoadObject<UMaterialInterface>(nullptr, TEXT("/Game/AiQuiz/Character/M_Blockman.M_Blockman"));
		if (!BaseMaterial)
		{
			BaseMaterial = LoadObject<UMaterialInterface>(nullptr, TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
		}
	}
	if (!BaseMaterial) { return nullptr; }
	UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(BaseMaterial, this);
	MID->SetVectorParameterValue(TEXT("Color"), Color);     // M_Blockman param
	MID->SetVectorParameterValue(TEXT("Color1"), Color);    // BasicShapeMaterial param (harmless if absent)
	return MID;
}

UStaticMeshComponent* AAiQuizWall::MakeBox(const FVector& GodotCenter, const FVector& GodotSize, const FLinearColor& Color)
{
	if (!CubeMesh)
	{
		CubeMesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
	}
	UStaticMeshComponent* Box = NewObject<UStaticMeshComponent>(this);
	Box->SetStaticMesh(CubeMesh);
	Box->SetCollisionEnabled(ECollisionEnabled::NoCollision); // collision is analytic in the GameMode
	if (UMaterialInstanceDynamic* MID = MakeColorMID(Color))
	{
		Box->SetMaterial(0, MID);
	}
	Box->SetupAttachment(Root);
	Box->RegisterComponent();
	Box->SetRelativeLocation(GodotToUE(GodotCenter.X, GodotCenter.Y, GodotCenter.Z));
	Box->SetRelativeScale3D(GodotBoxScale(GodotSize.X, GodotSize.Y, GodotSize.Z));
	return Box;
}

void AAiQuizWall::BuildFrame(int32 NumChoices)
{
	for (UStaticMeshComponent* P : FrameParts)
	{
		if (P) { P->DestroyComponent(); }
	}
	FrameParts.Reset();

	// Dimensions (quiz_wall.gd::_build_wall_around_doors).
	const float TotalWidth = 24.0f, MinX = -12.0f, MaxX = 12.0f;
	const float DoorTopY = 2.38f, DoorBottomY = -2.02f, WallTopY = 4.05f, WallBottomY = -3.15f;
	const float Depth = 1.1f; // 0.55 half -> 1.1 full

	// Top beam
	const float TopH = WallTopY - DoorTopY;
	FrameParts.Add(MakeBox(FVector(0.f, DoorTopY + TopH * 0.5f, 0.f), FVector(TotalWidth, TopH, Depth), WALL_COLOR));
	// Bottom beam
	const float BotH = DoorBottomY - WallBottomY;
	FrameParts.Add(MakeBox(FVector(0.f, WallBottomY + BotH * 0.5f, 0.f), FVector(TotalWidth, BotH, Depth), WALL_COLOR));

	// Pillars between doors
	const float PillarH = DoorTopY - DoorBottomY;
	const float PillarY = DoorBottomY + PillarH * 0.5f;

	TArray<float> DoorXs;
	float HalfW;
	if (NumChoices == 4)
	{
		DoorXs = { DOOR4_XS[0], DOOR4_XS[1], DOOR4_XS[2], DOOR4_XS[3] }; // already ascending
		HalfW = 1.45f;
	}
	else
	{
		DoorXs = { RIGHT_DOOR_X, LEFT_DOOR_X }; // sorted ascending (-3.5, 3.5)
		HalfW = 1.8f;
	}

	float CurX = MinX;
	for (float Dx : DoorXs)
	{
		const float DoorLeft = Dx - HalfW;
		const float PillarW = DoorLeft - CurX;
		if (PillarW > 0.f)
		{
			FrameParts.Add(MakeBox(FVector(CurX + PillarW * 0.5f, PillarY, 0.f), FVector(PillarW, PillarH, Depth), WALL_COLOR));
		}
		CurX = Dx + HalfW;
	}
	const float FinalW = MaxX - CurX;
	if (FinalW > 0.f)
	{
		FrameParts.Add(MakeBox(FVector(CurX + FinalW * 0.5f, PillarY, 0.f), FVector(FinalW, PillarH, Depth), WALL_COLOR));
	}
}

void AAiQuizWall::BuildDoors(int32 NumChoices)
{
	BuildFrame(NumChoices);

	for (UStaticMeshComponent* D : Doors) { if (D) { D->DestroyComponent(); } }
	for (UTextRenderComponent* L : Labels) { if (L) { L->DestroyComponent(); } }
	Doors.Reset();
	Labels.Reset();

	if (!LabelFont)
	{
		LabelFont = LoadObject<UFont>(nullptr, TEXT("/Game/AiQuiz/UI/F_NotoSansJP.F_NotoSansJP"));
	}

	auto MakeLabel = [&](float Gx, float Gy, float WorldSize) -> UTextRenderComponent*
	{
		UTextRenderComponent* T = NewObject<UTextRenderComponent>(this);
		T->SetupAttachment(Root);
		T->RegisterComponent();
		// Front face of the door (toward the approaching player at -X). yaw 180 faces the text at -X.
		T->SetRelativeLocation(GodotToUE(Gx, Gy, -0.65f));
		T->SetRelativeRotation(FRotator(0.f, 180.f, 0.f));
		T->SetHorizontalAlignment(EHTA_Center);
		T->SetVerticalAlignment(EVRTA_TextCenter);
		T->SetTextRenderColor(FColor::White);
		T->SetWorldSize(WorldSize);
		if (LabelFont) { T->SetFont(LabelFont); }
		T->SetText(FText::GetEmpty());
		return T;
	};

	if (NumChoices == 4)
	{
		for (int32 i = 0; i < 4; ++i)
		{
			Doors.Add(MakeBox(FVector(DOOR4_XS[i], 0.18f, 0.f), FVector(2.9f, 4.4f, 1.2f), DOOR_COLORS_4[i]));
			Labels.Add(MakeLabel(DOOR4_XS[i], 0.18f, 22.f));
		}
	}
	else
	{
		Doors.Add(MakeBox(FVector(LEFT_DOOR_X, 0.18f, 0.f), FVector(3.6f, 4.4f, 1.2f), DOOR_COLORS_2[0]));   // 0 = left
		Labels.Add(MakeLabel(LEFT_DOOR_X, 0.18f, 30.f));
		Doors.Add(MakeBox(FVector(RIGHT_DOOR_X, 0.18f, 0.f), FVector(3.6f, 4.4f, 1.2f), DOOR_COLORS_2[1])); // 1 = right
		Labels.Add(MakeLabel(RIGHT_DOOR_X, 0.18f, 30.f));
	}
	CurrentNumChoices = NumChoices;
}

void AAiQuizWall::SetQuiz(const FQuizItem& Quiz, int32 NumChoices)
{
	const int32 N = (NumChoices == 2) ? 2 : 4;
	if (N != CurrentNumChoices)
	{
		BuildDoors(N);
	}

	if (Quiz.C.Num() == 0)
	{
		ClearLabels();
		return;
	}

	static const TCHAR* L4[4] = { TEXT("A"), TEXT("B"), TEXT("C"), TEXT("D") };
	if (N == 4)
	{
		for (int32 i = 0; i < 4 && i < Labels.Num(); ++i)
		{
			const FString Txt = (i < Quiz.C.Num()) ? FString::Printf(TEXT("%s. %s"), L4[i], *Quiz.C[i]) : FString();
			if (Labels[i]) { Labels[i]->SetText(FText::FromString(Txt)); }
		}
	}
	else
	{
		if (Labels.Num() >= 2)
		{
			if (Labels[0]) { Labels[0]->SetText(FText::FromString(Quiz.C.Num() > 0 ? Quiz.C[0] : FString())); }
			if (Labels[1]) { Labels[1]->SetText(FText::FromString(Quiz.C.Num() > 1 ? Quiz.C[1] : FString())); }
		}
	}
}

void AAiQuizWall::ClearLabels()
{
	for (UTextRenderComponent* L : Labels)
	{
		if (L) { L->SetText(FText::GetEmpty()); }
	}
}

void AAiQuizWall::SpawnDebris(const FVector& WorldCenter, const FVector& GodotSize, const FLinearColor& Color, int32 ChunksX, int32 ChunksY)
{
	UWorld* W = GetWorld();
	if (!W) { return; }
	if (!CubeMesh)
	{
		CubeMesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
	}

	// Hold the debris on a throwaway actor so it OUTLIVES this wall (the wall may be
	// destroyed the same frame on a back-cull / final clear). SetLifeSpan auto-cleans it.
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	AActor* Holder = W->SpawnActor<AActor>(AActor::StaticClass(), FTransform(WorldCenter), Params);
	if (!Holder) { return; }
	USceneComponent* HRoot = NewObject<USceneComponent>(Holder);
	Holder->SetRootComponent(HRoot);
	HRoot->RegisterComponent();

	const FVector ChunkM(GodotSize.X / ChunksX, GodotSize.Y / ChunksY, GodotSize.Z); // meters
	UMaterialInstanceDynamic* MID = MakeColorMID(Color);

	for (int32 cx = 0; cx < ChunksX; ++cx)
	{
		for (int32 cy = 0; cy < ChunksY; ++cy)
		{
			UStaticMeshComponent* Chunk = NewObject<UStaticMeshComponent>(Holder);
			Chunk->SetStaticMesh(CubeMesh);
			if (MID) { Chunk->SetMaterial(0, MID); }
			Chunk->SetupAttachment(HRoot);
			Chunk->RegisterComponent();
			Chunk->SetWorldScale3D(GodotBoxScale(ChunkM.X, ChunkM.Y, ChunkM.Z) * 0.85f);

			// Offset from the door center (Godot lateral X -> UE -Y, up Y -> UE Z).
			const float Ox = (cx - (ChunksX - 1) * 0.5f) * ChunkM.X;
			const float Oy = (cy - (ChunksY - 1) * 0.5f) * ChunkM.Y;
			Chunk->SetWorldLocation(WorldCenter + FVector(0.f, -Ox * 100.f, Oy * 100.f));

			// Physics: free-flying debris that ignores the pawn.
			Chunk->SetCollisionEnabled(ECollisionEnabled::PhysicsOnly);
			Chunk->SetCollisionObjectType(ECC_WorldDynamic);
			Chunk->SetCollisionResponseToAllChannels(ECR_Ignore);
			Chunk->SetCollisionResponseToChannel(ECC_WorldStatic, ECR_Block);
			Chunk->SetSimulatePhysics(true);
			Chunk->SetPhysicsLinearVelocity(GodotVel(
				FMath::FRandRange(-5.f, 5.f),
				FMath::FRandRange(1.5f, 6.5f),
				FMath::FRandRange(5.f, 15.f)));
			Chunk->SetPhysicsAngularVelocityInDegrees(FVector(
				FMath::FRandRange(-360.f, 360.f),
				FMath::FRandRange(-360.f, 360.f),
				FMath::FRandRange(-360.f, 360.f)));
		}
	}
	Holder->SetLifeSpan(1.6f); // quiz_wall.gd shrink+free ~1.5s
}

void AAiQuizWall::BreakDoor(int32 DoorIndex)
{
	if (!Doors.IsValidIndex(DoorIndex)) { return; }
	UStaticMeshComponent* Door = Doors[DoorIndex];
	if (!Door || !Door->IsVisible()) { return; }

	const FVector Center = Door->GetComponentLocation();
	const FLinearColor Color = (CurrentNumChoices == 4)
		? DOOR_COLORS_4[FMath::Clamp(DoorIndex, 0, 3)]
		: DOOR_COLORS_2[FMath::Clamp(DoorIndex, 0, 1)];
	const FVector DoorGodotSize = (CurrentNumChoices == 4) ? FVector(2.9f, 4.4f, 1.2f) : FVector(3.6f, 4.4f, 1.2f);

	Door->SetVisibility(false);
	if (Labels.IsValidIndex(DoorIndex) && Labels[DoorIndex]) { Labels[DoorIndex]->SetVisibility(false); }

	// quiz_wall.gd::break_door non-preview = 4x5 chunks (~20 bodies/door, capped by SetLifeSpan).
	SpawnDebris(Center, DoorGodotSize, Color, 4, 5);
}

void AAiQuizWall::ShatterWall()
{
	// Back-cull collapse (quiz_wall.gd::shatter_wall). The wall is behind the player, so keep it
	// bounded: scatter each still-visible door (2x2) backward, then hide every part (the director
	// destroys the actor next; the debris are independent throwaway actors that outlive it).
	for (int32 i = 0; i < Doors.Num(); ++i)
	{
		if (Doors[i] && Doors[i]->IsVisible())
		{
			const FLinearColor Color = (CurrentNumChoices == 4) ? DOOR_COLORS_4[FMath::Clamp(i, 0, 3)] : DOOR_COLORS_2[FMath::Clamp(i, 0, 1)];
			const FVector Sz = (CurrentNumChoices == 4) ? FVector(2.9f, 4.4f, 1.2f) : FVector(3.6f, 4.4f, 1.2f);
			SpawnDebris(Doors[i]->GetComponentLocation(), Sz, Color, 2, 2);
		}
	}
	for (UStaticMeshComponent* P : FrameParts) { if (P) { P->SetVisibility(false); } }
	for (UStaticMeshComponent* D : Doors) { if (D) { D->SetVisibility(false); } }
	for (UTextRenderComponent* L : Labels) { if (L) { L->SetVisibility(false); } }
}

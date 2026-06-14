#include "AiQuizPawn.h"
#include "AiQuizGameModeBase.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/PlayerController.h"
#include "Animation/AnimSequence.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Kismet/GameplayStatics.h"
#include "UObject/ConstructorHelpers.h"
#include "InputCoreTypes.h"
#include "Engine/World.h"

namespace
{
	// Block-man limb segments: a colored box spans bone A -> bone B (Mixamo bone names,
	// "mixamorig:" stripped on Interchange import). Thickness in UU; color 0=body 1=head 2=limb.
	struct FLimbSeg { const TCHAR* A; const TCHAR* B; float Th; int32 Col; };
	static const FLimbSeg GBlockmanSegs[] = {
		{ TEXT("Hips"),        TEXT("Spine1"),       34.f, 0 },
		{ TEXT("Spine1"),      TEXT("Neck"),         40.f, 0 },
		{ TEXT("Head"),        TEXT("HeadTop_End"),  26.f, 1 },
		{ TEXT("LeftArm"),     TEXT("LeftForeArm"),  15.f, 2 },
		{ TEXT("LeftForeArm"), TEXT("LeftHand"),     13.f, 2 },
		{ TEXT("RightArm"),    TEXT("RightForeArm"), 15.f, 2 },
		{ TEXT("RightForeArm"),TEXT("RightHand"),    13.f, 2 },
		{ TEXT("LeftUpLeg"),   TEXT("LeftLeg"),      21.f, 2 },
		{ TEXT("LeftLeg"),     TEXT("LeftFoot"),     17.f, 2 },
		{ TEXT("LeftFoot"),    TEXT("LeftToeBase"),  13.f, 2 },
		{ TEXT("RightUpLeg"),  TEXT("RightLeg"),     21.f, 2 },
		{ TEXT("RightLeg"),    TEXT("RightFoot"),    17.f, 2 },
		{ TEXT("RightFoot"),   TEXT("RightToeBase"), 13.f, 2 },
	};
	// P1 palette (player_controller.gd:8-10): body / head / limb.
	static const FLinearColor GBlockmanColors[3] = {
		FLinearColor(0.95f, 0.55f, 0.20f), // body
		FLinearColor(0.95f, 0.65f, 0.35f), // head
		FLinearColor(0.85f, 0.48f, 0.18f), // limb
	};
}

AAiQuizPawn::AAiQuizPawn()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bStartWithTickEnabled = true;
	// Tick after the GameMode so we read freshly-updated state in the same frame.
	PrimaryActorTick.TickGroup = TG_PostUpdateWork;

	Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent = Root;

	// --- Placeholder box body (Phase 4): 70 x 70 x 240 uu, standing on the floor ---
	BodyBox = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("BodyBox"));
	BodyBox->SetupAttachment(Root);
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (CubeMesh.Succeeded())
	{
		BodyBox->SetStaticMesh(CubeMesh.Object);
	}
	BodyBox->SetRelativeScale3D(FVector(0.7f, 0.7f, 2.4f));        // 70 x 70 x 240 uu
	BodyBox->SetRelativeLocation(FVector(0.0f, 0.0f, 120.0f));     // half-height up => feet at actor origin
	BodyBox->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	BodyBox->SetCastShadow(true);

	// --- Mixamo character (Phase 5): drives anim + bone sockets ---
	AnimMesh = CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("AnimMesh"));
	AnimMesh->SetupAttachment(Root);
	AnimMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	AnimMesh->SetVisibility(false);   // made visible in BeginPlay once a mesh loads
	// Mixamo imports facing -Y; yaw +90 turns it to face +X (gameplay forward). Feet at origin.
	AnimMesh->SetRelativeLocationAndRotation(FVector::ZeroVector, FRotator(0.0f, 90.0f, 0.0f));
	// Keep posing while hidden so GetSocketTransform stays valid for box transcription (Phase 5b).
	AnimMesh->VisibilityBasedAnimTickOption = EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones;

	// --- First-person camera (Godot FOV 44, eye 1.2 m) ---
	FpsCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FpsCamera"));
	FpsCamera->SetupAttachment(Root);
	FpsCamera->SetRelativeLocation(FVector(0.0f, 0.0f, EyeHeightUU));
	FpsCamera->SetFieldOfView(CameraFOV);
}

void AAiQuizPawn::BeginPlay()
{
	Super::BeginPlay();
	FpsCamera->SetFieldOfView(CameraFOV);
	GM = ResolveGameMode();

	// Phase 5: bind the imported Mixamo character + clips by path (if present).
	if (USkeletalMesh* SK = LoadObject<USkeletalMesh>(nullptr, TEXT("/Game/AiQuiz/Character/SK_YBot.SK_YBot")))
	{
		AnimMesh->SetSkeletalMeshAsset(SK);
		BodyBox->SetVisibility(false);   // hide the placeholder box once we have a character
		if (bUseBlockman)
		{
			AnimMesh->SetVisibility(false);  // skeleton is only a pose source for the boxes
			BuildBlockman();
		}
		else
		{
			AnimMesh->SetVisibility(true);   // Phase 5a: show the Mixamo mesh directly
		}
	}
	if (!AnimRun)      { AnimRun      = LoadObject<UAnimSequence>(nullptr, TEXT("/Game/AiQuiz/Character/A_Run.A_Run")); }
	if (!AnimJump)     { AnimJump     = LoadObject<UAnimSequence>(nullptr, TEXT("/Game/AiQuiz/Character/A_Jump.A_Jump")); }
	if (!AnimDrowning) { AnimDrowning = LoadObject<UAnimSequence>(nullptr, TEXT("/Game/AiQuiz/Character/A_Drown.A_Drown")); }
	if (!AnimFall)     { AnimFall     = AnimJump; }  // descending portion of the jump arc
	if (!AnimIdle)     { AnimIdle     = AnimRun;  }  // no dedicated idle clip yet; hold a run pose
}

void AAiQuizPawn::BuildBlockman()
{
	UStaticMesh* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
	UMaterialInterface* Base = LoadObject<UMaterialInterface>(nullptr, TEXT("/Game/AiQuiz/Character/M_Blockman.M_Blockman"));
	if (!Cube) { return; }

	// One MID per palette colour (reused across boxes of the same type).
	UMaterialInstanceDynamic* Mids[3] = { nullptr, nullptr, nullptr };
	if (Base)
	{
		for (int32 c = 0; c < 3; ++c)
		{
			Mids[c] = UMaterialInstanceDynamic::Create(Base, this);
			Mids[c]->SetVectorParameterValue(TEXT("Color"), GBlockmanColors[c]);
		}
	}

	const int32 N = UE_ARRAY_COUNT(GBlockmanSegs);
	LimbBoxes.Reserve(N);
	for (int32 i = 0; i < N; ++i)
	{
		UStaticMeshComponent* Box = NewObject<UStaticMeshComponent>(this);
		Box->SetStaticMesh(Cube);
		Box->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		if (Mids[GBlockmanSegs[i].Col]) { Box->SetMaterial(0, Mids[GBlockmanSegs[i].Col]); }
		Box->SetupAttachment(Root);
		Box->RegisterComponent();
		Box->SetAbsolute(true, true, true); // we drive world transform directly each tick
		LimbBoxes.Add(Box);
	}
}

void AAiQuizPawn::UpdateBlockman()
{
	if (bExploded || LimbBoxes.Num() == 0 || !AnimMesh) { return; }
	const int32 N = FMath::Min(LimbBoxes.Num(), (int32)UE_ARRAY_COUNT(GBlockmanSegs));
	for (int32 i = 0; i < N; ++i)
	{
		UStaticMeshComponent* Box = LimbBoxes[i];
		if (!Box) { continue; }
		const FVector A = AnimMesh->GetSocketLocation(FName(GBlockmanSegs[i].A));
		const FVector B = AnimMesh->GetSocketLocation(FName(GBlockmanSegs[i].B));
		const FVector Dir = B - A;
		const float Len = FMath::Max((float)Dir.Size(), 6.0f);
		const float Th = GBlockmanSegs[i].Th;
		Box->SetWorldLocationAndRotation((A + B) * 0.5f, Dir.Rotation()); // X axis spans the bone
		Box->SetWorldScale3D(FVector(Len / 100.0f, Th / 100.0f, Th / 100.0f));
	}
}

void AAiQuizPawn::BurstBlockman()
{
	UWorld* W = GetWorld();
	if (!W || LimbBoxes.Num() == 0) { return; }
	bExploded = true;

	UStaticMesh* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
	UMaterialInterface* Base = LoadObject<UMaterialInterface>(nullptr, TEXT("/Game/AiQuiz/Character/M_Blockman.M_Blockman"));
	UMaterialInstanceDynamic* Mids[3] = { nullptr, nullptr, nullptr };
	if (Base)
	{
		for (int32 c = 0; c < 3; ++c)
		{
			Mids[c] = UMaterialInstanceDynamic::Create(Base, this);
			Mids[c]->SetVectorParameterValue(TEXT("Color"), GBlockmanColors[c]);
		}
	}

	// Throwaway holder so the debris outlives the pawn's per-tick box updates (auto-cleaned).
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	AActor* Holder = W->SpawnActor<AActor>(AActor::StaticClass(), FTransform(GetActorLocation()), Params);
	if (!Holder) { return; }
	USceneComponent* HRoot = NewObject<USceneComponent>(Holder);
	Holder->SetRootComponent(HRoot);
	HRoot->RegisterComponent();

	const int32 N = FMath::Min(LimbBoxes.Num(), (int32)UE_ARRAY_COUNT(GBlockmanSegs));
	for (int32 i = 0; i < N; ++i)
	{
		UStaticMeshComponent* Src = LimbBoxes[i];
		if (!Src) { continue; }
		UStaticMeshComponent* Chunk = NewObject<UStaticMeshComponent>(Holder);
		Chunk->SetStaticMesh(Cube);
		if (Mids[GBlockmanSegs[i].Col]) { Chunk->SetMaterial(0, Mids[GBlockmanSegs[i].Col]); }
		Chunk->SetupAttachment(HRoot);
		Chunk->RegisterComponent();
		Chunk->SetWorldTransform(Src->GetComponentTransform()); // same shape/place as the limb box

		Chunk->SetCollisionEnabled(ECollisionEnabled::PhysicsOnly);
		Chunk->SetCollisionObjectType(ECC_WorldDynamic);
		Chunk->SetCollisionResponseToAllChannels(ECR_Ignore);
		Chunk->SetCollisionResponseToChannel(ECC_WorldStatic, ECR_Block);
		Chunk->SetSimulatePhysics(true);
		Chunk->SetPhysicsLinearVelocity(FVector(
			FMath::FRandRange(-600.f, 600.f),
			FMath::FRandRange(-600.f, 600.f),
			FMath::FRandRange(300.f, 950.f)));      // burst up + outward
		Chunk->SetPhysicsAngularVelocityInDegrees(FVector(
			FMath::FRandRange(-540.f, 540.f),
			FMath::FRandRange(-540.f, 540.f),
			FMath::FRandRange(-540.f, 540.f)));
		Src->SetVisibility(false);
	}
	Holder->SetLifeSpan(2.5f);
}

AAiQuizGameModeBase* AAiQuizPawn::ResolveGameMode()
{
	return Cast<AAiQuizGameModeBase>(UGameplayStatics::GetGameMode(this));
}

void AAiQuizPawn::Tick(float Dt)
{
	Super::Tick(Dt);
	if (!GM)
	{
		GM = ResolveGameMode();
		if (!GM) { return; }
	}

	HandleMetaInput();        // Phase 7: menu navigation + R/Esc on the result screen
	GatherInputAndPush();     // BEFORE: feed input into the GameMode
	ApplyStateToActor(Dt);    // AFTER: read authoritative state -> place pawn + camera
	UpdateAnimation();        // Phase 5: switch clip from state (no-op until a mesh is set)
	if (bUseBlockman)
	{
		if (bExploded)
		{
			// New round -> rebuild the body (re-show the limb boxes).
			if (GM->State == EAiQuizState::Countdown || GM->State == EAiQuizState::Playing)
			{
				for (UStaticMeshComponent* B : LimbBoxes) { if (B) { B->SetVisibility(true); } }
				bExploded = false;
			}
		}
		else if (GM->State == EAiQuizState::GameOver && GM->GameOverTimer >= 2.0f)
		{
			BurstBlockman();   // Phase 9: explode ~2s into death (game_world.gd:514 timing)
		}
		UpdateBlockman();      // Phase 5b: place boxes on the (hidden) skeleton (no-op once exploded)
	}
}

void AAiQuizPawn::GatherInputAndPush()
{
	APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0);
	if (!PC) { return; }

	// 1:1 port of game_world.gd:118-123 / 147-152 (Input.is_key_pressed):
	//   D / Right  -> axis.x -= 1   A / Left -> axis.x += 1   (INVERTED vs physical key)
	float AxisX = 0.0f;
	if (PC->IsInputKeyDown(EKeys::D) || PC->IsInputKeyDown(EKeys::Right)) { AxisX -= 1.0f; }
	if (PC->IsInputKeyDown(EKeys::A) || PC->IsInputKeyDown(EKeys::Left))  { AxisX += 1.0f; }
	const bool bJump = PC->WasInputKeyJustPressed(EKeys::SpaceBar);

	// No extra negation: the GameMode does PlayerX += AxisX * Speed * dt, identical to Godot.
	GM->SetInput(AxisX, bJump);
}

void AAiQuizPawn::HandleMetaInput()
{
	APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0);
	if (!PC) { return; }

	if (GM->State == EAiQuizState::Menu)
	{
		// Subject (A/D or Left/Right), grade (W/S or Up/Down), difficulty (Q/E).
		const TArray<FString> Subjects = GM->GetAvailableSubjects();
		const int32 NumSubjects = FMath::Max(1, Subjects.Num());
		auto Cycle = [](int32 Cur, int32 Delta, int32 Num) { return ((Cur + Delta) % Num + Num) % Num; };

		if (PC->WasInputKeyJustPressed(EKeys::D) || PC->WasInputKeyJustPressed(EKeys::Right))
		{
			GM->MenuSubjectIndex = Cycle(GM->MenuSubjectIndex, +1, NumSubjects); GM->MenuGradeIndex = 0;
		}
		if (PC->WasInputKeyJustPressed(EKeys::A) || PC->WasInputKeyJustPressed(EKeys::Left))
		{
			GM->MenuSubjectIndex = Cycle(GM->MenuSubjectIndex, -1, NumSubjects); GM->MenuGradeIndex = 0;
		}

		const FString CurSubject = Subjects.IsValidIndex(GM->MenuSubjectIndex) ? Subjects[GM->MenuSubjectIndex] : FString();
		const int32 NumGrades = FMath::Max(1, GM->GetAvailableGrades(CurSubject).Num());
		if (PC->WasInputKeyJustPressed(EKeys::W) || PC->WasInputKeyJustPressed(EKeys::Up))
		{
			GM->MenuGradeIndex = Cycle(GM->MenuGradeIndex, +1, NumGrades);
		}
		if (PC->WasInputKeyJustPressed(EKeys::S) || PC->WasInputKeyJustPressed(EKeys::Down))
		{
			GM->MenuGradeIndex = Cycle(GM->MenuGradeIndex, -1, NumGrades);
		}

		if (PC->WasInputKeyJustPressed(EKeys::E)) { GM->MenuDifficultyIndex = Cycle(GM->MenuDifficultyIndex, +1, 3); }
		if (PC->WasInputKeyJustPressed(EKeys::Q)) { GM->MenuDifficultyIndex = Cycle(GM->MenuDifficultyIndex, -1, 3); }

		if (PC->WasInputKeyJustPressed(EKeys::Enter) || PC->WasInputKeyJustPressed(EKeys::SpaceBar))
		{
			GM->StartRoundFromMenu();
		}
	}
	else if (GM->State == EAiQuizState::GameOver || GM->State == EAiQuizState::Clear)
	{
		// R = retry (same selection); Esc = back to menu (game_world.gd R-to-menu / Esc).
		if (PC->WasInputKeyJustPressed(EKeys::R)) { GM->StartRoundFromMenu(); }
		if (PC->WasInputKeyJustPressed(EKeys::Escape)) { GM->ReturnToMenu(); }
	}
}

void AAiQuizPawn::ApplyStateToActor(float Dt)
{
	// Treadmill placement (see header). UE_X fixed (~0), UE_Y = -100*PlayerX, UE_Z = floor + 100*PlayerY.
	const FVector Loc = ComputePawnLocation(GM->GetPlayerLocalZ(), GM->PlayerX, GM->PlayerY, FloorTopZ, UU);
	SetActorLocation(Loc);

	BobTime += Dt;
	const float Bob = FMath::Sin(BobTime * BobFreq) * BobAmpUU;

	if (GM->State == EAiQuizState::GameOver)
	{
		// Game-over dolly + decaying shake (camera_controller.gd 1P branch lines 113-130):
		// the camera eases back behind the player (forward = +X, so "back" = -X) and rises.
		const float GoT = GM->GameOverTimer;
		const float TVal = FMath::Min(1.0f, GoT * 0.5f);
		const float Ease = 1.0f - FMath::Pow(1.0f - TVal, 3.0f);
		const float DistUU = Ease * 8.0f * UU;
		const float DecayShake = FMath::Max(0.0f, 1.0f - GoT * 0.8f) * 1.5f;
		const float SX = FMath::FRandRange(-0.5f, 0.5f) * DecayShake * UU;
		const float SY = FMath::FRandRange(-0.5f, 0.5f) * DecayShake * UU;
		const float SZ = FMath::FRandRange(-0.5f, 0.5f) * DecayShake * UU;

		const FVector Eye = Loc + FVector(-DistUU + SX, SY, EyeHeightUU + Ease * 4.0f * UU + Bob + SZ);
		const FVector Target = Loc + FVector(0.0f, SX * 0.5f, EyeHeightUU * 0.5f + SY * 0.5f);
		FpsCamera->SetWorldLocation(Eye);
		FpsCamera->SetWorldRotation((Target - Eye).Rotation());
		return;
	}

	// Normal FPS: head-bob on the camera (Godot: eye.y += sin(_time*1.2)*0.04). Up axis = UE Z.
	FpsCamera->SetRelativeRotation(FRotator::ZeroRotator);
	FpsCamera->SetRelativeLocation(FVector(0.0f, 0.0f, EyeHeightUU + Bob));
}

void AAiQuizPawn::UpdateAnimation()
{
	// Phase 5: drive the (hidden) skeleton from the gameplay state, no AnimBP needed.
	if (!AnimMesh || !AnimMesh->GetSkeletalMeshAsset())
	{
		return; // no mesh yet (Phase 4) -> nothing to animate
	}

	const EAiQuizAnim Desired = SelectAnim(GM->State, GM->PlayerY, GM->VelY);

	// Run playback rate scales with belt speed every tick (player_controller.gd:622-628).
	if (Desired == EAiQuizAnim::Run)
	{
		AnimMesh->SetPlayRate(FMath::Clamp(GM->ActiveWallSpeed / 3.5f, 0.5f, 2.5f));
	}

	if (bAnimInited && Desired == CurrentAnim)
	{
		return; // already playing the right clip; don't restart it every tick
	}
	CurrentAnim = Desired;
	bAnimInited = true;

	UAnimSequence* Clip = nullptr;
	bool bLoop = true;
	switch (Desired)
	{
	case EAiQuizAnim::Run:      Clip = AnimRun;      bLoop = true;  break;
	case EAiQuizAnim::Jump:     Clip = AnimJump;     bLoop = false; break;
	case EAiQuizAnim::Fall:     Clip = AnimFall ? AnimFall : AnimJump; bLoop = false; break;
	case EAiQuizAnim::Drowning: Clip = AnimDrowning; bLoop = true;  break;
	case EAiQuizAnim::Idle:
	default:                    Clip = AnimIdle;     bLoop = true;  break;
	}
	if (Clip)
	{
		AnimMesh->PlayAnimation(Clip, bLoop);
		if (Desired != EAiQuizAnim::Run) { AnimMesh->SetPlayRate(1.0f); }
	}
}

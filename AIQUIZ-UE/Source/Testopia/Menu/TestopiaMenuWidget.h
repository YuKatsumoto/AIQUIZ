#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "TestopiaMenuWidget.generated.h"

class UBorder;
class UButton;
class UCanvasPanel;
class UTextBlock;

/**
 * メインメニューの UI (Godot 版 main_menu の移植の第一歩)。
 * ウィジェットブループリントを使わず、ツリーを C++ で組み立てる。
 * 基準の画面は 1920x1080。
 */
UCLASS()
class TESTOPIA_API UTestopiaMenuWidget : public UUserWidget
{
	GENERATED_BODY()

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	void BuildTree();
	/** Anchor は画面のどの角を基準にするか ((0,0) = 左上、(1,1) = 右下)。 */
	UButton* AddModeButton(UCanvasPanel* Canvas, const FName& Name, const FText& Label, const FVector2D& Position, const FVector2D& Size, float FontSize, const FVector2D& Anchor = FVector2D::ZeroVector);
	UBorder* AddStepChip(class UHorizontalBox* Row, const FName& Name, const FText& Label);
	void SelectMode(int32 ModeIndex);
	void RefreshSelection();

	UFUNCTION()
	void HandleTenQuestions();

	UFUNCTION()
	void HandleEndless();

	UFUNCTION()
	void HandleTutorial();

	UFUNCTION()
	void HandleOnline();

	UFUNCTION()
	void HandleSettings();

	UPROPERTY(Transient)
	TArray<TObjectPtr<UButton>> ModeButtons;

	UPROPERTY(Transient)
	TArray<TObjectPtr<UBorder>> StepChips;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> HintText;

	TArray<FText> ModeLabels;
	int32 SelectedMode = INDEX_NONE;
};

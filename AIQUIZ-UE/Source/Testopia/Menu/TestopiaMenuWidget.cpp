#include "Menu/TestopiaMenuWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "Components/BackgroundBlur.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Image.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/TextBlock.h"
#include "Engine/Texture2D.h"
#include "Fonts/CompositeFont.h"
#include "Misc/Paths.h"
#include "Styling/SlateTypes.h"

#define LOCTEXT_NAMESPACE "TestopiaMenu"

namespace TestopiaMenuStyle
{
	// Godot 版メニューの配色。
	static FLinearColor Srgb(uint8 R, uint8 G, uint8 B, uint8 A = 255)
	{
		return FLinearColor::FromSRGBColor(FColor(R, G, B, A));
	}

	static const FLinearColor ButtonNormal = Srgb(30, 36, 50, 176);
	static const FLinearColor ButtonHover = Srgb(52, 64, 88, 208);
	static const FLinearColor ButtonPressed = Srgb(24, 28, 38, 224);
	static const FLinearColor ButtonOutline = Srgb(255, 255, 255, 56);
	static const FLinearColor Accent = Srgb(255, 210, 63);
	static const FLinearColor ChipActive = Srgb(46, 107, 214, 245);
	static const FLinearColor ChipIdle = Srgb(24, 32, 62, 235);
	static const FLinearColor ChipOutline = Srgb(86, 112, 190, 255);
	static const FLinearColor Shadow = FLinearColor(0.0f, 0.02f, 0.06f, 0.65f);
	static const FLinearColor LogoShadow = Srgb(13, 22, 48, 235);

	static const float ButtonRadius = 12.0f;
	static const float ButtonBlur = 14.0f;
	static const float ShadowPad = 30.0f;

	static UTexture2D* UiTexture(const TCHAR* Path)
	{
		return LoadObject<UTexture2D>(nullptr, Path);
	}

	/** Slate のフォントサイズはポイント (96dpi 基準)。px から直す。 */
	static float Px(float Pixels)
	{
		return Pixels * 0.75f;
	}

	static TSharedPtr<const FCompositeFont> MakeFont(const TCHAR* File)
	{
		return MakeShared<FCompositeFont>(
			TEXT("Default"),
			FPaths::ProjectContentDir() / TEXT("Slate/Fonts") / File,
			EFontHinting::Default,
			EFontLoadingPolicy::LazyLoad);
	}

	static FSlateFontInfo Font(bool bBold, float Pixels)
	{
		// フォントファイルは Content/Slate/Fonts に置いたものを直接読む。
		static const TSharedPtr<const FCompositeFont> Bold = MakeFont(TEXT("NotoSansJP-Bold.ttf"));
		static const TSharedPtr<const FCompositeFont> Medium = MakeFont(TEXT("NotoSansJP-Medium.ttf"));
		return FSlateFontInfo(bBold ? Bold : Medium, Px(Pixels));
	}

	static FButtonStyle MakeButtonStyle(bool bSelected)
	{
		const FLinearColor Outline = bSelected ? Accent : ButtonOutline;
		const float Width = bSelected ? 3.0f : 1.0f;

		FButtonStyle Style;
		Style.SetNormal(FSlateRoundedBoxBrush(ButtonNormal, ButtonRadius, Outline, Width));
		Style.SetHovered(FSlateRoundedBoxBrush(ButtonHover, ButtonRadius, Accent, 3.0f));
		Style.SetPressed(FSlateRoundedBoxBrush(ButtonPressed, ButtonRadius, Accent, 3.0f));
		Style.SetNormalPadding(FMargin(0.0f));
		Style.SetPressedPadding(FMargin(0.0f, 2.0f, 0.0f, 0.0f));
		return Style;
	}
}

TSharedRef<SWidget> UTestopiaMenuWidget::RebuildWidget()
{
	if (WidgetTree && WidgetTree->RootWidget == nullptr)
	{
		BuildTree();
	}
	return Super::RebuildWidget();
}

void UTestopiaMenuWidget::BuildTree()
{
	using namespace TestopiaMenuStyle;

	UCanvasPanel* Canvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("Root"));
	WidgetTree->RootWidget = Canvas;

	// --- 左側をわずかに暗くして、明るい空や海の上でも文字を読みやすくする ---
	if (UTexture2D* Scrim = UiTexture(TEXT("/Game/UI/T_UI_ScrimLeft.T_UI_ScrimLeft")))
	{
		UImage* ScrimImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("ScrimLeft"));
		ScrimImage->SetBrushFromTexture(Scrim);
		ScrimImage->SetVisibility(ESlateVisibility::HitTestInvisible);
		UCanvasPanelSlot* ScrimSlot = Canvas->AddChildToCanvas(ScrimImage);
		ScrimSlot->SetAnchors(FAnchors(0.0f, 0.0f, 0.56f, 1.0f));
		ScrimSlot->SetOffsets(FMargin(0.0f));
	}

	// --- ロゴ (ぼかした影 → 厚みの影 → 本体の順に重ねる) ---
	if (UTexture2D* Logo = LoadObject<UTexture2D>(nullptr, TEXT("/Game/UI/Branding/T_TestopiaLogo.T_TestopiaLogo")))
	{
		const FVector2D LogoSize(540.0, 79.0);
		const FVector2D LogoPos(130.0, 92.0);

		if (UTexture2D* Soft = UiTexture(TEXT("/Game/UI/Branding/T_TestopiaLogoShadow.T_TestopiaLogoShadow")))
		{
			// 影の画像はロゴの外に余白を持つ (make_menu_textures.py の LOGO_SHADOW_PAD)。
			const double PadRatio = 48.0 / 1288.0;
			const FVector2D Pad(LogoSize.X * PadRatio, LogoSize.X * PadRatio);
			UImage* SoftImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("LogoSoftShadow"));
			SoftImage->SetBrushFromTexture(Soft);
			SoftImage->SetVisibility(ESlateVisibility::HitTestInvisible);
			UCanvasPanelSlot* SoftSlot = Canvas->AddChildToCanvas(SoftImage);
			SoftSlot->SetPosition(LogoPos - Pad + FVector2D(0.0, 10.0));
			SoftSlot->SetSize(LogoSize + Pad * 2.0);
		}

		UImage* LogoShadowImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("LogoShadow"));
		LogoShadowImage->SetBrushFromTexture(Logo);
		LogoShadowImage->SetColorAndOpacity(LogoShadow);
		UCanvasPanelSlot* ShadowSlot = Canvas->AddChildToCanvas(LogoShadowImage);
		ShadowSlot->SetPosition(LogoPos + FVector2D(3.0, 5.0));
		ShadowSlot->SetSize(LogoSize);

		UImage* LogoImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("Logo"));
		LogoImage->SetBrushFromTexture(Logo);
		UCanvasPanelSlot* LogoSlot = Canvas->AddChildToCanvas(LogoImage);
		LogoSlot->SetPosition(LogoPos);
		LogoSlot->SetSize(LogoSize);
	}
	else
	{
		UTextBlock* Title = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("TitleFallback"));
		Title->SetText(LOCTEXT("Title", "TESTOPIA"));
		Title->SetFont(Font(true, 84.0f));
		Title->SetShadowOffset(FVector2D(3.0, 4.0));
		Title->SetShadowColorAndOpacity(LogoShadow);
		UCanvasPanelSlot* TitleSlot = Canvas->AddChildToCanvas(Title);
		TitleSlot->SetPosition(FVector2D(130.0, 80.0));
		TitleSlot->SetAutoSize(true);
	}

	// --- 見出し ---
	{
		UTextBlock* Prompt = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Prompt"));
		Prompt->SetText(LOCTEXT("Prompt", "モードを選んでください"));
		Prompt->SetFont(Font(false, 28.0f));
		Prompt->SetShadowOffset(FVector2D(2.0, 2.0));
		Prompt->SetShadowColorAndOpacity(Shadow);
		UCanvasPanelSlot* PromptSlot = Canvas->AddChildToCanvas(Prompt);
		PromptSlot->SetPosition(FVector2D(134.0, 262.0));
		PromptSlot->SetAutoSize(true);
	}

	// --- モードのボタン (2 列 × 2 段) ---
	ModeLabels = {
		LOCTEXT("ModeTen", "10問チャレンジ"),
		LOCTEXT("ModeEndless", "エンドレス"),
		LOCTEXT("ModeTutorial", "チュートリアル"),
		LOCTEXT("ModeOnline", "オンライン対戦"),
	};

	const double ColX[2] = { 132.0, 542.0 };
	const FVector2D BigSize(390.0, 116.0);
	const FVector2D SmallSize(390.0, 78.0);
	const double Row1Y = 318.0;
	const double Row2Y = Row1Y + BigSize.Y + 20.0;

	ModeButtons.Reset();
	ModeButtons.Add(AddModeButton(Canvas, TEXT("BtnTen"), ModeLabels[0], FVector2D(ColX[0], Row1Y), BigSize, 36.0f));
	ModeButtons.Add(AddModeButton(Canvas, TEXT("BtnEndless"), ModeLabels[1], FVector2D(ColX[1], Row1Y), BigSize, 36.0f));
	ModeButtons.Add(AddModeButton(Canvas, TEXT("BtnTutorial"), ModeLabels[2], FVector2D(ColX[0], Row2Y), SmallSize, 28.0f));
	ModeButtons.Add(AddModeButton(Canvas, TEXT("BtnOnline"), ModeLabels[3], FVector2D(ColX[1], Row2Y), SmallSize, 28.0f));

	ModeButtons[0]->OnClicked.AddDynamic(this, &UTestopiaMenuWidget::HandleTenQuestions);
	ModeButtons[1]->OnClicked.AddDynamic(this, &UTestopiaMenuWidget::HandleEndless);
	ModeButtons[2]->OnClicked.AddDynamic(this, &UTestopiaMenuWidget::HandleTutorial);
	ModeButtons[3]->OnClicked.AddDynamic(this, &UTestopiaMenuWidget::HandleOnline);

	// --- 手順のチップ (1 モード / 2 設定 / 3 スタート) ---
	{
		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("StepRow"));
		UCanvasPanelSlot* RowSlot = Canvas->AddChildToCanvas(Row);
		RowSlot->SetPosition(FVector2D(132.0, Row2Y + SmallSize.Y + 22.0));
		RowSlot->SetAutoSize(true);

		StepChips.Reset();
		StepChips.Add(AddStepChip(Row, TEXT("Step1"), LOCTEXT("Step1", "1 モード")));
		StepChips.Add(AddStepChip(Row, TEXT("Step2"), LOCTEXT("Step2", "2 設定")));
		StepChips.Add(AddStepChip(Row, TEXT("Step3"), LOCTEXT("Step3", "3 スタート")));
	}

	// --- 選んだモードの表示 ---
	{
		HintText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Hint"));
		HintText->SetFont(Font(false, 22.0f));
		HintText->SetShadowOffset(FVector2D(2.0, 2.0));
		HintText->SetShadowColorAndOpacity(Shadow);
		UCanvasPanelSlot* HintSlot = Canvas->AddChildToCanvas(HintText);
		HintSlot->SetPosition(FVector2D(134.0, Row2Y + SmallSize.Y + 84.0));
		HintSlot->SetAutoSize(true);
	}

	// --- 右下：設定 / API状態 ---
	{
		UButton* Settings = AddModeButton(Canvas, TEXT("BtnSettings"), LOCTEXT("Settings", "設定 / API状態"), FVector2D(-26.0, -26.0), FVector2D(248.0, 60.0), 24.0f, FVector2D(1.0, 1.0));
		Settings->OnClicked.AddDynamic(this, &UTestopiaMenuWidget::HandleSettings);
	}

	// --- 左下：試作版の表示 ---
	{
		UTextBlock* Build = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("BuildLabel"));
		Build->SetText(LOCTEXT("BuildLabel", "Unreal Engine 5.8 試作版"));
		Build->SetFont(Font(false, 18.0f));
		Build->SetColorAndOpacity(FSlateColor(FLinearColor(1.0f, 1.0f, 1.0f, 0.75f)));
		Build->SetShadowOffset(FVector2D(1.0, 1.0));
		Build->SetShadowColorAndOpacity(Shadow);
		UCanvasPanelSlot* BuildSlot = Canvas->AddChildToCanvas(Build);
		BuildSlot->SetAnchors(FAnchors(0.0f, 1.0f));
		BuildSlot->SetAlignment(FVector2D(0.0, 1.0));
		BuildSlot->SetPosition(FVector2D(30.0, -26.0));
		BuildSlot->SetAutoSize(true);
	}

	RefreshSelection();
}

UButton* UTestopiaMenuWidget::AddModeButton(UCanvasPanel* Canvas, const FName& Name, const FText& Label, const FVector2D& Position, const FVector2D& Size, float FontSize, const FVector2D& Anchor)
{
	using namespace TestopiaMenuStyle;

	const FAnchors Anchors(Anchor.X, Anchor.Y);
	auto Place = [&](UWidget* Widget, const FVector2D& Pos, const FVector2D& WidgetSize)
	{
		UCanvasPanelSlot* PlacedSlot = Canvas->AddChildToCanvas(Widget);
		PlacedSlot->SetAnchors(Anchors);
		PlacedSlot->SetAlignment(Anchor);
		PlacedSlot->SetPosition(Pos);
		PlacedSlot->SetSize(WidgetSize);
	};

	// 落ち影 (9 スライスのぼかした角丸)。
	if (UTexture2D* ShadowTexture = UiTexture(TEXT("/Game/UI/T_UI_Shadow.T_UI_Shadow")))
	{
		FSlateBrush ShadowBrush;
		ShadowBrush.SetResourceObject(ShadowTexture);
		ShadowBrush.ImageSize = FVector2D(128.0, 128.0);
		ShadowBrush.DrawAs = ESlateBrushDrawType::Box;
		ShadowBrush.Margin = FMargin(0.375f);

		UImage* ShadowImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), FName(*(Name.ToString() + TEXT("_Shadow"))));
		ShadowImage->SetBrush(ShadowBrush);
		ShadowImage->SetVisibility(ESlateVisibility::HitTestInvisible);
		const FVector2D Pad(ShadowPad, ShadowPad);
		Place(ShadowImage, Position + (Anchor * 2.0 - FVector2D(1.0, 1.0)) * Pad + FVector2D(0.0, 8.0), Size + Pad * 2.0);
	}

	// すりガラス：後ろの景色をぼかす。
	UBackgroundBlur* Blur = WidgetTree->ConstructWidget<UBackgroundBlur>(UBackgroundBlur::StaticClass(), FName(*(Name.ToString() + TEXT("_Blur"))));
	Blur->SetBlurStrength(ButtonBlur);
	Blur->SetApplyAlphaToBlur(true);
	Blur->SetCornerRadius(FVector4(ButtonRadius, ButtonRadius, ButtonRadius, ButtonRadius));
	Blur->SetVisibility(ESlateVisibility::HitTestInvisible);
	Place(Blur, Position, Size);

	UButton* Button = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass(), Name);
	Button->SetStyle(MakeButtonStyle(false));
	Place(Button, Position, Size);

	UOverlay* Content = WidgetTree->ConstructWidget<UOverlay>(UOverlay::StaticClass(), FName(*(Name.ToString() + TEXT("_Content"))));
	if (UButtonSlot* ButtonSlot = Cast<UButtonSlot>(Button->AddChild(Content)))
	{
		ButtonSlot->SetHorizontalAlignment(HAlign_Fill);
		ButtonSlot->SetVerticalAlignment(VAlign_Fill);
		ButtonSlot->SetPadding(FMargin(0.0f));
	}

	// 左の丸い目印。
	UImage* Dot = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), FName(*(Name.ToString() + TEXT("_Dot"))));
	Dot->SetBrush(FSlateRoundedBoxBrush(Srgb(20, 22, 28), 7.0f, Srgb(176, 124, 38), 2.0f, FVector2f(14.0f, 14.0f)));
	if (UOverlaySlot* DotSlot = Content->AddChildToOverlay(Dot))
	{
		DotSlot->SetHorizontalAlignment(HAlign_Left);
		DotSlot->SetVerticalAlignment(VAlign_Center);
		DotSlot->SetPadding(FMargin(18.0f, 0.0f, 0.0f, 0.0f));
	}

	UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), FName(*(Name.ToString() + TEXT("_Text"))));
	Text->SetText(Label);
	Text->SetFont(Font(true, FontSize));
	Text->SetJustification(ETextJustify::Center);
	if (UOverlaySlot* TextSlot = Content->AddChildToOverlay(Text))
	{
		TextSlot->SetHorizontalAlignment(HAlign_Center);
		TextSlot->SetVerticalAlignment(VAlign_Center);
	}

	return Button;
}

UBorder* UTestopiaMenuWidget::AddStepChip(UHorizontalBox* Row, const FName& Name, const FText& Label)
{
	using namespace TestopiaMenuStyle;

	UBorder* Chip = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), Name);
	Chip->SetBrush(FSlateRoundedBoxBrush(ChipIdle, 18.0f, ChipOutline, 1.5f));
	Chip->SetPadding(FMargin(18.0f, 5.0f, 18.0f, 7.0f));

	UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), FName(*(Name.ToString() + TEXT("_Text"))));
	Text->SetText(Label);
	Text->SetFont(Font(true, 20.0f));
	Chip->SetContent(Text);

	if (UHorizontalBoxSlot* ChipSlot = Row->AddChildToHorizontalBox(Chip))
	{
		ChipSlot->SetPadding(FMargin(0.0f, 0.0f, 14.0f, 0.0f));
		ChipSlot->SetVerticalAlignment(VAlign_Center);
	}
	return Chip;
}

void UTestopiaMenuWidget::SelectMode(int32 ModeIndex)
{
	SelectedMode = ModeIndex;
	RefreshSelection();
}

void UTestopiaMenuWidget::RefreshSelection()
{
	using namespace TestopiaMenuStyle;

	for (int32 Index = 0; Index < ModeButtons.Num(); ++Index)
	{
		if (ModeButtons[Index])
		{
			ModeButtons[Index]->SetStyle(MakeButtonStyle(Index == SelectedMode));
		}
	}

	// モードを選ぶ前は「1 モード」、選んだ後は「2 設定」を強調する。
	const int32 ActiveStep = (SelectedMode == INDEX_NONE) ? 0 : 1;
	for (int32 Index = 0; Index < StepChips.Num(); ++Index)
	{
		if (StepChips[Index])
		{
			const bool bActive = (Index == ActiveStep);
			StepChips[Index]->SetBrush(FSlateRoundedBoxBrush(bActive ? ChipActive : ChipIdle, 18.0f, ChipOutline, 1.5f));
		}
	}

	if (HintText)
	{
		if (ModeLabels.IsValidIndex(SelectedMode))
		{
			HintText->SetText(FText::Format(
				LOCTEXT("HintSelected", "「{0}」を選択中（設定から先は未移植です）"), ModeLabels[SelectedMode]));
		}
		else
		{
			HintText->SetText(FText::GetEmpty());
		}
	}
}

void UTestopiaMenuWidget::HandleTenQuestions()
{
	SelectMode(0);
}

void UTestopiaMenuWidget::HandleEndless()
{
	SelectMode(1);
}

void UTestopiaMenuWidget::HandleTutorial()
{
	SelectMode(2);
}

void UTestopiaMenuWidget::HandleOnline()
{
	SelectMode(3);
}

void UTestopiaMenuWidget::HandleSettings()
{
	if (HintText)
	{
		HintText->SetText(LOCTEXT("HintSettings", "設定 / API状態 の画面は未移植です"));
	}
}

#undef LOCTEXT_NAMESPACE

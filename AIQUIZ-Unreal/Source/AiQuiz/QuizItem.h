#pragma once

#include "CoreMinimal.h"
#include "Engine/DataTable.h"
#include "QuizItem.generated.h"

/**
 * One quiz question row for the offline bank DataTable (DT_QuizBank).
 * Mirrors the AIQUIZ-Godot QuizItem fields (q / c / a / exp|e / t).
 * Pure data definition — all gameplay logic lives in Blueprints.
 */
USTRUCT(BlueprintType)
struct FQuizItem : public FTableRowBase
{
	GENERATED_BODY()

	/** 教科: 算数 / 理科 / 国語 / 社会 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	FString Subject;

	/** 学年 1-6 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	int32 Grade = 0;

	/** 問題文 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	FString Q;

	/** 選択肢 (2 or 4) */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	TArray<FString> C;

	/** 正解インデックス */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	int32 A = 0;

	/** 解説文 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	FString E;

	/** AI予測解答時間(秒)。動的壁速度の算出に使用 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	float T = 4.0f;

	/** 選択肢数 (2 or 4) */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Quiz")
	int32 NumChoices = 4;
};

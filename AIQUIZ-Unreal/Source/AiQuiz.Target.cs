using UnrealBuildTool;

public class AiQuizTarget : TargetRules
{
	public AiQuizTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.V6;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("AiQuiz");
	}
}

using UnrealBuildTool;

public class AiQuizEditorTarget : TargetRules
{
	public AiQuizEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V6;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("AiQuiz");
	}
}

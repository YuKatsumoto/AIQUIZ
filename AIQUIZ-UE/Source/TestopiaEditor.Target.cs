using UnrealBuildTool;
using System.Collections.Generic;

public class TestopiaEditorTarget : TargetRules
{
	public TestopiaEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V7;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_8;
		ExtraModuleNames.Add("Testopia");
	}
}

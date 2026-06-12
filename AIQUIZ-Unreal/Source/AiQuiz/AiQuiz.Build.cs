using UnrealBuildTool;

public class AiQuiz : ModuleRules
{
	public AiQuiz(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] {
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore"   // EKeys for direct key polling (faithful to Godot Input.is_key_pressed)
		});
	}
}

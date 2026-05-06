import sys

file_path = r'c:\AIQUIZ\AIQUIZ-Godot\ui\main_menu.tscn'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

changes = [
    (
'''[node name="CurrentSubjectLabel" type="Label" parent="VBoxContainer/ConfigContainer/SubjectCarousel"]
unique_name_in_owner = true
custom_minimum_size = Vector2(200, 44)
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "📐 算数"
horizontal_alignment = 1
vertical_alignment = 1''',
'''[node name="CurrentSubjectLabel" type="Button" parent="VBoxContainer/ConfigContainer/SubjectCarousel"]
unique_name_in_owner = true
custom_minimum_size = Vector2(200, 44)
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 22
text = " 算数"
expand_icon = true
flat = true'''
    ),
    (
'''[node name="CurrentGradeLabel" type="Label" parent="VBoxContainer/ConfigContainer/GradeCarousel"]
unique_name_in_owner = true
custom_minimum_size = Vector2(200, 44)
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "📚 3年生"
horizontal_alignment = 1
vertical_alignment = 1''',
'''[node name="CurrentGradeLabel" type="Button" parent="VBoxContainer/ConfigContainer/GradeCarousel"]
unique_name_in_owner = true
custom_minimum_size = Vector2(200, 44)
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 22
text = " 3年生"
expand_icon = true
flat = true'''
    ),
    (
'''[node name="CurrentDiffLabel" type="Label" parent="VBoxContainer/ConfigContainer/DiffCarousel"]
unique_name_in_owner = true
custom_minimum_size = Vector2(200, 44)
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "⚡ 普通"
horizontal_alignment = 1
vertical_alignment = 1''',
'''[node name="CurrentDiffLabel" type="Button" parent="VBoxContainer/ConfigContainer/DiffCarousel"]
unique_name_in_owner = true
custom_minimum_size = Vector2(200, 44)
layout_mode = 2
mouse_filter = 2
theme_override_font_sizes/font_size = 22
text = " 普通"
expand_icon = true
flat = true'''
    )
]

for t, r in changes:
    if t.replace('\n', '\r\n') in content:
        content = content.replace(t.replace('\n', '\r\n'), r.replace('\n', '\r\n'))
    elif t in content:
        content = content.replace(t, r)
    else:
        print(f'Failed to find:\\n{t}')
        sys.exit(1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Successfully updated main_menu.tscn')

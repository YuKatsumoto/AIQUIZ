extends RefCounted
class_name Constants

const SUBJECTS = ["算数", "理科", "国語", "社会", "英語"]
const SUBJECT_EN = {
	"算数": "Math",
	"理科": "Science",
	"国語": "Japanese",
	"社会": "Social Studies",
	"英語": "English",
}

const DEFAULT_SUBJECT_GRADES = [1, 2, 3, 4, 5, 6]
const SUBJECT_GRADE_OPTIONS = {
	"英語": [3, 4, 5, 6],
}


static func grades_for_subject(subject: String) -> Array[int]:
	var source: Array = SUBJECT_GRADE_OPTIONS.get(subject, DEFAULT_SUBJECT_GRADES)
	var grades: Array[int] = []
	for value: Variant in source:
		grades.append(int(value))
	return grades


static func is_grade_supported(subject: String, grade: int) -> bool:
	return grade in grades_for_subject(subject)


static func normalize_grade_for_subject(subject: String, grade: int) -> int:
	var grades := grades_for_subject(subject)
	if grades.is_empty():
		return clampi(grade, 1, 6)
	if grade in grades:
		return grade
	var closest: int = grades[0]
	for candidate: int in grades:
		if absi(candidate - grade) < absi(closest - grade):
			closest = candidate
	return closest


static func cycle_grade_for_subject(subject: String, grade: int, delta: int) -> int:
	var grades := grades_for_subject(subject)
	if grades.is_empty():
		return clampi(grade, 1, 6)
	var normalized := normalize_grade_for_subject(subject, grade)
	var index := grades.find(normalized)
	return grades[wrapi(index + delta, 0, grades.size())]

const DIFFICULTY_LEVELS = ["簡単", "普通", "難しい"]
const DIFFICULTY_EN = {"簡単": "Easy", "普通": "Normal", "難しい": "Hard"}

const MODE_TEN = "TEN_QUESTIONS"
const MODE_ENDLESS = "ENDLESS"
const MODE_COOP = "COOP"
const MODE_TUTORIAL = "TUTORIAL"

const STATE_MENU = "MENU"
const STATE_PRELOADING = "PRELOADING"
const STATE_WAITING_START = "WAITING_START"
const STATE_FLYOVER = "FLYOVER"
const STATE_COUNTDOWN = "COUNTDOWN"
const STATE_PLAYING = "PLAYING"
const STATE_CORRECT = "CORRECT"
const STATE_GAME_OVER = "GAME_OVER"
const STATE_CLEAR = "CLEAR"
const STATE_GOAL_RACE = "GOAL_RACE"
const STATE_RESULT_CEREMONY = "RESULT_CEREMONY"

const MENU_STEP_MODE = "MODE_SELECT"
const MENU_STEP_CONFIG = "CONFIG_SELECT"
const MENU_STEP_SETTINGS = "SETTINGS"

const CONFIG_STEP_SUBJECT = "SUBJECT_SELECT"
const CONFIG_STEP_GRADE = "GRADE_SELECT"
const CONFIG_STEP_DIFFICULTY = "DIFFICULTY_SELECT"
const CONFIG_STEP_SUMMARY = "CONFIG_SUMMARY"

class_name I18n
extends RefCounted
## UI strings. Keys are used as Label/Button text and translated by Godot's
## TranslationServer, so switching the locale updates the UI live.
## To add a language: add its locale to LANGUAGES and a column to every entry.
## After adding Chinese text, re-run tools/subset_fonts.py (the bundled CJK font
## only contains the characters used here).

const LANGUAGES := [
	["zh_CN", "简体中文"],
	["en", "English"],
]

const STRINGS := {
	"MENU_START": {"zh_CN": "开始游戏", "en": "Start Game"},
	"MENU_SETTINGS": {"zh_CN": "设置", "en": "Settings"},
	"SETTINGS_TITLE": {"zh_CN": "设  置", "en": "Settings"},
	"OPT_LANGUAGE": {"zh_CN": "语言", "en": "Language"},
	"OPT_BRIGHTNESS": {"zh_CN": "画面亮度", "en": "Brightness"},
	"OPT_QUALITY": {"zh_CN": "画面质量", "en": "Graphics"},
	"OPT_FULLSCREEN": {"zh_CN": "全屏显示", "en": "Fullscreen"},
	"OPT_VSYNC": {"zh_CN": "垂直同步", "en": "V-Sync"},
	"OPT_GRAIN": {"zh_CN": "胶片颗粒", "en": "Film Grain"},
	"OPT_SHAKE": {"zh_CN": "心跳震屏", "en": "Heartbeat Shake"},
	"OPT_MASTER": {"zh_CN": "主音量", "en": "Master Volume"},
	"OPT_MUSIC": {"zh_CN": "音乐", "en": "Music"},
	"OPT_SFX": {"zh_CN": "音效", "en": "Sound Effects"},
	"VAL_ON": {"zh_CN": "开", "en": "On"},
	"VAL_OFF": {"zh_CN": "关", "en": "Off"},
	"Q_LOW": {"zh_CN": "低", "en": "Low"},
	"Q_MEDIUM": {"zh_CN": "中", "en": "Medium"},
	"Q_HIGH": {"zh_CN": "高", "en": "High"},
	"Q_ULTRA": {"zh_CN": "极致", "en": "Ultra"},
	"BTN_BACK": {"zh_CN": "返回", "en": "Back"},
	"QUIT_PROMPT": {"zh_CN": "确定要离开吗？", "en": "Leave the corridor?"},
	"QUIT_LEAVE": {"zh_CN": "离开", "en": "Leave"},
	"QUIT_STAY": {"zh_CN": "留下", "en": "Stay"},
	"VERSION": {"zh_CN": "v0.1.0  原型", "en": "v0.1.0  Prototype"},
	"PRO_CHAPTER": {"zh_CN": "第一章", "en": "Chapter One"},
	"PRO_WIP": {"zh_CN": "—— 正在制作中 ——", "en": "— In Development —"},
	"PRO_PRESS": {"zh_CN": "按任意键返回", "en": "Press any key to return"},
}

static var _registered := false


static func register() -> void:
	if _registered:
		return
	_registered = true
	for lang: Array in LANGUAGES:
		var t := Translation.new()
		t.locale = lang[0]
		for key: String in STRINGS:
			t.add_message(key, STRINGS[key].get(lang[0], STRINGS[key]["en"]))
		TranslationServer.add_translation(t)


static func language_index(locale: String) -> int:
	for i in LANGUAGES.size():
		if LANGUAGES[i][0] == locale:
			return i
	return 0

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
	# ---- main menu
	"MENU_START": {"zh_CN": "开始游戏", "en": "Start Game"},
	"MENU_SETTINGS": {"zh_CN": "设置", "en": "Settings"},
	"TAGLINE": {"zh_CN": "钢琴师，你能活下来吗？", "en": "Pianist, can you survive?"},
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
	"OPT_MOUSE": {"zh_CN": "鼠标灵敏度", "en": "Mouse Sensitivity"},
	"OPT_SUBTITLES": {"zh_CN": "字幕", "en": "Subtitles"},
	"OPT_MIC": {"zh_CN": "麦克风判定", "en": "Microphone"},
	"OPT_MIC_SENS": {"zh_CN": "麦克风灵敏度", "en": "Mic Sensitivity"},
	"OPT_MIC_DEVICE": {"zh_CN": "麦克风设备", "en": "Mic Device"},
	"VAL_ON": {"zh_CN": "开", "en": "On"},
	"VAL_OFF": {"zh_CN": "关", "en": "Off"},
	"Q_LOW": {"zh_CN": "低", "en": "Low"},
	"Q_MEDIUM": {"zh_CN": "中", "en": "Medium"},
	"Q_HIGH": {"zh_CN": "高", "en": "High"},
	"Q_ULTRA": {"zh_CN": "极致", "en": "Ultra"},
	"BTN_BACK": {"zh_CN": "返回", "en": "Back"},
	"QUIT_PROMPT": {"zh_CN": "确定要离开吗？", "en": "Leave?"},
	"QUIT_LEAVE": {"zh_CN": "离开", "en": "Leave"},
	"QUIT_STAY": {"zh_CN": "留下", "en": "Stay"},
	"VERSION": {"zh_CN": "v0.1.0  样例", "en": "v0.1.0  Sample"},
	# ---- difficulty
	"DIFF_TITLE": {"zh_CN": "选 择 难 度", "en": "Choose Difficulty"},
	"DIFF_EASY": {"zh_CN": "简单", "en": "Easy"},
	"DIFF_NORMAL": {"zh_CN": "普通", "en": "Normal"},
	"DIFF_HARD": {"zh_CN": "困难", "en": "Hard"},
	"DIFF_NIGHTMARE": {"zh_CN": "噩梦", "en": "Nightmare"},
	"DIFF_EASY_D": {"zh_CN": "只有尖叫才会暴露。凶手盯着你时会有提示。", "en": "Only a scream gives you away. You are warned when he is watching."},
	"DIFF_NORMAL_D": {"zh_CN": "倒吸一口气也会暴露。没有任何提示。", "en": "Even a gasp gives you away. No warnings."},
	"DIFF_HARD_D": {"zh_CN": "小声惊呼、紧张的笑都算出声。他更多疑。", "en": "A whimper or a nervous laugh counts. He trusts you less."},
	"DIFF_NIGHTMARE_D": {"zh_CN": "一次失误就死。没有墨镜。也许不止一个人。", "en": "One mistake and you die. No sunglasses. Maybe not just one of them."},
	"DIFF_WIP": {"zh_CN": "开发中", "en": "In development"},
	"DIFF_WIP_MSG": {"zh_CN": "这个难度还在开发中", "en": "This difficulty is still in development"},
	# ---- microphone calibration
	"CAL_TITLE": {"zh_CN": "麦 克 风 校 准", "en": "Microphone Calibration"},
	"CAL_INTRO": {"zh_CN": "这个游戏会听你的声音。\n被画面吓到时，只要发出声音，伪装就会失败。", "en": "This game listens to you.\nIf a sight makes you make a sound, your act is over."},
	"CAL_QUIET": {"zh_CN": "请保持安静……", "en": "Stay quiet…"},
	"CAL_SPEAK": {"zh_CN": "现在用正常音量说一句话，比如：“我什么都看不见。”", "en": "Now say something at a normal volume, like: “I can't see a thing.”"},
	"CAL_DONE": {"zh_CN": "校准完成", "en": "Calibrated"},
	"CAL_NO_MIC": {"zh_CN": "没有检测到麦克风的声音。", "en": "No sound from the microphone."},
	"CAL_BEGIN": {"zh_CN": "开始", "en": "Begin"},
	"CAL_RETRY": {"zh_CN": "重新校准", "en": "Recalibrate"},
	"CAL_SKIP": {"zh_CN": "不用麦克风", "en": "Play without mic"},
	"CAL_HEADPHONES": {"zh_CN": "请戴上耳机，否则游戏自己的声音会被麦克风收进去。", "en": "Wear headphones, or the game will hear itself."},
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

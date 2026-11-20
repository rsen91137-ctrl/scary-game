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
	"CAL_INTRO": {"zh_CN": "你是个哑巴。\n哑巴不会说话，但会倒吸一口气。\n今晚，这个游戏会一直听着你。", "en": "You are mute.\nThe mute can't speak — but they can still gasp.\nTonight, this game is listening."},
	"CAL_QUIET": {"zh_CN": "请保持安静……", "en": "Stay quiet…"},
	"CAL_SPEAK": {"zh_CN": "现在，倒吸一口气。\n就像你刚刚看见了什么。", "en": "Now gasp.\nAs if you had just seen something."},
	"CAL_DONE": {"zh_CN": "校准完成。整晚，都别出声。", "en": "Done. Not a sound, all night."},
	"CAL_NO_MIC": {"zh_CN": "没有检测到麦克风的声音。", "en": "No sound from the microphone."},
	"CAL_BEGIN": {"zh_CN": "开始", "en": "Begin"},
	"CAL_RETRY": {"zh_CN": "重新校准", "en": "Recalibrate"},
	"CAL_SKIP": {"zh_CN": "不用麦克风", "en": "Play without mic"},
	"CAL_HEADPHONES": {"zh_CN": "请戴上耳机，否则游戏自己的声音会被麦克风收进去。", "en": "Wear headphones, or the game will hear itself."},
	"CAL_LEVEL": {"zh_CN": "音量", "en": "Level"},
	# ---- the backstory, told over the eye before the night begins
	"STORY_1": {"zh_CN": "他生下来，就不会说话。", "en": "He was born unable to speak."},
	"STORY_2": {"zh_CN": "一个哑巴弹钢琴，没人愿意多看一眼。", "en": "Nobody looks twice at a mute pianist."},
	"STORY_3": {"zh_CN": "可一个瞎子弹钢琴，所有人都会心疼。", "en": "But everyone pities a blind one."},
	"STORY_4": {"zh_CN": "于是他戴上墨镜，拿起盲杖。从那天起，他是个盲人。", "en": "So he put on dark glasses and took up a white cane. From that day on, he was blind."},
	"STORY_5": {"zh_CN": "当盲人有很多好处。人们在他面前，从不遮掩。", "en": "Being blind has its perks. People hide nothing in front of you."},
	"STORY_6": {"zh_CN": "今晚的委托，他犹豫过。老楼，深夜，一个独居的女人。", "en": "He hesitated over tonight's job. An old block, late at night, a woman living alone."},
	"STORY_7": {"zh_CN": "可电话里，她的声音很好听。照片上的她，很美。", "en": "But her voice on the phone was lovely. In the photo, she was beautiful."},
	"STORY_8": {"zh_CN": "报酬，也不算少。", "en": "And the money wasn't bad."},
	"STORY_9": {"zh_CN": "他不知道，那个女人，已经死了。", "en": "He didn't know the woman was already dead."},
	"STORY_10": {"zh_CN": "而开门的男人，看见他的墨镜和盲杖，忽然笑了。", "en": "And the man who opened the door looked at his dark glasses and his white cane, and smiled."},
	"STORY_SKIP": {"zh_CN": "按住 空格 跳过", "en": "Hold SPACE to skip"},
	# ---- the man's whispers (subtitles; audio in assets/audio/voice)
	"WHISPER_1": {"zh_CN": "我看见你了。", "en": "I see you."},
	"WHISPER_2": {"zh_CN": "你看得见……对吧？", "en": "You can see… can't you?"},
	"WHISPER_3": {"zh_CN": "别回头。", "en": "Don't look back."},
	"WHISPER_4": {"zh_CN": "继续弹。", "en": "Keep playing."},
	"WHISPER_5": {"zh_CN": "嘘……", "en": "Shh…"},
	"WHISPER_6": {"zh_CN": "她还在等你。", "en": "She's still waiting for you."},
	"WHISPER_7": {"zh_CN": "你在发抖。", "en": "You're shaking."},
	"WHISPER_8": {"zh_CN": "别出声。", "en": "Don't make a sound."},
	"WHISPER_9": {"zh_CN": "下一个，就是你。", "en": "You're next."},
	"WHISPER_10": {"zh_CN": "睁开眼睛。", "en": "Open your eyes."},
	"WHISPER_11": {"zh_CN": "你不是瞎子。", "en": "You're not blind."},
	"WHISPER_12": {"zh_CN": "进来吧。", "en": "Come in."},
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

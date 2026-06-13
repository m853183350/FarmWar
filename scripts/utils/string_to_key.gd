## 字符串转按键的工具函数。
## 包含所有的鼠标和键盘按键映射，方便从配置文件中直接使用字符串来指定按键。


extends RefCounted


# ============================================================
# 9. 静态方法 — 字符串转按键


static func _string_to_key(s: String) -> Key:
	match s:
		# 字母
		"A": return KEY_A
		"B": return KEY_B
		"C": return KEY_C
		"D": return KEY_D
		"E": return KEY_E
		"F": return KEY_F
		"G": return KEY_G
		"H": return KEY_H
		"I": return KEY_I
		"J": return KEY_J
		"K": return KEY_K
		"L": return KEY_L
		"M": return KEY_M
		"N": return KEY_N
		"O": return KEY_O
		"P": return KEY_P
		"Q": return KEY_Q
		"R": return KEY_R
		"S": return KEY_S
		"T": return KEY_T
		"U": return KEY_U
		"V": return KEY_V
		"W": return KEY_W
		"X": return KEY_X
		"Y": return KEY_Y
		"Z": return KEY_Z
		
		# 数字
		"0": return KEY_0
		"1": return KEY_1
		"2": return KEY_2
		"3": return KEY_3
		"4": return KEY_4
		"5": return KEY_5
		"6": return KEY_6
		"7": return KEY_7
		"8": return KEY_8
		"9": return KEY_9

		# 数字
		"KEY_0": return KEY_0
		"KEY_1": return KEY_1
		"KEY_2": return KEY_2
		"KEY_3": return KEY_3
		"KEY_4": return KEY_4
		"KEY_5": return KEY_5
		"KEY_6": return KEY_6
		"KEY_7": return KEY_7
		"KEY_8": return KEY_8
		"KEY_9": return KEY_9
		
		# 功能键
		"ESCAPE": return KEY_ESCAPE
		"BACKSPACE": return KEY_BACKSPACE
		"TAB": return KEY_TAB
		"ENTER": return KEY_ENTER
		"KP_ENTER": return KEY_KP_ENTER
		"SHIFT": return KEY_SHIFT
		"CTRL": return KEY_CTRL
		"CONTROL": return KEY_CTRL
		"ALT": return KEY_ALT
		"PAUSE": return KEY_PAUSE
		"CAPSLOCK": return KEY_CAPSLOCK
		"PRINT": return KEY_PRINT
		"SCROLLLOCK": return KEY_SCROLLLOCK
		"NUMLOCK": return KEY_NUMLOCK
		"INSERT": return KEY_INSERT
		"HOME": return KEY_HOME
		"END": return KEY_END
		"PAGEUP": return KEY_PAGEUP
		"PAGEDOWN": return KEY_PAGEDOWN
		"DELETE": return KEY_DELETE
		"SPACE": return KEY_SPACE
		
		# 方向键
		"UP": return KEY_UP
		"DOWN": return KEY_DOWN
		"LEFT": return KEY_LEFT
		"RIGHT": return KEY_RIGHT
		
		# F键
		"F1": return KEY_F1
		"F2": return KEY_F2
		"F3": return KEY_F3
		"F4": return KEY_F4
		"F5": return KEY_F5
		"F6": return KEY_F6
		"F7": return KEY_F7
		"F8": return KEY_F8
		"F9": return KEY_F9
		"F10": return KEY_F10
		"F11": return KEY_F11
		"F12": return KEY_F12
		"F13": return KEY_F13
		"F14": return KEY_F14
		"F15": return KEY_F15
		"F16": return KEY_F16
		"F17": return KEY_F17
		"F18": return KEY_F18
		"F19": return KEY_F19
		"F20": return KEY_F20
		"F21": return KEY_F21
		"F22": return KEY_F22
		"F23": return KEY_F23
		"F24": return KEY_F24
		
		# 数字键盘
		"KP_0": return KEY_KP_0
		"KP_1": return KEY_KP_1
		"KP_2": return KEY_KP_2
		"KP_3": return KEY_KP_3
		"KP_4": return KEY_KP_4
		"KP_5": return KEY_KP_5
		"KP_6": return KEY_KP_6
		"KP_7": return KEY_KP_7
		"KP_8": return KEY_KP_8
		"KP_9": return KEY_KP_9
		"KP_MULTIPLY": return KEY_KP_MULTIPLY
		"KP_ADD": return KEY_KP_ADD  
		"KP_MINUS": return KEY_KP_SUBTRACT  
		"KP_PERIOD": return KEY_KP_PERIOD
		"KP_DIVIDE": return KEY_KP_DIVIDE
		"KP_ENTER": return KEY_KP_ENTER
		
		# 符号键
		"APOSTROPHE": return KEY_APOSTROPHE
		"COMMA": return KEY_COMMA
		"MINUS": return KEY_MINUS
		"PERIOD": return KEY_PERIOD
		"SLASH": return KEY_SLASH
		"SEMICOLON": return KEY_SEMICOLON
		"EQUAL": return KEY_EQUAL
		"LEFT_BRACKET": return KEY_BRACKETLEFT 
		"BACKSLASH": return KEY_BACKSLASH
		"RIGHT_BRACKET": return KEY_BRACKETRIGHT
		"APOSTROPHE": return KEY_APOSTROPHE
		"QUOTELEFT": return KEY_QUOTELEFT
		# 特殊系统键
		
		_: 
			push_error("Util: 无法识别的键盘按键名: '%s'" % s)
			return KEY_NONE

static func _string_to_mouse_button(s: String) -> MouseButton:
	match s:
		"MOUSE_BUTTON_LEFT": return MOUSE_BUTTON_LEFT
		"MOUSE_BUTTON_RIGHT": return MOUSE_BUTTON_RIGHT
		"MOUSE_BUTTON_MIDDLE": return MOUSE_BUTTON_MIDDLE
		"MOUSE_BUTTON_WHEEL_UP": return MOUSE_BUTTON_WHEEL_UP
		"MOUSE_BUTTON_WHEEL_DOWN": return MOUSE_BUTTON_WHEEL_DOWN
		"MOUSE_BUTTON_WHEEL_LEFT": return MOUSE_BUTTON_WHEEL_LEFT
		"MOUSE_BUTTON_WHEEL_RIGHT": return MOUSE_BUTTON_WHEEL_RIGHT
		"MOUSE_BUTTON_XBUTTON1": return MOUSE_BUTTON_XBUTTON1
		"MOUSE_BUTTON_XBUTTON2": return MOUSE_BUTTON_XBUTTON2
		_:
			push_error("CameraController: 无法识别的鼠标按键名: %s" % s)
			return MOUSE_BUTTON_NONE

class_name Cards

## 花札48枚の定義。1枚は Dictionary:
##   id: "1a" など / month: 1〜12 / kind: KIND_* / name: 札の名前 / tags: 役に使う印（"aka" 赤短, "ao" 青短 など）
## 山札にはこの Dictionary の複製を入れる（強化で書き換えるため）。

enum { KIND_KASU, KIND_TAN, KIND_TANE, KIND_HIKARI }

const KIND_NAMES := ["カス", "短冊", "タネ", "光"]
## 札1枚のチップ（点の元）
const KIND_CHIPS := [3, 6, 8, 15]
const MONTH_NAMES := ["", "松", "梅", "桜", "藤", "菖蒲", "牡丹", "萩", "芒", "菊", "紅葉", "柳", "桐"]

## [月, 種類, 名前, 印]
const DEFS := [
	[1, KIND_HIKARI, "松に鶴", []], [1, KIND_TAN, "松に赤短", ["aka"]], [1, KIND_KASU, "松のカス", []], [1, KIND_KASU, "松のカス", []],
	[2, KIND_TANE, "梅に鶯", []], [2, KIND_TAN, "梅に赤短", ["aka"]], [2, KIND_KASU, "梅のカス", []], [2, KIND_KASU, "梅のカス", []],
	[3, KIND_HIKARI, "桜に幕", ["maku"]], [3, KIND_TAN, "桜に赤短", ["aka"]], [3, KIND_KASU, "桜のカス", []], [3, KIND_KASU, "桜のカス", []],
	[4, KIND_TANE, "藤に不如帰", []], [4, KIND_TAN, "藤に短冊", []], [4, KIND_KASU, "藤のカス", []], [4, KIND_KASU, "藤のカス", []],
	[5, KIND_TANE, "菖蒲に八橋", []], [5, KIND_TAN, "菖蒲に短冊", []], [5, KIND_KASU, "菖蒲のカス", []], [5, KIND_KASU, "菖蒲のカス", []],
	[6, KIND_TANE, "牡丹に蝶", ["cho"]], [6, KIND_TAN, "牡丹に青短", ["ao"]], [6, KIND_KASU, "牡丹のカス", []], [6, KIND_KASU, "牡丹のカス", []],
	[7, KIND_TANE, "萩に猪", ["ino"]], [7, KIND_TAN, "萩に短冊", []], [7, KIND_KASU, "萩のカス", []], [7, KIND_KASU, "萩のカス", []],
	[8, KIND_HIKARI, "芒に月", ["tsuki"]], [8, KIND_TANE, "芒に雁", []], [8, KIND_KASU, "芒のカス", []], [8, KIND_KASU, "芒のカス", []],
	[9, KIND_TANE, "菊に盃", ["sake"]], [9, KIND_TAN, "菊に青短", ["ao"]], [9, KIND_KASU, "菊のカス", []], [9, KIND_KASU, "菊のカス", []],
	[10, KIND_TANE, "紅葉に鹿", ["shika"]], [10, KIND_TAN, "紅葉に青短", ["ao"]], [10, KIND_KASU, "紅葉のカス", []], [10, KIND_KASU, "紅葉のカス", []],
	[11, KIND_HIKARI, "柳に小野道風", ["ame"]], [11, KIND_TANE, "柳に燕", []], [11, KIND_TAN, "柳に短冊", []], [11, KIND_KASU, "柳に雷", []],
	[12, KIND_HIKARI, "桐に鳳凰", []], [12, KIND_KASU, "桐のカス", []], [12, KIND_KASU, "桐のカス", []], [12, KIND_KASU, "桐のカス", []],
]

static var _serial := 0


static func make(d: Array, index: int) -> Dictionary:
	_serial += 1
	return {
		"uid": _serial,
		# 絵は月ごとの4枚の何枚目か（art_index）で決まる
		"art": "%d_%d" % [d[0], index % 4],
		"month": d[0], "kind": d[1], "name": d[2], "tags": (d[3] as Array).duplicate(),
		"bonus": 0,      # 強化で足されたチップ
		"gold": false,   # 金箔：倍率+2
	}


static func full_deck() -> Array:
	var deck := []
	for i in DEFS.size():
		deck.append(make(DEFS[i], i))
	return deck


static func copy(c: Dictionary) -> Dictionary:
	_serial += 1
	var n := c.duplicate(true)
	n["uid"] = _serial
	return n


static func chips(c: Dictionary) -> int:
	return KIND_CHIPS[c.kind] + c.bonus


static func label(c: Dictionary) -> String:
	return "%d月 %s" % [c.month, c.name]

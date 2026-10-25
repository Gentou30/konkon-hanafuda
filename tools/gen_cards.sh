#!/usr/bin/env bash
# 花札の絵（月ごとに4枚を横に並べた1枚の画像）。split で4枚に分ける
cd ~/Projects/konkon-hanafuda
C="Exactly four traditional Japanese hanafuda playing cards for one month, laid out side by side in a single horizontal row with clear empty gaps between them, every card upright and the same size (portrait rectangle, aspect 2:3), each card has a thin cream-white border and rounded corners, flat bold traditional hanafuda art style with bright red, black, gold and green, crisp and readable, slightly cute. Plain flat pure green (#00FF00) background around the cards. No text, no letters, no numbers. Cards from left to right:"
months=(
"1|January pine: (1) bright card: pine tree with a red-crowned crane and a big red sun; (2) pine with a red poetry ribbon (red tanzaku with black writing-like marks); (3) plain pine branches and red sky; (4) plain pine branches and red sky, slightly different."
"2|February plum: (1) red plum blossoms with a green bush warbler bird; (2) plum blossoms with a red poetry ribbon (red tanzaku); (3) plain red plum blossoms; (4) plain red plum blossoms, slightly different."
"3|March cherry: (1) bright card: cherry blossoms with a red and white festival curtain (maku); (2) cherry blossoms with a red poetry ribbon (red tanzaku); (3) plain pink cherry blossoms; (4) plain pink cherry blossoms, slightly different."
"4|April wisteria: (1) hanging purple wisteria with a cuckoo bird flying in front of a crescent moon; (2) wisteria with a plain red ribbon (tanzaku without writing); (3) plain hanging wisteria; (4) plain hanging wisteria, slightly different."
"5|May iris: (1) purple irises with a wooden zigzag plank bridge (yatsuhashi); (2) irises with a plain red ribbon; (3) plain purple irises; (4) plain purple irises, slightly different."
"6|June peony: (1) big red peonies with two butterflies; (2) peonies with a blue poetry ribbon (blue tanzaku); (3) plain red peonies; (4) plain red peonies, slightly different."
"7|July bush clover: (1) red bush clover (hagi) with a charging wild boar; (2) bush clover with a plain red ribbon; (3) plain bush clover; (4) plain bush clover, slightly different."
"8|August pampas grass: (1) bright card: susuki pampas grass hill with a huge full moon on a red sky; (2) pampas grass hill with three wild geese flying; (3) plain pampas grass hill; (4) plain pampas grass hill, slightly different."
"9|September chrysanthemum: (1) yellow chrysanthemums with a red lacquer sake cup with the kotobuki symbol; (2) chrysanthemums with a blue poetry ribbon (blue tanzaku); (3) plain chrysanthemums; (4) plain chrysanthemums, slightly different."
"10|October maple: (1) red maple leaves with a deer looking back; (2) maple leaves with a blue poetry ribbon (blue tanzaku); (3) plain red maple leaves; (4) plain red maple leaves, slightly different."
"11|November willow and rain: (1) bright card: a man in old court clothes holding a red umbrella under a willow in the rain, with a frog jumping; (2) willow with a swallow flying; (3) willow with a plain red ribbon; (4) a black and red lightning drum card (oni's thunder drum and lightning on a dark background)."
"12|December paulownia: (1) bright card: a colorful phoenix (houou) under paulownia flowers; (2) plain paulownia leaves and purple flowers; (3) plain paulownia leaves and purple flowers; (4) plain paulownia leaves with a yellow band."
)
run(){ for m in "$@"; do n="${m%%|*}"; d="${m#*|}"; tools/gen_image.sh "art/raw/cards_$n.png" "$C $d" & done; wait; }
run "${months[@]:0:6}"
run "${months[@]:6:6}"
